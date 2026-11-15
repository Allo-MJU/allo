# Village Walking and Character Inspector Plan

**Goal:** Make owned village characters visibly walk and rest, and present a polished right inspector with animated artwork.

**Architecture:** Keep the persistent village map and its ownership markers. A small UGUI frame renderer reuses each of the six mapped species' existing eight-frame running sheet. AppUi controls bounded walking destinations, rest periods and selection; the renderer controls frames and facing. Existing game actions and storage contracts stay unchanged.

**Stack:** Unity UGUI/C#, existing Flutter assets, no GIF decoder or new runtime dependency.

## Constraints

- Preserve the existing forest camp, canonical species and owned instance IDs.
- Walk near the existing grass positions; no whole-image sinusoidal floating.
- Pause movement for reduced motion, pointer input, map inertia, facilities, character detail, confirmations and busy states.
- Keep both walking position and inspector frame phase across snapshot refreshes.
- Inspector stays on the right, showing real role, assignment/job, description, learned actions and food inventory only.
- Unknown artwork retains its explicit fallback; never substitute another species.

## Tasks

1. Renderer and asset packaging (delegated):
   - Add frame ordering/facing/timing/reduced-motion/cache/fallback tests and observe RED.
   - Add VillageCharacterArt with shared straight-alpha textures and asynchronous retarget guards.
   - Package exactly six existing run-sheet paths in pubspec.
2. Walking and right inspector (main):
   - Update village tests for visible travel, rest, snapshot continuity and right-panel layout; observe RED.
   - Replace floating with deterministic per-owned-ID destinations, walking and rest.
   - Put the animated preview, identity, current activity and existing actions inside the right inspector.
   - Tick movement once per frame; remove the geometry-driven second tick.
3. Verification:
   - Run the full Unity EditMode suite and existing village input PlayMode tests.
   - Render actual Unity walking/detail sequences and the smaller viewport.
   - Encode the captured sequence as an animated preview; review motion and readability independently.
   - Build/export and install the Android update without clearing user data.
   - Record evidence and update the existing PR.
