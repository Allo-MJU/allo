# Sea learning illustration assets — 2026-11-15

Generated using the built-in image_gen tool (not CLI/API fallback). Original native PNG files were copied into Unity Resources without cropping, resizing, alpha conversion, or drawing modifications. Exact prompts were then embedded as PNG tEXt metadata using impeccable embed-prompt. Original generated outputs remain in place. IHDR, IDAT, PLTE and tRNS chunks were compared against the originals and are identical, preserving pixels and alpha; file hashes differ because of the added metadata. The metadata scan reported `SCAN: 2 rasters, 0 missing`.

## boat-states.png

- Resource: `unity/allo_explore/Assets/Resources/StoryArt/Sea/boat-states.png`
- Original source: `/Users/seokamoto/.codex/generated_images/01a1de67-a986-7253-a32b-938e846e1667/exec-a91e8abd-c1f0-4cf2-89af-a6071098f1fc.png`
- Native dimensions: 1774 × 887 px (exactly 2:1).
- PNG alpha: yes; transparent background visually inspected.
- Atlas: two equal 887 × 887 cells, full sail left and tightly furled sail right. Same right-facing wooden mail boat, intact mast, matching scale and baseline. Split at normalized x=0.5.
- Visual review: complete isolated boats within their cells; organic wooden hull and cloth, envelope cargo, no text/background/water.
- Generation arguments: `transparent_background: true`; no reference images.

Exact prompt:

```text
Use case: illustration-story
Asset type: Production transparent mobile-game sprite atlas.
Primary request: Draw exactly TWO states of ONE identical small wooden mail sailboat, side by side, on genuine transparent alpha. Canvas aspect ratio exactly 2:1: two equal square cells, no visible cell borders. Left square: full gently billowing cream sail with seams. Right square: the exact same boat, same wooden hull, same mast, same envelope cargo, same planks, rope, colors, scale, camera and baseline, but the cream sail is tightly furled and tied around the mast. The mast must remain intact and same height in both.
Style: polished warm small-game anime/storybook bitmap art, crisp hand-drawn outlines, restrained cel shading, organically curved cedar wooden hull and graceful folded fabric, amber/brass small details. Readable at small size for a children's educational game. Near-side gentle three-quarter view facing RIGHT. Both boats centered within their respective squares, generous equal margins, aligned at precisely the same waterline baseline and scale. Each boat must be complete and fully inside its cell. Both have a small cream paper mail envelope visibly nestled in the hull.
Constraints: absolutely no primitive rectangle/triangle symbols, no flat vector icon style, no photorealism, no complex noisy textures. NO background, no water, no wake, no cast shadow outside boat, no characters, no text, no labels, no frame, no logos. Transparent between and around the two isolated boats. Sail-state change only.
```

## ocean-stage.png

- Resource: `unity/allo_explore/Assets/Resources/StoryArt/Sea/ocean-stage.png`
- Original source: `/Users/seokamoto/.codex/generated_images/01a1de67-a986-7253-a32b-938e846e1667/exec-e547ac79-e0e8-49e0-aae5-d9f914c30e89.png`
- Native dimensions: 2172 × 724 px (exactly 3:1).
- PNG alpha: no; opaque RGB landscape.
- Visual review: calm illustrated turquoise/seafoam waves, distant corner shores, clear water center and lower area; no boats, people, animals, text, or UI.
- Generation arguments: `transparent_background: false`; no reference images.

Exact prompt:

```text
Use case: illustration-story
Asset type: opaque production background for a children's educational mobile sailboat game, wide panoramic landscape approximately 3:1.
Primary request: an inviting calm small coastal lagoon / toy sea. Polished warm small-game anime/storybook bitmap illustration with crisp hand-drawn outlines and restrained cel shading, organically shaped gentle turquoise and seafoam layered waves with delicate foam, readable beautiful water shapes, subtly varied water colors. A little warm distant sandy shoreline with small dunes and grass only at the far upper left and upper right corners. Low distant horizon in the upper quarter, small amount of pale warm sky. The central and lower 75% must be spacious clear turquoise water where a side-view wooden boat can move from left to right. Side-view/very gentle elevated water perspective compatible with a sailboat game. Daylight, tranquil welcoming mood, warm cream sand accents, balanced saturation. Real illustrated forms and organic wave details, not a generic gradient and not a flat rectangle. Keep wave detail calm enough for small overlaid game labels near top and bottom, open clear middle area.
Constraints: NO boats, ships, people, animals, buildings, text, labels, arrows, UI, logos, frames, huge sun, photorealism or noisy texture. Opaque complete landscape background, edge-to-edge art.
```


## Final resource SHA-256 (with prompt metadata)

- `boat-states.png`: `eeeb11712e921732358754fedb02278599083132103c5369de63431f7ba16869`
- `ocean-stage.png`: `4a5d0f824b0f09c3da179fceb3e1903150149e88a5e083503a92179b2245890f`

Exact prompt text files: `boat-states-prompt.txt` and `ocean-stage-prompt.txt` in this directory. Embedded tEXt values were verified against those files.
