# Village Character Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans.

**Goal:** Small village wandering, enlarged exact-owned-character detail and separate dex navigation.
**Architecture:** AppUiMap owns persistent marker offsets and local selection. A new AppUi partial reuses existing authoritative actions and food controls. The existing per-frame village geometry hook advances display motion.
**Tech Stack:** Unity 6000.0.85f2, C#, UGUI, NUnit.
**Spec:** docs/superpowers/specs/2026-11-14-village-character-detail-design.md

## Global Constraints
- Preserve existing 2D village pan/HUD and authoritative Dart game rules.
- Preserve the other chat's edits and existing saved data; do not commit the whole dirty worktree.
- Pause wandering for reducedMotion, inactive views, detail/confirmation overlays, busy state and pointer presses.

## Review Focus
- Snapshots preserve current marker offsets and map pan.
- Same-species distinct IDs open the tapped owned creature.
- Deleted selections and view changes close stale detail.
- Confirmation blocks underlying world/detail actions.
- Dragging a friend pans without selecting it.

### Task 1: Village movement and local detail
**Files:** Modify AppUiMap.cs, AppUi.cs navigation label; create AppUiVillageCharacter.cs and AppVillageCharacterTests.cs; adapt AppVillagePanTests.cs obsolete dex-selection assertion.
**Interfaces:** BuildVillageMap/UpdateVillageGeometry call TickVillageFriends(float deltaTime), OpenVillageFriend(string creatureId), BuildVillageCharacterDetail(). CreatureActions/FeedOptions consume the exact owned ID.
- [x] Add failing tests for local exact-ID detail, close/pan preservation, stale selection cleanup, bounded motion/snapshot persistence and paused motion. Run scoped Unity EditMode tests; observe expected failures.
- [x] Implement motion/detail using existing helpers and destroyed-object guards for async art. Rename only the navigation label in shared AppUi.cs.
- [x] Run Unity EditMode suite and village PlayMode input regression. Inspect rendered output from the modified source.
- [x] Fresh read-only review, fix material findings and record actual validation. Leave changes reviewable in the worktree.
