'use strict';
const {randomInt} = require('node:crypto');
const {initializeApp} = require('firebase-admin/app');
const {getDatabase} = require('firebase-admin/database');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const emulatorDatabaseUrl = process.env.FIREBASE_DATABASE_EMULATOR_HOST
  ? `https://${process.env.GCLOUD_PROJECT}-default-rtdb.firebaseio.com` : undefined;
const databaseURL = process.env.SESSION_DATABASE_URL || emulatorDatabaseUrl;
initializeApp(databaseURL ? {databaseURL} : undefined);
const options = {region: 'asia-northeast3', timeoutSeconds: 15, maxInstances: 10};
const SESSION_TTL = 24 * 60 * 60 * 1000;
const PAIR_TTL = 10 * 60 * 1000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function identity(request) {
  if (!request.auth || request.auth.token.firebase?.sign_in_provider !== 'anonymous') {
    throw new HttpsError('unauthenticated', 'Device authentication required.');
  }
  return request.auth.uid;
}
function sessionId(data) {
  if (!data || typeof data.sessionId !== 'string' || !UUID.test(data.sessionId)) {
    throw new HttpsError('invalid-argument', 'Invalid session identifier.');
  }
  return data.sessionId;
}
function live(value, now) {
  return value?.meta && Number.isSafeInteger(value.meta.createdAt) &&
    value.meta.createdAt <= now && now - value.meta.createdAt < SESSION_TTL;
}
function ended(value) {
  return Object.values(value.events || {}).some(e => e?.by === 'car' && e?.type === 'sessionEnd');
}
function response(sid, value) {
  return {sessionId: sid, createdAt: value.meta.createdAt, pairCode: value.meta.pairCode,
    paired: value.meta.paired, carAppVersion: value.meta.carAppVersion};
}
function unavailable() { return new HttpsError('permission-denied', 'Session is unavailable.'); }

exports.createVehicleSession = onCall(options, async request => {
  const uid = identity(request), sid = sessionId(request.data);
  const version = request.data.carAppVersion;
  if (typeof version !== 'string' || version.length < 1 || version.length > 64) {
    throw new HttpsError('invalid-argument', 'Invalid application version.');
  }
  const db = getDatabase(), ref = db.ref(`sessions/${sid}`), now = Date.now();
  const existing = (await ref.get()).val();
  if (existing) {
    if (existing.acl?.carUid !== uid || !live(existing, now) || ended(existing)) throw unavailable();
    return response(sid, existing);
  }
  // Limits new sessions per device identity; retries of an existing session are free.
  const quota = await db.ref(`sessionCreationLimits/${uid}`).transaction(current => {
    if (!current || now - current.windowAt >= 3600000) return {windowAt: now, count: 1};
    if (current.count >= 20) return;
    return {...current, count: current.count + 1};
  });
  if (!quota.committed) throw new HttpsError('resource-exhausted', 'Try again later.');
  const code = randomInt(0, 1000000).toString().padStart(6, '0');
  const result = await ref.transaction(current => current || {
    acl: {carUid: uid},
    meta: {createdAt: now, pairCode: code, paired: false, carAppVersion: version},
    pairing: {expiresAt: now + PAIR_TTL, attempts: 0},
  });
  const value = result.snapshot.val();
  if (value?.acl?.carUid !== uid || !live(value, Date.now()) || ended(value)) throw unavailable();
  return response(sid, value);
});

exports.joinVehicleSession = onCall(options, async request => {
  const uid = identity(request), sid = sessionId(request.data), code = request.data.pairCode;
  if (typeof code !== 'string' || !/^\d{6}$/.test(code)) {
    throw new HttpsError('invalid-argument', 'Invalid pairing code.');
  }
  const db = getDatabase(), ref = db.ref(`sessions/${sid}`), now = Date.now();
  const eventKey = ref.child('events').push().key;
  let accepted = false;
  await ref.transaction(current => {
    accepted = false; // Firebase may rerun this callback after contention.
    // A fresh Admin reference may initially have an empty local cache. Returning
    // null performs compare-and-swap and lets the server retry with real state;
    // aborting here would incorrectly reject every first join.
    if (current === null) return null;
    if (!live(current, now) || ended(current) || current.acl?.carUid === uid) return;
    const claimed = current.acl?.phoneUid;
    if (claimed) {
      // Idempotent reconnect only for the original phone and matching code.
      if (claimed === uid && current.meta.pairCode === code) accepted = true;
      return;
    }
    if (!current.pairing || current.pairing.expiresAt <= now || current.pairing.attempts >= 5) return;
    if (current.meta.pairCode !== code) {
      // Commit the attempt before returning a generic error; throwing here would roll it back.
      current.pairing.attempts += 1;
      return current;
    }
    current.acl.phoneUid = uid;
    current.meta.paired = true;
    current.events ||= {};
    current.events[eventKey] = {ts: now, type: 'paired', by: 'phone'};
    accepted = true;
    return current;
  });
  const value = (await ref.get()).val();
  if (!accepted || value?.acl?.phoneUid !== uid || !live(value, Date.now()) || ended(value)) throw unavailable();
  return response(sid, value);
});

