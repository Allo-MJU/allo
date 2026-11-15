# Sea illustration refresh

**Goal:** Replace the exposed sea experiment's primitive boat/water art with coherent illustrated assets while preserving its prediction, comparison, motion and saved-card behavior.

**Scope:** User feedback refines the implemented sea pilot. Reuse its existing screen and game palette; no new story, character identity, AI behavior or vehicle feature.

## Asset contract

- `Assets/Resources/StoryArt/Sea/boat-states.png`: transparent equal-width two-cell atlas. Left is the open-sail boat, right is the same boat with furled sail. One texture preserves identity/alignment; Unity selects a half using UVs.
- `Assets/Resources/StoryArt/Sea/ocean-stage.png`: opaque illustrated calm sea backdrop without a boat or baked labels.
- Native image generation supplies actual bitmap art. Exact prompts and origin paths are recorded under `art/sea-learning/2026-11-15/`.

## Work

- [x] Generate and inspect both images for style, transparency, equal framing and identical boat identity.
- [x] Replace only coast_sail procedural art in StoryOverlay. Reuse existing one-variable motion distances, neutral/reduced-motion handling and comparison labels.
- [x] Check image bounds/UV selection and meaningful branch motion in focused Unity tests; retain the story/ownership regression suite.
- [x] Run Unity tests, export current source, rebuild local fake-feed APK, install with data preserved.
- [x] Inspect actual single/paired scenes on the emulator, leave the improved screen ready to view and record evidence.

Art generation and code integration have disjoint ownership. Main reviews both and coordinates the Unity editor/build; no parallel editors operate on the same project.

Completed at source `18813e1`; Unity299/299 passed. Native textures, UV/alpha and small landscape were visually checked. Independent visual/code review returned ship for this artwork correction. See `docs/verification/2026-11-15-sea-illustration-refresh.md`.
