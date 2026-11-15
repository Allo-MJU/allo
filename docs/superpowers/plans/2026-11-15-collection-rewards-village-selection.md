# Collection Rewards and Village Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Prevent duplicate hatches, grant three berry snacks once per post-completion trip, and persist up to four player-selected village friends.

**Architecture:** Existing Dart game/camp controllers own results and durable receipts. Unity sends validated village-selection intents and renders a local presentation setting. Existing Firebase fields remain unchanged.

**Tech Stack:** Dart/Flutter, SharedPreferences, Unity UGUI C#.

**Spec:** `docs/superpowers/specs/2026-11-15-collection-rewards-village-selection-design.md`

## Global Constraints

- Existing source and uncommitted changes are preserved. No commit, push, deploy, APK build or install.
- No vehicle control permission, child PII, coordinate upload, new currency or external dependency.
- Completed catalog means all 12 IDs from the actual species catalog, not 12 ownership records.
- Reward is exactly `berry_snack` x3 per newly eligible trip, including durable retry/recreation deduplication.
- Village IDs identify exact owned creatures. Maximum 4. Empty selection is intentional and persists.
- Parent owns docs; Task 1 owns core/game/camp; Task 2 owns UnityAppController/local village store/Unity UI. Do not overlap edits.
- Tasks may implement in parallel only in disjoint owned files, as explicitly requested by the user's AGENTS instructions.

## Review Focus

- All matching environmental candidates are collected but catalog is incomplete: still select a new species.
- Catalog load or reward write fails: never publish a successful grant or allocate an unwanted egg.
- Last species is collected during this trip: no snack double-reward in that same trip.
- Selection is empty, references missing creatures, or includes two owned instances of one species: validate without changing unrelated roles.
- Snapshot refresh, reconnect, profile recreation, and save failure: settings and economic receipts remain correct.

### Task 1: Unique collection and completed-catalog reward

**Files:** `phone/packages/allo_core/lib/src/species_table.dart`, core species tests; `phone/lib/game/game_controller.dart`, game tests; `phone/packages/allo_core/lib/src/base_camp.dart`, camp tests; `phone/lib/base_camp/base_camp_controller.dart`, controller tests; local ledger only if needed.

**Interfaces:** Expose existing-controller-backed persistent reward handling; keep all selection/reward calculations out of Unity. Return no species explicitly when no unseen species remains. Existing callers must handle this result.

- [x] Write failing tests for unseen candidate selection, fallback, last ID, and complete catalog.
- [x] Implement a finite unseen pool preserving existing priorities where possible.
- [x] Write failing tests for 3 snacks once per eligible trip, restart/reconnect/retry, save failure, duplicate old ownership, and 12th hatch trip.
- [x] Implement reward receipt and inventory write atomically through existing camp storage; integrate trip entry and pending hatch settlement.
- [x] Run scoped tests, core full suite, and report test commands/results and changed files.

### Task 2: Persistent village friend selector

**Files:** `phone/lib/unity_app/unity_app_controller.dart`, new `phone/lib/unity_app/village_selection_store.dart`, associated phone tests; Unity `AppState.cs`, `AppUiMap.cs`, new `AppUiVillageSelection.cs` plus metadata and EditMode tests. Avoid `AppUiViews.cs` unless necessary and coordinate before editing.

**Interfaces:** Existing snapshot adds `villageCreatureIds` and availability/error state if needed. Existing action payload may carry `creatureIds`; otherwise add a narrow action parser. New `setVillageFriends` intent validates exact IDs and persists before replacing confirmed selection. Profile from existing dex namespace/profile plus fake/real separation.

- [x] Write and observe failing tests for selected IDs, 0/4/5, invalid or repeated IDs, save/reload/failure, duplicate-species identity and profile isolation.
- [x] Implement the local store and controller serialization using existing change publication.
- [x] Write failing Unity tests for selected-only map rendering and selection/save UI behavior.
- [x] Implement compact existing-style selection surface with up to 4 choices, cancel/save, no automatic replacements after explicit choice.
- [x] Run scoped Flutter tests; report Unity tests for parent to run serially with the shared Editor.

### Task 3: Integrate, review and propose end-of-care UX

- [x] Parent inspects each diff and dispatches read-only independent task review with concrete file scope.
- [x] Produce proposal-only end-of-care states/copy/actions for first failure, voluntary stop, waiting to resume, and completed catalog.
- [x] Run whole Flutter/core suites and Unity EditMode suite once after integrating tasks. Inspect final UI from Unity test capture where available; preserve current exports/APKs.
- [x] Address material review findings and record verification limits. Report implemented behavior separately from the UX proposal.
