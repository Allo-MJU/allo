/** Real local Auth + Functions + RTDB emulator integration; never uses a live project. */
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const project = process.env.GCLOUD_PROJECT || 'demo-allo-auth';
assert.ok(project.startsWith('demo-'), 'Only demo projects are allowed');
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const dbHost = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';
assert.match(authHost, /^(127\.0\.0\.1|localhost):\d+$/);
assert.match(dbHost, /^(127\.0\.0\.1|localhost):\d+$/);
const namespace = `${project}-default-rtdb`;
async function identity() {
  const response = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local-only`, {
    method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({returnSecureToken: true}),
  });
  assert.equal(response.status, 200);
  return response.json();
}
async function call(name, token, data) {
  const response = await fetch(`http://127.0.0.1:5001/${project}/asia-northeast3/${name}`, {
    method: 'POST', headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})},
    body: JSON.stringify({data}),
  });
  return {status: response.status, ...(await response.json())};
}
async function db(path, token, method = 'GET', body) {
  const response = await fetch(`http://${dbHost}/${path}.json?ns=${namespace}${token && token !== 'owner' ? `&auth=${token}` : ''}`, {
    method, headers: {'Content-Type': 'application/json', ...(token === 'owner' ? {Authorization: 'Bearer owner'} : {})},
    ...(body === undefined ? {} : {body: JSON.stringify(body)}),
  });
  return {status: response.status, value: await response.json()};
}
function denied(response) { assert.ok([401, 403].includes(response.status), JSON.stringify(response)); }
function ok(response) { assert.equal(response.status, 200, JSON.stringify(response)); }
const carEvent = () => ({ts: Date.now(), by: 'car', type: 'fishingRequested', payload: {action: 'start'}});

