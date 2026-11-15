# Dex and Inventory Book Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for implementation. Independent asset and test work may be delegated under the user's AGENTS.md rules.

**Goal:** Replace the Unity phone dex and inventory with a usable illustrated open book, details left and faces/items right.

**Architecture:** A book-specific AppUi partial owns the shared pages, portrait crop and local item art. BuildDex/BuildInventory use those pages while preserving AppState and existing action envelopes. Other routes keep their existing Sheet component.

**Tech Stack:** Unity 6000.0.85f2, C#, UGUI; existing Flutter bridge unchanged.

**Spec:** docs/superpowers/specs/2026-11-14-dex-inventory-book-design.md

## Global Constraints

- Left detail approximately 45%, right catalog approximately 55%; landscape 1600×720 and 1024×576.
- Existing real names, descriptions, counts and action restrictions remain authoritative.
- No added packages, backend contract changes or unrelated screen redesign.
- Separate worktree based on origin/dev 99309e9; preserve unrelated dirty worktrees.
- Raster book background lives inside Unity Resources and records its provenance.

## Review Focus

- All twelve species remain recognizable when portraits are cropped.
- Empty catalogs, uncollected species and long descriptions stay navigable.
- Zero food, no recipient and busy state cannot consume an item.
- State refresh preserves selection and both page scroll positions.
- Both target aspect ratios retain touch targets and legible content inside safe bounds.

### Task 1: Book layout and dex

**Files:** Create AppUiBook.cs beside existing AppUi files; modify AppUiViews.cs BuildDex only; add AppUiBookTests.cs under Tests/EditMode.

**Interfaces:** Book pages are independent transparent scroll panes; selection uses existing _selectedDex/_selectedCreature. Existing selectCarCompanion, performAction and feedFood envelopes stay unchanged.

- [x] Add behavior tests for left detail/right selectable catalog, empty and uncollected states; run and observe expected failures.
- [x] Add the shared book background/pages and face portrait framing; wire BuildDex to them without changing global Sheet.
- [x] Run UI edit tests; adapt the old scroll test's grid lookup to the new right pane while retaining its scroll preservation assertions.

### Task 2: Inventory

**Files:** AppUiBook.cs and AppUiViews.cs BuildInventory; AppUiBookTests.cs.

**Interfaces:** MaterialState/FoodState IDs map to local artwork; food consumption still calls Confirm then feedFood with recipient and recipe.

- [x] Cover item selection, selected count, disabled zero-food use and no-recipient state.
- [x] Build right item slots and left detail; add materials/food tabs and recipient selection.
- [x] Run both new tests and existing confirmation/vehicle-companion/scroll tests.

### Task 3: Rendering and review

**Files:** Editor/BookUiCapture.cs; docs/verification/2026-11-14-book-ui.md; screenshot outputs under docs/work-results/unity-phone/book-ui/; scoped DESIGN/PRODUCT records.

- [x] Render actual Unity canvas with real species art at 1600×720 and 1024×576, including dex and food inventory; inspect all twelve portrait crops.
- [x] Fix clipping and interaction defects in one batch, then recapture affected views.
- [x] Run full EditMode suite and a fresh independent review of the diff and captured views.
- [x] Record verified scope and limitations, commit only this worktree's changes, provide clickable previews.
