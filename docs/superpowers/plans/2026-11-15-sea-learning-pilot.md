# Sea Learning Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Let the user complete the sea experiment, save their prediction and observation, and inspect the actual Android Unity app on a visible emulator.

**Architecture:** Reuse StoryDirector and StoryOverlay. Dart owns manual entry, run evidence, persistence, lifecycle and input arbitration; Unity renders the existing toy experiment and notebook. No server or vehicle app changes.

**Tech Stack:** Flutter/Dart, SharedPreferences, Unity 6 UGUI, Android emulator.

**Spec:** `docs/superpowers/specs/2026-11-15-sea-learning-pilot-design.md` (approved by user 2026-11-15).

## Global Constraints

- Only `coast_sail` may start in the phone pilot; existing other-pack cards remain readable.
- No automatic invitations; existing direct conversation and egg/camera/photo priorities remain authoritative.
- Preserve `unityApp.story.v1`, `version: 1`, `cards`, and legacy card compatibility.
- Only successful atomic saves replace a topic's last personal record; no duplicated card rewards.
- Runtime AI, remote deployment, vehicle app edits and shared-branch pushes are outside this task.
- The user authorized implementation and emulator setup; execute without another plan approval round.

## Review Focus

1. Controller replacement during a delayed write must not overwrite a successfully stored card (Task 1).
2. Restored non-sea sessions must not block the pilot or be discarded before explicit sea start (Task 1).
3. Busy native input/AI responses, photo-required and session-end must win input ownership (Task 2).
4. Repeated experiment save with the same card count must refresh displayed evidence (Task 3).
5. Final emulator must run this worktree's fresh Unity export and Dart source, with no user data clearing (Task 4).

## Shared interfaces / write boundaries

- Task 1 owns `phone/lib/story/story_director.dart`, `story_store.dart`, minimal `story_pack.dart` changes, `phone/assets/data/window_stories_ko.json`, and `phone/test/story/*`.
- StoryDirector adds optional `Set<String>? playableTopics` (null retains existing all-pack behavior), `Future<void> flush()` and uses a store-lifetime barrier for pending writes across owner replacement. Existing `initialize`, `snapshot`, `updateContext`, `handle`, `pause` remain usable.
- Saved card snapshot keeps id/topicId/title/text and adds optional string fields `prediction`, `firstAction`, `observation`, `principle`, `nextQuestion`. Legacy cards omit personal fields. coast_sail gains a prediction node before existing choose, bumped pack version, and mandatory explain before ending. `storyReplay` restarts the prediction for coast_sail.
- Task 2 (main) owns `phone/lib/unity_app/unity_app_controller.dart` and `phone/test/unity_app_controller_story_test.dart` plus new dedicated host tests as needed.
- Host app snapshot `story` adds `ready`, `canOpen`, `notebookOpen`, `error` alongside the Director snapshot. Initialize it with all packs plus playableTopics `{'coast_sail'}` and disable canOffer always.
- New app intents: `storyNotebook` with boolean `open`; `storyRetry` with no fields. Existing Director intents use existing instanceId/nodeId/storyRevision/actionId/topicId, host validates entry/session/lifecycle and publishes ackRequestId/ackAccepted. Opening notebook is manual and `canOpen`-guarded. New runs require an open notebook. Pause closes presentation; resuming requires notebook. UI blocked signals from egg drawers do not themselves open notebook.
- Task 3 owns Unity `AppState.cs`, `AppUi.cs`, `AppUiViews.cs`, `StoryOverlay.cs`, required small direct-learning UI hook changes and relevant Unity tests. Add bool open to AppAction. Host controls notebookOpen; ToggleNotebook submits storyNotebook open. A persistent StoryOverlay attaches to safe area and uses host state. CabinGesturesBlocked and conversation entry account for experiment/notebook capture.
- Task 4 owns launch helper/documentation, ignored build output and emulator operation. Build only after all sources are integrated; do not overwrite another worktree's Unity project or clear emulator app data.

### Task 1: Personal evidence and storage

- [x] Add failing tests for 2 predictions × 2 first actions; require comparison/explanation and correct personal card fields.
- [x] Test legacy cards, non-sea unfinished session retention, pause/restart restoration, version mismatch, failed-save retry, replay replace, duplicate/stale input and delayed-write owner replacement.
- [x] Run `flutter test test/story` in phone and record expected failures.
- [x] Implement the minimal additive storage/model/content changes; retain existing all-pack tests through default behavior.
- [x] Rerun focused tests and `dart analyze lib/story test/story`.
- [x] Review against spec before integration.

### Task 2: Host connection and input lifecycle

- [x] Replace old no-story assertions with manual-only pilot tests; maintain unpaired/legacy-intent restrictions.
- [x] Test manual notebook→sea start→four paths→save; background/navigation/connection ending/photo-required pauses; delayed request rejection; busy AI/native input prevents opening.
- [x] Test retryable initialization and fresh controller storage ownership using Task 1 flush/barrier contract.
- [x] Run failing host tests, implement initialization/snapshot/dispatch/lifecycle integration, rerun host tests.
- [x] Verify unrelated egg affinity and direct learning behavior through existing targeted tests.

### Task 3: Unity entry, experiment and notebook

- [x] Add failing EditMode tests for connected-only notebook entry, host-driven open/close, stale story isolation, evidence display and update at fixed cardCount.
- [x] Read impeccable craft floor before UI edits; preserve incumbent tokens, boat art and character assets.
- [x] Add compact lower action entry; connect persistent overlay, use existing experiment geometry, display prediction distinctly and personal card rows in bounded layout.
- [x] Enforce no concurrent direct chat/egg gestures; preserve Back, pause, reduced motion and matching TTS only.
- [x] Run Unity EditMode tests after integration; inspect Android renders at 2400×1080 (1600×720 reference canvas) and 800×360 landscape.

### Task 4: Review and user-visible demo

- [x] Run complete Flutter tests, shared core tests and Unity EditMode suite; analyze changed Dart.
- [x] Independent reviewer checks storage races, session compatibility, UI capture and host entry against spec; fix actionable findings and rerun relevant checks.
- [x] Export this worktree's Unity project and build fake-feed Unity debug APK with long-lived local trip timing; record artifact source/hash.
- [x] Install without clearing app data, launch on a visible Android emulator, exercise actual prediction/compare/reason/save/reopen and restart restore. Capture inspected screenshots and log errors separately.
- [x] Leave the emulator at the experiment start for user interaction. Add a repeatable launch helper and concise local instructions with exact route and test limitations.
- [x] Record verification, update checked tasks and commit scoped changes. No merge/deploy/push.

## Completed evidence

Implementation source `6c4a79e`; Flutter555/core93/Unity294 passed. Scoped code re-review resolved all five findings including native preferences memory-before-failure. Fresh native export and final debug APK succeeded; emulator manual flow, update/restart card restore and small landscape were observed. Visual finish review returned ship; ordinary-extension design metadata check needed no changes. See `docs/verification/2026-11-15-sea-learning-pilot.md` for artifact hash, receipts and unverified physical/AI/audio limits.
