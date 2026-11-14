# Unity phone implementation

The Android phone app boots the Unity interface over existing Dart rules, storage and vehicle communication. Home, cabin, facilities, friends, inventory and settings use Unity. Egg models and gestures appear only inside the vehicle cabin.

## Latest dev integration

The working branch includes dev through ffef8ea (PR #106), including #99/#91/#102. Existing authenticated pairing, gameRevision, companion/fishing state, driving auto-fishing presentation, and collectionSummary/baseSummary publication are retained. Vehicle summaries use successfully saved camp state and the existing whole-game writer. Driving distance/lookout rewards stay authoritative; no fish currency, animation/timer rewards or extra material credit was added.

Unity friends detail also exposes the latest vehicle-companion selection, fishing record count and failed-save retry. Selection resolves the exact persisted ownership record through the existing camp registry, including duplicate-species and legacy occurrence IDs. Disconnected/ended/busy selection is rejected; saved work can be retried offline.

The legacy exploration egg/care/props remain available outside full app presentation. Accepted app state clears legacy egg/HUD visuals, including an in-progress hatch restored after home → cabin. Malformed bridge payloads are not written to logs. Debug-only local affinity/Firebase entrypoints explicitly preserve their Flutter verification frames and injected controller/API ownership.

## Camp direction

Ninja Voltage is the baseline 2D village composition; Palworld supplies the wilderness survival theme. Original cel-shaded 2D terrain and small transparent workbench, outdoor cauldron and training sprites fill the screen beneath a thin HUD and right circular rail. Background, facilities, labels, jobs and up to four owned-character markers pan together within bounds. The HUD stays fixed and pan survives snapshots and facility detail changes. No reference game's IP artwork was imported; see docs/village-art-provenance.md.

## Pre-collected examples

UNITY_DEMO_CREATURES=true with FEED=fake and UNITY_APP=true enables the isolated unity-demo-examples profile with 길싹이, 웅덩이삐약, 등불나방 and 고속혜성. These are actual saved, assignable canonical ownership records, added idempotently without materials. Default/original demo data, incubation progress and fishing checkpoints stay separate. Store constructors retain both the latest namespace option and the existing profile option. Marker taps select the exact owned creature in friends detail.

## Verification

- Phone full suite: 404 passed; focused phase-2 integration: 72 passed.
- Shared core: 93 passed.
- Vehicle JVM tests: 293 passed in 47 suites with JDK 17.
- Unity EditMode: 115 passed; PlayMode real EventSystem drag: 1 passed.
- Scoped Dart analysis and independent integration reviews: clean.
- Concurrent camp initialization and disconnect/load recovery were reproduced in failing tests, then fixed with a shared load future and busy observation fence.
- Final scene/export and debug APK build succeeded (131.0s); data-preserving install and cold launch on Android 16/API 36 showed the 2D camp and all four canonical examples, with no Unity/AndroidRuntime/Flutter errors. 01-home.png records that final view.

Runtime logs/results are /tmp/allo_phase2_full.log, /tmp/allo_phase2_core.log, /tmp/allo-phase2-car-tests.log, /tmp/allo-latest-dev-ui-final-editmode.xml and /tmp/allo-latest-dev-final-playmode.xml.

## Remaining checks

Real vehicle/network integration and physical-device camera/microphone remain unverified in this work. Manual emulator system Back/pan automation was inconclusive; the PlayMode test verifies actual raycast/drag dispatch and both axes. Species without approved sprites use a clearly labeled placeholder. Runtime credentials and generated Unity libraries/APKs are excluded from the PR.

## Companion learning latest refresh — 2026-11-14

Local integration now includes dev `c15c12e` through #120, preserving 3D character/props and optional window experiments beside fixed personal stories. Canonical12 personal drafts contain36 scenes; new11 plots/personas await human review. Flutter459/core93/Unity176/server38 tests passed. Fresh Unity export/debug APK build and data-preserving API36 emulator install/cold launch succeeded. See [verification](../../verification/2026-11-14-companion-learning-latest.md) and [local API setup](../../companion-learning-local-setup.md). Actual provider dialogue awaits an API key entered only in the local launcher; no remote deployment was performed.

## Trip egg and server-owned character dialogue — 2026-11-14

Pairing now prepares at most one egg for a trip; incomplete eggs carry into the next trip without another grant. Repeating grants and cabin selectors are removed. Owned friends are summoned from Friends; tapping their actual cabin character opens a head-anchored server invitation. Personal story progression and personas execute on the backend; APK contains an ID-only manifest. Flutter479/core93/Unity189/server48 and vehicle fixture2 checks passed. The updated APK was installed without clearing data and its server invitation/story/next flow was observed. See [current verification](../../verification/2026-11-14-trip-egg-companion-invitation.md) and [setup](../../companion-learning-local-setup.md).

## Cabin pairing, direct conversation and action sheet — 2026-11-14

The unpaired cabin now opens with only a vehicle-connect action. Pairing opens the Flutter QR camera or accepts credentials, then prepares the trip egg. Friends are summoned explicitly from the Dex; their care and server-owned conversation stay independent from egg affinity. A single rounded `행동` button opens grouped egg/friend choices.

Flutter500/core93/Unity220/server53 passed. Fresh export and debug APK were installed on API36 without clearing data. Actual QR camera entry/cancel returned to Unity; manual synthetic pairing prepared an egg. Egg petting with a buddy present raised affinity to3; buddy petting left it at3. Actual character tap opened the conversation composer and honest key-unconfigured error. No live model was invoked. See [verification](../../verification/2026-11-14-cabin-pairing-direct-conversation.md) and [screenshot](cabin-direct-conversation/07-actions-sheet.png).

## Directional toss and double-tap relocation — 2026-11-14

The previous action sheet is replaced by four illustrated circles and a held item. Up/left/right/diagonal swipes throw toward the release position with bounded velocity follow-through. Double-tap arms free relocation; ordinary drops have no reward, while fixed cushion/blanket drops use existing care approval. Single-tap conversation waits briefly for the second tap. The QR connection action occupies the cabin title position.

Final Unity EditMode236 and UI raycast PlayMode1 passed. Final export/APK build and API36 data-preserving install succeeded. Actual forward and horizontal left/right ball flights, landing and care submission were observed with a stable camera. [Verification and limits](../../verification/2026-11-14-cabin-toss-and-rest.md), [left toss](cabin-toss-and-rest/07-left-toss.png), [right toss](cabin-toss-and-rest/08-right-toss.png).