exports.renewVehiclePairing = onCall(options, async request => {
  const uid = identity(request), sid = sessionId(request.data), requestId = request.data.requestId;
  if (typeof requestId !== 'string' || !UUID.test(requestId)) {
    throw new HttpsError('invalid-argument', 'Invalid renewal identifier.');
  }
  const ref = getDatabase().ref(`sessions/${sid}`), now = Date.now();
  let accepted = false;
  await ref.transaction(current => {
    accepted = false;
    // Resolve a cold local cache through server CAS, as in joinVehicleSession.
    if (current === null) return null;
    if (!live(current, now) || ended(current) || current.acl?.carUid !== uid ||
        current.acl?.phoneUid || current.meta.paired !== false || !current.pairing) return;
    const receipts = current.pairing.renewReceipts || {};
    if (receipts[requestId]) { accepted = true; return; }
    if ((current.pairing.renewals || 0) >= 10) return;
    // No accidental re-use of the just-invalidated code.
    let code;
    do { code = randomInt(0, 1000000).toString().padStart(6, '0'); }
    while (code === current.meta.pairCode);
    current.meta.pairCode = code;
    current.pairing.expiresAt = now + PAIR_TTL;
    current.pairing.attempts = 0;
    current.pairing.renewals = (current.pairing.renewals || 0) + 1;
    current.pairing.renewReceipts = {...receipts, [requestId]: true};
    accepted = true;
    return current;
  });
  const value = (await ref.get()).val();
  if (!accepted || value?.acl?.carUid !== uid || value.acl?.phoneUid ||
      value.meta?.paired !== false || !live(value, Date.now()) || ended(value)) throw unavailable();
  return response(sid, value);
});

exports.recordDestinationVisit = onCall(options, async request => {
  const uid = identity(request), data = request.data, sid = sessionId(data), now = Date.now();
  const fields = ['sessionId', 'visitId', 'routeRevision', 'placeId', 'placeName', 'regionTag', 'arrivedAtMs', 'companionIds'];
  const key = /^[a-zA-Z0-9_-]{1,100}$/;
  if (Object.keys(data).some(k => !fields.includes(k)) || fields.some(k => !(k in data)) ||
      !/^visit_[0-9a-f]{16}$/.test(data.visitId) || !/^route_[0-9a-f]{16,32}$/.test(data.routeRevision) ||
      !/^(place|poi|unknown)_[0-9a-f]{16}$/.test(data.placeId) ||
      typeof data.placeName !== 'string' || data.placeName.trim() !== data.placeName || !data.placeName.length || data.placeName.length > 120 ||
      !['coast', 'mountain', 'city', 'unknown'].includes(data.regionTag) ||
      !Number.isSafeInteger(data.arrivedAtMs) || data.arrivedAtMs <= 0 || data.arrivedAtMs > now + 300000 ||
      !Array.isArray(data.companionIds) || data.companionIds.length > 1 ||
      data.companionIds.some(id => typeof id !== 'string' || !key.test(id) || ['__proto__', 'prototype', 'constructor'].includes(id))) {
    throw new HttpsError('invalid-argument', 'Invalid visit.');
  }
  const db = getDatabase(), session = (await db.ref(`sessions/${sid}`).get()).val();
  if (!session?.acl?.phoneUid || session.acl.carUid !== uid || !Number.isSafeInteger(session.meta?.createdAt) ||
      data.arrivedAtMs < session.meta.createdAt || data.arrivedAtMs >= session.meta.createdAt + SESSION_TTL) throw unavailable();
  const visit = {sessionId: sid, routeRevision: data.routeRevision, placeId: data.placeId,
    placeName: data.placeName, regionTag: data.regionTag, arrivedAtMs: data.arrivedAtMs,
    companionIds: data.companionIds, evidence: 'destination-arrived'};
  const comparable = v => JSON.stringify([v.sessionId, v.routeRevision, v.placeId, v.placeName, v.regionTag, v.arrivedAtMs, v.companionIds || [], v.evidence]);
  let conflict = false;
  await db.ref(`travelHistory/${session.acl.phoneUid}`).transaction(current => {
    conflict = false;
    current ||= {}; current.visits ||= {}; current.places ||= {};
    const previous = current.visits[data.visitId];
    if (previous) { conflict = comparable(previous) !== comparable(visit); return; }
    const storedVisit = {...visit, receivedAtMs: now};
    current.visits[data.visitId] = storedVisit;
    for (const companionId of data.companionIds) {
      current.companions ||= {};
      const companion = current.companions[companionId] ||= {};
      companion.places ||= {};
      const latest = companion.places[data.placeId];
      if (!latest || data.arrivedAtMs > latest.arrivedAtMs) {
        companion.places[data.placeId] = {...storedVisit, visitId: data.visitId};
      }
    }
    const place = current.places[data.placeId];
    current.places[data.placeId] = {placeId: data.placeId, placeName: data.placeName, regionTag: data.regionTag,
      visitCount: (place?.visitCount || 0) + 1, lastArrivedAtMs: Math.max(place?.lastArrivedAtMs || 0, data.arrivedAtMs)};
    return current;
  });
  if (conflict) throw new HttpsError('already-exists', 'Visit identifier conflict.');
  return {visitId: data.visitId, recorded: true};
});