test('authenticated session lifecycle and server-enforced writer isolation', async t => {
  const car = await identity(), phone = await identity(), stranger = await identity();
  const sid = randomUUID(), path = `sessions/${sid}`;
  let meta;
  await t.test('unauthenticated session creation is denied', async () => {
    const r = await call('createVehicleSession', null, {sessionId: sid, carAppVersion: 'test'});
    assert.equal(r.error.status, 'UNAUTHENTICATED');
  });
  await t.test('car creates server-owned metadata and retries idempotently', async () => {
    const r = await call('createVehicleSession', car.idToken, {sessionId: sid, carAppVersion: 'test'});
    ok(r); meta = r.result; assert.match(meta.pairCode, /^\d{6}$/); assert.equal(meta.paired, false);
    assert.ok(Math.abs(Date.now() - meta.createdAt) < 10000);
    const retry = await call('createVehicleSession', car.idToken, {sessionId: sid, carAppVersion: 'different'});
    assert.deepEqual(retry.result, meta);
    const other = await call('createVehicleSession', stranger.idToken, {sessionId: sid, carAppVersion: 'test'});
    assert.equal(other.error.status, 'PERMISSION_DENIED');
  });
  await t.test('no root, list, private ACL, or pre-pair metadata reads', async () => {
    denied(await db(path, car.idToken)); denied(await db('sessions', car.idToken));
    denied(await db(`${path}/acl`, car.idToken)); denied(await db(`${path}/pairing`, car.idToken));
    denied(await db(`${path}/meta`, null)); denied(await db(`${path}/meta`, phone.idToken));
    ok(await db(`${path}/meta`, car.idToken));
  });
  await t.test('clients cannot self-create sessions or rewrite ACL/meta/paired', async () => {
    denied(await db(`sessions/${randomUUID()}`, car.idToken, 'PUT', {acl: {carUid: car.localId}, meta}));
    denied(await db(`${path}/acl/phoneUid`, phone.idToken, 'PUT', phone.localId));
    denied(await db(`${path}/meta/paired`, phone.idToken, 'PUT', true));
    denied(await db(`${path}/meta/createdAt`, car.idToken, 'PUT', Date.now()));
  });
  await t.test('wrong pairing code commits failed attempt without granting read', async () => {
    const wrong = meta.pairCode === '000000' ? '000001' : '000000';
    const r = await call('joinVehicleSession', phone.idToken, {sessionId: sid, pairCode: wrong});
    assert.equal(r.error.status, 'PERMISSION_DENIED');
    assert.equal((await db(`${path}/pairing/attempts`, 'owner')).value, 1);
    denied(await db(`${path}/game`, phone.idToken));
  });
  await t.test('car cannot claim phone role and one phone can join once', async () => {
    const self = await call('joinVehicleSession', car.idToken, {sessionId: sid, pairCode: meta.pairCode});
    assert.equal(self.error.status, 'PERMISSION_DENIED');
    const first = await call('joinVehicleSession', phone.idToken, {sessionId: sid, pairCode: meta.pairCode});
    ok(first); assert.equal(first.result.paired, true);
    const retry = await call('joinVehicleSession', phone.idToken, {sessionId: sid, pairCode: meta.pairCode});
    ok(retry);
    await db(`${path}/pairing/expiresAt`, 'owner', 'PUT', Date.now() - 1);
    ok(await call('joinVehicleSession', phone.idToken, {sessionId: sid, pairCode: meta.pairCode}));
    const takeover = await call('joinVehicleSession', stranger.idToken, {sessionId: sid, pairCode: meta.pairCode});
    assert.equal(takeover.error.status, 'PERMISSION_DENIED');
    const events = (await db(`${path}/events`, 'owner')).value;
    assert.equal(Object.values(events).filter(e => e.type === 'paired').length, 1);
  });
  await t.test('both participants can read shared state but stranger cannot', async () => {
    for (const key of ['meta', 'vehicle', 'game', 'events']) {
      ok(await db(`${path}/${key}`, car.idToken)); ok(await db(`${path}/${key}`, phone.idToken));
      denied(await db(`${path}/${key}`, stranger.idToken));
    }
  });
  await t.test('only car writes vehicle; only bound phone writes game', async () => {
    const v = {ts: Date.now(), gear: 'P', fishingPresence: {version: 1, active: true}};
    const g = {ts: Date.now(), stage: 'idle', fishing: {version: 1, totalRecords: 1}};
    ok(await db(`${path}/vehicle`, car.idToken, 'PUT', v));
    ok(await db(`${path}/game`, phone.idToken, 'PUT', g));
    denied(await db(`${path}/vehicle`, phone.idToken, 'PUT', v));
    denied(await db(`${path}/game`, car.idToken, 'PUT', g));
    denied(await db(`${path}/game`, stranger.idToken, 'PUT', g));
    denied(await db(`${path}/vehicle`, car.idToken, 'DELETE'));
    denied(await db(`${path}/game`, phone.idToken, 'DELETE'));
    denied(await db(path, phone.idToken, 'PATCH', {vehicle: v, game: g}));
  });
  await t.test('location and malformed/stale writes are denied', async () => {
    denied(await db(`${path}/vehicle`, car.idToken, 'PUT', {ts: Date.now(), gear: 'P', latitude: 37}));
    denied(await db(`${path}/vehicle`, car.idToken, 'PUT', {gear: 'P'}));
    denied(await db(`${path}/game`, phone.idToken, 'PUT', {ts: Date.now() - 600000, stage: 'idle'}));
  });
  await t.test('events are append-only and sender/type bound', async () => {
    ok(await db(`${path}/events/car1`, car.idToken, 'PUT', carEvent()));
    denied(await db(`${path}/events/car1`, car.idToken, 'PUT', carEvent()));
    denied(await db(`${path}/events/car1`, car.idToken, 'DELETE'));
    denied(await db(`${path}/events/spoof`, phone.idToken, 'PUT', carEvent()));
    denied(await db(`${path}/events/end-spoof`, phone.idToken, 'PUT', {ts: Date.now(), by: 'phone', type: 'sessionEnd'}));
    denied(await db(`${path}/events/pair-spoof`, phone.idToken, 'PUT', {ts: Date.now(), by: 'phone', type: 'paired'}));
    ok(await db(`${path}/events/phone1`, phone.idToken, 'PUT', {ts: Date.now(), by: 'phone', type: 'hatched'}));
  });
  await t.test('sessionEnd blocks new join/reconnect and recreating same session', async () => {
    ok(await db(`${path}/events/end`, car.idToken, 'PUT', {ts: Date.now(), by: 'car', type: 'sessionEnd'}));
    const join = await call('joinVehicleSession', phone.idToken, {sessionId: sid, pairCode: meta.pairCode});
    assert.equal(join.error.status, 'PERMISSION_DENIED');
    const create = await call('createVehicleSession', car.idToken, {sessionId: sid, carAppVersion: 'test'});
    assert.equal(create.error.status, 'PERMISSION_DENIED');
    assert.equal((await call('renewVehiclePairing', car.idToken, {sessionId: sid, requestId: randomUUID()})).error.status, 'PERMISSION_DENIED');
    // Existing phone may publish its final saved summary after receiving sessionEnd.
    ok(await db(`${path}/game`, phone.idToken, 'PUT', {ts: Date.now(), stage: 'idle'}));
  });
  await t.test('expired session denies reads and writes even for owners', async () => {
    ok(await db(`${path}/meta/createdAt`, 'owner', 'PUT', Date.now() - 86400001));
    denied(await db(`${path}/game`, car.idToken));
    denied(await db(`${path}/game`, phone.idToken, 'PUT', {ts: Date.now(), stage: 'idle'}));
    denied(await db(`${path}/vehicle`, car.idToken, 'PUT', {ts: Date.now(), gear: 'P'}));
  });
  await t.test('pairing locks after five wrong attempts and cannot reset by create retry', async () => {
    const id = randomUUID(); const created = await call('createVehicleSession', car.idToken, {sessionId: id, carAppVersion: 'test'}); ok(created);
    const wrong = created.result.pairCode === '000000' ? '000001' : '000000';
    for (let i = 0; i < 5; i++) assert.equal((await call('joinVehicleSession', stranger.idToken, {sessionId: id, pairCode: wrong})).error.status, 'PERMISSION_DENIED');
    ok(await call('createVehicleSession', car.idToken, {sessionId: id, carAppVersion: 'test'}));
    assert.equal((await db(`sessions/${id}/pairing/attempts`, 'owner')).value, 5);
    assert.equal((await call('joinVehicleSession', phone.idToken, {sessionId: id, pairCode: created.result.pairCode})).error.status, 'PERMISSION_DENIED');
  });
  await t.test('expired pairing denies a new phone even with correct code', async () => {
    const id = randomUUID(); const created = await call('createVehicleSession', car.idToken, {sessionId: id, carAppVersion: 'test'}); ok(created);
    await db(`sessions/${id}/pairing/expiresAt`, 'owner', 'PUT', Date.now() - 1);
    assert.equal((await call('joinVehicleSession', phone.idToken, {sessionId: id, pairCode: created.result.pairCode})).error.status, 'PERMISSION_DENIED');
  });
  await t.test('session creation quota is server-enforced per identity', async () => {
    await db(`sessionCreationLimits/${stranger.localId}`, 'owner', 'PUT', {windowAt: Date.now(), count: 20});
    const result = await call('createVehicleSession', stranger.idToken, {sessionId: randomUUID(), carAppVersion: 'test'});
    assert.equal(result.error.status, 'RESOURCE_EXHAUSTED');
  });
  await t.test('simultaneous claims produce exactly one phone owner', async () => {
    const id = randomUUID(); const created = await call('createVehicleSession', car.idToken, {sessionId: id, carAppVersion: 'test'}); ok(created);
    const results = await Promise.all([phone, stranger].map(user => call('joinVehicleSession', user.idToken, {sessionId: id, pairCode: created.result.pairCode})));
    assert.equal(results.filter(r => r.status === 200).length, 1);
    assert.equal(Object.keys((await db(`sessions/${id}/events`, 'owner')).value).length, 1);
  });
  await t.test('owner can renew locked pairing once per request without extending session TTL', async () => {
    const id = randomUUID(); const created = await call('createVehicleSession', car.idToken, {sessionId: id, carAppVersion: 'test'}); ok(created);
    const route = `sessions/${id}`;
    await db(`${route}/pairing/attempts`, 'owner', 'PUT', 5);
    await db(`${route}/pairing/expiresAt`, 'owner', 'PUT', Date.now() - 1);
    const requestId = randomUUID();
    assert.equal((await call('renewVehiclePairing', stranger.idToken, {sessionId: id, requestId})).error.status, 'PERMISSION_DENIED');
    const renewed = await call('renewVehiclePairing', car.idToken, {sessionId: id, requestId}); ok(renewed);
    assert.notEqual(renewed.result.pairCode, created.result.pairCode);
    assert.equal(renewed.result.createdAt, created.result.createdAt);
    let pairing = (await db(`${route}/pairing`, 'owner')).value;
    assert.equal(pairing.attempts, 0); assert.equal(pairing.renewals, 1);
    assert.ok(pairing.expiresAt > Date.now()); const expiry = pairing.expiresAt;
    assert.equal((await call('joinVehicleSession', phone.idToken, {sessionId: id, pairCode: created.result.pairCode})).error.status, 'PERMISSION_DENIED');
    const retry = await call('renewVehiclePairing', car.idToken, {sessionId: id, requestId}); ok(retry);
    assert.equal(retry.result.pairCode, renewed.result.pairCode);
    pairing = (await db(`${route}/pairing`, 'owner')).value;
    assert.equal(pairing.attempts, 1); assert.equal(pairing.expiresAt, expiry); assert.equal(pairing.renewals, 1);
    ok(await call('joinVehicleSession', phone.idToken, {sessionId: id, pairCode: renewed.result.pairCode}));
    assert.equal((await call('renewVehiclePairing', car.idToken, {sessionId: id, requestId: randomUUID()})).error.status, 'PERMISSION_DENIED');
    assert.equal((await db(`${route}/acl/phoneUid`, 'owner')).value, phone.localId);
  });
  await t.test('renewal is bounded and old request retries never rotate again', async () => {
    const id = randomUUID(); ok(await call('createVehicleSession', car.idToken, {sessionId: id, carAppVersion: 'test'}));
    const firstId = randomUUID(); ok(await call('renewVehiclePairing', car.idToken, {sessionId: id, requestId: firstId}));
    let latest;
    for (let i = 1; i < 10; i++) { latest = await call('renewVehiclePairing', car.idToken, {sessionId: id, requestId: randomUUID()}); ok(latest); }
    assert.equal((await call('renewVehiclePairing', car.idToken, {sessionId: id, requestId: randomUUID()})).error.status, 'PERMISSION_DENIED');
    const retry = await call('renewVehiclePairing', car.idToken, {sessionId: id, requestId: firstId}); ok(retry);
    assert.equal(retry.result.pairCode, latest.result.pairCode);
    assert.equal((await db(`sessions/${id}/pairing/renewals`, 'owner')).value, 10);
  });
  await t.test('concurrent join and renewal cannot replace an already-bound phone', async () => {
    const id = randomUUID(); const created = await call('createVehicleSession', car.idToken, {sessionId: id, carAppVersion: 'test'}); ok(created);
    const [join, renew] = await Promise.all([
      call('joinVehicleSession', phone.idToken, {sessionId: id, pairCode: created.result.pairCode}),
      call('renewVehiclePairing', car.idToken, {sessionId: id, requestId: randomUUID()}),
    ]);
    assert.equal([join, renew].filter(r => r.status === 200).length, 1);
    const state = (await db(`sessions/${id}`, 'owner')).value;
    if (join.status === 200) { assert.equal(state.acl.phoneUid, phone.localId); assert.equal(state.meta.pairCode, created.result.pairCode); }
    else { assert.equal(state.acl.phoneUid, undefined); assert.notEqual(state.meta.pairCode, created.result.pairCode); }
  });

});
