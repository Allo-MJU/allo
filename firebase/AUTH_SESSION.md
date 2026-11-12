# Authenticated vehicle / phone session contract

Both clients sign in with Firebase Anonymous Authentication and retain their own UID. A UID is a device/session participant identity, not a verified human, child, parent, or physically attested car. An existing non-anonymous login is not silently replaced. No service-account secret is shipped to either client.

## Trusted callables

Configured deployment region: `asia-northeast3`. All three callables require a valid Firebase anonymous Auth ID token. RTDB rules alone never grant pairing based on a client-written code or role.

- `createVehicleSession({sessionId, carAppVersion})`: UUID supplied by the car provides retry idempotency. Server assigns a random 6-digit code and server timestamp, sets `acl.carUid` to the caller UID, and returns `{sessionId,createdAt,pairCode,paired,carAppVersion}`. Existing live non-ended session may be retried only by that car UID. New creation limited to 20 per UID per hour. Failed creation races may consume quota, never transfer ownership.
- `joinVehicleSession({sessionId,pairCode})`: server transaction validates code, session lifetime and termination. It atomically binds one `acl.phoneUid`, sets `meta.paired`, and appends one paired event. The car UID cannot also be the phone. Same phone UID/code retries return current metadata without duplicate paired events. Another phone cannot replace the first.
- A new phone must join within 10 minutes of session creation. Five incorrect codes lock further new claims for that session. Attempts are counted across identities for that session and committed even when the callable returns an error. Create retry cannot reset code, expiry, or attempts. The owning unpaired car can use `renewVehiclePairing` to recover, or create a new vehicle session; this is intentionally fail-closed and can be denied by someone who knows the session UUID and consumes the attempt budget.
- Already-bound phone may reconnect with the same UID/code after the pairing window, up to the session's 24-hour lifetime. Losing local auth state creates a new UID: it cannot reclaim an old session. Ended/expired session requires a new session. Error details do not distinguish unknown/wrong/claimed/locked session to avoid an ownership oracle.

## RTDB access

No root/list/whole-session reads. Participants may read only their session's `meta`, `vehicle`, `game`, and `events`. `acl`, private `pairing`, and creation quota records are backend-only.

| Path | Client writer |
| --- | --- |
| `vehicle` | Owning car UID |
| `game` | Bound phone UID |
| `meta`, `acl`, `pairing` | Server only |
| `events/<id>` | Append only; authenticated role must match `by` and allowed event type |

Car events: `sessionEnd`, `destinationSuggest`, `companionTransferRequested`, `fishingRequested`. Phone events: `hatched`, `lookOutPrompt`. `paired` is server-only. Overwrite/deletion of event records is rejected. Mixed-role root PATCH is rejected. Vehicle/game deletion is rejected. Required timestamp and basic fields are validated; client timestamps outside ±5 minutes are rejected. Direct vehicle latitude/longitude fields remain rejected. This is role isolation and minimum wire validation, not a complete arbitrary-payload schema or recursive PII filter.

Access expires 24 hours after immutable server creation time. A `sessionEnd` event prevents joining/rejoining/recreating the same session; already bound clients may still read and the phone may publish its final saved game summary until TTL. Ending a session is not immediate ACL revocation. If instant revocation is later required, add an explicit server lifecycle while preserving final-save acknowledgement.

## Configuration and deployment prerequisites

Enable Anonymous Authentication in the selected Firebase project. Functions and both clients must use the same project and exact RTDB instance. `SESSION_DATABASE_URL` may be set as a Functions environment variable for the exact database root URL; otherwise Firebase Admin's project config is used. For the local demo project, Functions explicitly uses `<project>-default-rtdb`, matching the namespace where the CLI loads rules. An unintended second namespace can otherwise have emulator-default rules.

Functions use Node 22 and locked npm dependencies. Deployment generally requires the Firebase plan/permissions needed for Cloud Functions. No deployment, billing, Auth-console changes, App Check enforcement changes, or live rules updates are performed by this implementation.

Production abuse controls remain a deployment concern: per-UID creation quota and per-session attempt count do not stop an attacker creating many anonymous identities. App Check/attestation and project quota/rate monitoring should be selected for the actual supported devices; this implementation does not claim physical device attestation or parent approval.

## Local verification

Use the official Firebase CLI and supported Java runtime. From `firebase/`:

```sh
npm ci --prefix functions
firebase emulators:exec --only auth,database,functions --project demo-allo-auth \
  'node --test tests/session-auth.test.mjs'
```

The test refuses non-`demo-` projects and non-loopback emulator hosts. It uses the real local Auth token issuance, callable token validation, server transactions, and RTDB rules engine. Synthetic test data only. It covers denied unauth access, pre-pair secrecy, UID ownership, idempotency, root PATCH, writer separation, event spoof/overwrite/delete, stale data, attempt budget, expiry, termination, creation quota, and concurrent claims. It does not validate live project configuration, physical device token persistence, real network retries, or Pleos permissions.

Verified locally on 2026-11-11: 20 Node test results (19 scenario subtests plus the parent) passed, 0 failures, against Auth + Functions + RTDB emulators. Dependency installation audit reported 0 vulnerabilities.

## Unpaired QR renewal

`renewVehiclePairing({sessionId,requestId})` requires the same anonymous car UID. `requestId` is a fresh UUID retained for retries. One transaction checks owner + no bound phone + `meta.paired=false` + live/not-ended session, then rotates the 6-digit code, clears failed attempts, sets a new 10-minute pairing window and records the renewal ID. It never changes session creation time or 24-hour lifetime. It returns the same metadata shape as create/join.

Maximum 10 distinct renewals per session. All successful renewal IDs are retained (bounded to 10); retrying any accepted ID reads the current metadata without rotating code, extending expiry, clearing failed attempts, or consuming another renewal. With no intervening renewal this is exactly the original result. Another renewal may supersede the code, so late retries return current metadata rather than revive old credentials.

If a phone join races with renewal, the shared session transaction serializes both: join first prevents renewal and preserves the bound phone; renewal first invalidates the previous code and the old-code join fails. If a phone joins just after a completed renewal, the renewal response may fail closed while metadata subscription shows the completed pairing. Clients must retain the session and retry request ID until success; never clear a valid bound session on a renewal error.
