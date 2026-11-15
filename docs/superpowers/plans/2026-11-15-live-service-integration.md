# Live service integration implementation plan

**Goal:** Build phone and vehicle APKs against the existing live Firebase project and the latest AWS AI API.

**Approved approach:** On 2026-11-15 the user chose the existing Firebase design with Blaze. Explain any newly discovered implementation or improvement before modifying it. Preserve the existing AWS host, credentials, photographs, SQLite data and unrelated TTS deployment work.

**Current status:** The user deferred APK work on 2026-11-15 to address newly identified feature changes. Stop further APK builds, distribution and device checks until that work is requested again. Existing build artifacts are intermediate results, not final deliverables.

## Resume record

- AWS AI API is running source `78bf749` in `/opt/allo-affinity/releases/78bf749`; existing environment, SQLite, photographs and Caddy were preserved. Actual HTTPS greeting and question returned `200`, `source: ai`; photo listing was unchanged.
- Firebase `allo-525bc` is Blaze. Anonymous Auth is enabled. All three existing Node 22 session callables are deployed in `asia-northeast3`, using the existing Singapore RTDB. Latest ACL database rules are deployed. Build-image cleanup is configured for seven days.
- Firebase emulator integration: 20/20 passed. Isolated live identities verified session creation, retry, renewal, pairing, takeover denial, vehicle/game synchronization and writer separation.
- The configured phone APK was installed on `ALLO_API_36` without deleting application data. Actual app pairing succeeded; its `incubating` game snapshot was read back through the isolated car identity. Cloud vehicle signal changes reached the app. In-app AI dialogue, physical QR scanning and audible STT/TTS are not yet verified.
- Source changes explained before implementation: show the full session ID for manual pairing; safely recover expired unpaired sessions only while parked; preserve late paired state and distinguish failed renewal from an authoritative read. Car regression suite: 348/348 passed. Independent review found the original two P2 issues resolved; the additional clock-skew/error-display case was also regression-tested and fixed.
- Feature edits remain uncommitted on `fix/live-service-integration-20261115`. No PR, push or merge was performed. Generated iOS changes from Flutter builds were removed separately.
- Ignored live configurations exist for phone, vehicle and Functions. Credentials are not in this record. Operational receipts are in the existing AWS deployment folder and `/private/tmp/allo-firebase-live-2yt0kzh5/`.
- Final APK packaging, final artifact provenance/signatures, vehicle screen rendering and complete device verification remain deferred. Existing `apk-20261115-live` contains an intermediate phone build; do not describe it as the final verified pair of APKs.

## 1. AI API release

- [x] Confirm the deployed companion endpoints are missing (authenticated requests return 404).
- [x] Run the current API tests (53) and bounded runtime tests (2).
- [x] Rehearse old → new → rollback with the same synthetic photograph and SQLite directory.
- [ ] Transfer the verified source archive through the pinned-host SSH/SSM connection.
- [ ] Stage a versioned release preserving repository-relative character data paths.
- [ ] Switch only the existing launcher; restart only `allo-affinity`; automatically restore the launcher on failed health checks.
- [ ] Verify authentication, old photo endpoints, actual AI greeting and follow-up over public HTTPS.

## 2. Firebase readiness

- [x] Confirm project `allo-525bc`, existing Singapore RTDB, Spark plan, uninitialized Auth, absent Functions and outdated live rules.
- [ ] Link an approved billing account / complete the Blaze transition. Payment entry and financial confirmation remain a user-controlled step when required by the browser tool.
- [ ] Enable anonymous authentication and obtain the existing registered Android app configuration without displaying credentials.
- [ ] Deploy the existing Node 22 session callables to `asia-northeast3` using the exact existing RTDB URL.
- [ ] Preserve existing data and deploy the repository's ACL rules; validate fresh sessions using isolated synthetic identities.
- [ ] Verify ownership, pairing, vehicle/game writer separation, renewal and invalid-code rejection against the live project.

## 3. Apps and final verification

- [ ] Generate ignored phone and vehicle configuration from the same project. Include the existing HTTPS AI endpoint/token in the phone config; never include provider keys.
- [ ] Build phone release with `FEED=firebase` and the latest Unity export; rebuild the vehicle release with matching settings.
- [ ] Verify APK signatures, packaged Unity/data and source/config provenance without logging configuration values.
- [ ] Exercise app startup, cloud pairing, snapshot sync, AI response and available device speech services. Distinguish REST/emulator evidence from physical-device and actual-car verification.
- [ ] Record evidence and remaining hardware-only limits; obtain an independent review of any code changes.

## Known decision points

- Do not replace Firebase with an AWS session implementation or change gameplay rules.
- Do not deploy or reconfigure the separately prepared cloud TTS service as an incidental change. Current direct AI speech uses Android TTS; vehicle plaza has bundled WAV fallback.
- If the current implementation fails verification, report the concrete problem, proposed minimal change and regression check before changing product code.
