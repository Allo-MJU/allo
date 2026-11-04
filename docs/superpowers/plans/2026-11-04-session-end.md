# Session end implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Consume car sessionEnd, preserve local progress or hatch saves, and require a fresh pairing after a completed trip.

**Architecture:** Work from the latest B phone stack (f2a68ee), preserving its session checkpoints. A car event makes the current session terminal locally; a shared closing Future reads the final snapshot, stops subscriptions, and saves. Keep the existing non-terminal endSession checkpoint path used by startIncubating and manual exits. Add a focused end-of-trip screen for progress, retry, and next actions.

**Tech Stack:** Existing Dart/Flutter, FlutterFire, SharedPreferences, GoRouter. No added dependencies.

**Spec:** The user-approved scope in this chat; contract recorded first in docs/schema.md, section 3.5.

## Global Constraints

- No PR creation, pushes, team announcements, deployment, or merges to shared branches without the user's confirmation.
- Preserve the original checkout's six dirty files and existing PR #21.
- Do not change Firebase Stage, paths, wire fields, rarity rules, or hatch timing policy.
- Current-session historical sessionEnd is terminal; stale callbacks from an earlier pairing are ignored.
- Saving failure retains pending data and blocks pairing/start until a successful retry.
- A's missing final writes and lost end-event delivery cannot be repaired by the consumer; document that boundary.

## Review Focus

- Terminal history can replay immediately after pairing, before an egg exists.
- Last vehicle callback may arrive after the event callback; read the session's final stored snapshot.
- Duplicate events and manual end button presses must share a closing operation.
- Storage may return false instead of throwing; do not report completion in that case.
- Old events or reads must not affect a new paired session, and UI callbacks must not escape the ending route.

### Task 1: Feed and local storage contract

**Files:** docs/schema.md; phone/lib/feed/{vehicle_feed,firebase_feed,fake_feed}.dart; phone/lib/storage/{dex_store,pairing_store}.dart; phone/test/storage_failure_test.dart

**Interfaces:** Add VehicleFeed.readLatestVehicle(): Future<VehicleState?>. Firebase reads a captured session reference with a bounded timeout; Fake returns its latest emitted value without advancing time. Firebase pairing rejects a recorded car sessionEnd. Storage writes/removals throw on false.

- [x] Document termination/checkpoint/re-pair semantics and current transport limits before production changes.
- [x] Add meaningful storage failure tests; run RED, implement guards, run GREEN.
- [x] Implement the one-shot final snapshot and ended-session pairing checks without changing wire fields.

### Task 2: Terminal controller

**Files:** phone/lib/game/game_controller.dart; phone/test/session_end_test.dart; existing phone test doubles implementing VehicleFeed

**Interfaces:** Expose bool sessionEnded, bool sessionSaved, bool endingSession. Preserve Future<bool> endSession() as the retry/checkpoint API. VehicleFeed.events is bound to a pairing generation.

- [x] Write and run failing tests for incubation end, hatch-save waiting, final snapshot, duplicate/manual overlap, failure/retry, history replay, stale callbacks, and the next session's carried distance.
- [x] Implement one shared closing Future, final-snapshot ingestion, storage completion, pairing invalidation and input guards. Keep last remote game state.
- [x] Run targeted tests, then all phone/core tests and analyzer.

### Task 3: Ending screen and verification

**Files:** phone/lib/app.dart; phone/lib/screens/session_end_screen.dart; phone/lib/screens/incubating_screen.dart; phone/test/session_end_screen_test.dart

**Interfaces:** Use the three controller getters and endSession retry. Route /session-end while terminal saving is incomplete, then offer /pairing and /dex without reviving the ended session.

- [x] Write a failing UI test for saving, storage error/retry, and successful next-session navigation.
- [x] Add a small screen using the existing Material theme; prevent an incubation hatch callback routing away from terminal handling.
- [x] Run full phone/core suites, analyze and diff checks. Request independent code review, fix material findings, and present local changes for user approval before any PR.

## Validation result

- Original phone baseline: 33 tests passed.
- Final full phone suite: 60 tests passed; allo_core: 16 tests passed.
- Direct `dart analyze phone`: no errors/warnings, two existing core info diagnostics. `flutter analyze` hit an LSP JSON framing failure on the Korean directory path; direct Dart analysis completed successfully on the same tree.
- Independent review identified stale cleanup after disposal; two regression tests were observed failing and then passing after generation/disposal guards.
- Integration uses local deterministic feed/database/platform boundaries; real vehicle and Firebase network behavior remain unverified.
- No pushes, PR creation, shared-branch merges, team announcements, or Firebase deployment were performed.

Publication preparation: rebased onto latest B stack a551732 (APK-internal species asset packaging); updated the screen-test preload path to assets/data/species.json. Final verification: phone61/core16 passed, direct Dart analysis errors0/warnings0 (existing info2).
