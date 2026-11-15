# Companion Quests and Travel History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add opt-in per-owned-friend 48-hour quests and durable arrival-backed travel history for recommendations.

**Architecture:** Firebase records authenticated owner-scoped visits. Existing local camp owns quest state and atomic food completion. Python owns fixed story-derived text. Unity renders question badges and explicit quest UI; the phone coordinates verified history and driver-confirmed exact destination requests.

**Tech Stack:** Kotlin/Pleos, Firebase Functions/RTDB, Dart/Flutter, Python HTTP, Unity UGUI.

**Spec:** `docs/superpowers/specs/2026-11-15-companion-quests-travel-history-design.md` (including exact interfaces at the end).

## Global Constraints

- User chose each friend individually every2days and recommended DB-visits/local-quests/server-story storage.
- No live deploy, APK build/export/install, credentials output, child PII, GPS path/coordinate/address upload, new economy or account migration.
- Existing uncommitted collection/snack/village and cornering/camera changes must be preserved. No commit/push in shared worktree.
- Existing location-name restriction is narrowed only for the explicit new owner-scoped visit contract; ordinary snapshot/events remain unchanged unless specified.
- No auto speech/dialogue. Exact owned creature IDs, one accepted quest per friend, first immediately available, 48h from issuance, unaccepted rollover; no surprise additional rewards.
- Each worker has disjoint files. Parent coordinates all Dart GameController/UnityAppController changes, new phone coordinator/history reader, docs and fixture captures.

## Review Focus

- Destination request/route end/parking/cancellation is never treated as arrival.
- Repeat arrivals, reconnect, queued upload, changed routes, changed phone membership and session end ordering cannot double count or leak owner history.
- Local quest/food save failures preserve old committed state; restart and time reversal cannot reset cooldown/consume twice.
- No history/offline is distinct from confirmed empty; no fabricated past dialogue or unknown place recommendation.
- Badges/detail/map selection/back/drag, active route and driver approval remain consistent.

### Task 1: Authenticated visits and vehicle producer

**Files:** `firebase/functions/index.js`, `firebase/database.rules.json`, `firebase/tests/*visit*`; car `navi/NaviEtaReader.kt`, `sync/FirebaseSessionApi.kt`, `sync/SessionManager.kt`, new visit tracker/outbox + tests, `gleo/DestinationSuggester.kt`, `gleo/TravelRequestFlow.kt`, `model/Models.kt`, `model/GameSnapshotReader.kt` + tests. Own all car/Firebase changes only.

**Interfaces:** Follow exact callable/storage contract in Spec. `Destination.placeId` deterministic18-place registry IDs. Optional `TravelRequest.targetPlaceId`. Same-session arrival correlation, known/unknown ID and companion context handled explicitly. Only actual destination arrival creates confirmed visits; no historical import inference.

- [x] Write failing local tests for route/arrival tracker, POI matching/changed/cancelled/unknown, dedup/outbox and exact destination request.
- [x] Implement producer+retry and callable owner verification/transaction/rules with no coordinate upload.
- [x] Add callable/rules emulator integration coverage for identity, malformed payload, idempotency, conflict, ended-session arrival, separate owner read, no public/private cross-read.
- [x] Run car JVM suite and local Firebase emulator integration serially; no deployment. Report exact commands/results.

### Task 2: Local quest state and atomic completion

**Files:** new `phone/packages/allo_core/lib/src/companion_quest.dart`, export `allo_core.dart`, `base_camp.dart` and tests; `phone/lib/base_camp/base_camp_controller.dart` and tests. Do not edit models.dart/game/Unity host or Python.

**Interfaces:** `CompanionQuest` immutable fields per spec. `BaseCamp.quests`, `questDue(String creatureId,{required int atMs})`, `offerQuest(CompanionQuest,{required int atMs})`, `acceptQuest(String creatureId,String questId,{required int atMs,String? targetPlaceId})`, `completeStoryQuest(String creatureId,String questId,{required int atMs})`, `completeTravelQuest(String creatureId,String questId,{required int atMs,required String placeId,required String visitId,required int arrivedAtMs,required List<String> companionIds})`. Controller exposes matching Future<bool> wrappers. Existing feedFood completes matching accepted food quest in same saved snapshot. Parent may adapt call shape after exact report but worker must announce changes.

- [x] TDD cadence/first/different individuals/unaccepted rollover/accepted retain/clock reverse/restart and target identity.
- [x] TDD food consumption+completion atomicity, accepted story self-confirmation, travel target+arrival-after-accept+same-companion/dedup, malformed snapshots/migration.
- [x] Implement minimal persisted quest state and controller commands; no new reward inventory.
- [x] Run core suite and scoped camp Flutter tests; report interfaces precisely. Parent runs whole phone suite once integrated.

### Task 3: Fixed story-derived quest templates

**Files:** new `server/affinity/quests.py`, `server/affinity/app.py`, server tests; `phone/lib/affinity/egg_demo_api.dart` add HttpEggDemoApi.companionQuestTemplate(Map body), transport test. Do not change abstract EggDemoApi unless necessary (would affect existing fakes).

**Interfaces:** Exact POST/response schema in spec. Fixed canonical story/persona source, no fake legacy stories/history, no LLM necessity; generic travel text without invented user past. Food target existing berry_snack. Story uses explicit observer self-confirmation only. Reuse existing bearer transport, no secret/provider call.

- [x] TDD all current real/legacy species, supported kinds and strict bounded input, no story inventions, no client-authored prompts or new user state.
- [x] Implement template endpoint and client method using existing HTTP/handling.
- [x] Run server whole suite and scoped phone transport tests, no provider calls/deploy.

### Task 4: Unity quest badges and detail UI

**Files:** Unity AppState.cs, AppUiMap.cs, AppUiVillageCharacter.cs, new AppUiQuests.cs+meta, small AppUi.cs/AppUiViews.cs hooks if needed; EditMode quest tests. Own C# UI only; parent owns Dart host/coordinator.

**Interfaces:** Root QuestState[] quests and exact intents from spec. Badge appears near village/character art, body remains hidden until explicit?press. Detail offer accept/later, food condition uses existing food UI, story confirm sends observeQuest, travel candidates choose ID and requestQuestTravel after acceptance. No automatic TTS or route changes. Preserve four selected village actors and exact owned character selection.

- [x] Write tests first, notify parent before product edits for scoped Unity RED.
- [x] Implement compact existing forest/inspector-style?badge and explicit detail card; handle pending/error/completed/empty/Back/nav.
- [x] Parent runs scoped/full Unity and actual PlayMode fixture capture. No build/export/APK.

### Task 5: Phone coordination, integration and review

**Files (parent):** new `phone/lib/quests/companion_quest_coordinator.dart`, `travel_history_store.dart`, tests; `phone/lib/unity_app/unity_app_controller.dart`, `phone/lib/game/game_controller.dart`, optional travelRequest serialization in `phone/packages/allo_core/lib/src/models.dart`, catalog asset registration; docs/schema/verification.

- [x] TDD cloud history known/unknown separation, template correlation, stable per-friend rollover, food/story/travel completion and late responses/disposal.
- [x] Wire explicit UI intents to camp/quest server/history; completed travel requires persisted arrival after acceptance with matching companion+place.
- [x] Send targetPlaceId proposal through existing game writer, preserve all other v2 fields and require existing driver guard.
- [x] Independent read-only reviews of each task; fix material findings with regression coverage.
- [x] Run integrated Flutter/core/server/car/Firebase/Unity checks appropriate to touched contracts; inspect actual UGUI captures. No success claims for live DB/device/SDK arrival unless observed.
