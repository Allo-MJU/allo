# mountain_sprite: new name-based character action atlas

Generated 2026-11-12 using the built-in image_gen tool. User explicitly selected new designs based on game species names after the unrelated PR #86 designs were identified. No remapping of those designs.

Reference: phone/assets/poses/road_sprout/idle.png (rendering style only).
Generated file: /Users/leejiho/.codex/generated_images/01a1cfc2-c6ff-71b1-8c20-e02e96431d96/exec-348685de-f1d9-4b68-b326-5e710366c9da.png
Output copied unchanged to actions.png. 1024×1536 RGBA, 4 columns × 6 rows; cells 0–7 locomotion, 8–15 fishing, 16–23 sleeping. Runtime renders cells directly; no image postprocessing.

## Exact prompt

Create ONE production game sprite atlas PNG with real transparent background. Exact layout: FOUR columns and SIX rows, 24 equal square cells, all cells same fixed camera, scale, baseline, character centered fully inside cell with ample padding. Target image 1024x1536 or larger same 2:3 aspect. Reference image is STYLE ONLY: match the polished soft 3D rendered collectible creature style and warm gentle shading. NEW CHARACTER: Mountain Sprite / 산정령: a small friendly mossy gray stone guardian with a distinct three-peaked mountain head, tiny pine sprig, amber eyes, chunky stone arms and short sturdy legs. Running is a weighty stepping gait. Preserve its identity and anatomy across all 24 cells.
Cells read left to right top to bottom. ROWS 1-2 (frames 0-7): eight sequential articulated running/hopping/flying poses, a seamless locomotion cycle, visibly different limb/wing poses, fixed root and size.
ROWS 3-4 (frames 8-15): eight sequential FISHING poses: seated gripping a little fishing rod, waiting, noticing tug, leaning back lifting rod, fish caught hanging on line, surprised as fish escapes, lowering rod, returning to wait. Species with wings/flippers grip with forelimbs. Keep rod and fish inside each cell.
ROWS 5-6 (frames 16-23): eight sequential SLEEPING poses: eyes closed, settle head, inhale body subtly, exhale, tuck paws/wings/flippers, gently roll sideways, settle, return toward starting curled pose. Preserve exact anatomy. Actual articulated poses, no whole-sprite rotation/zoom.
NO labels, no letters, no numbers, no grid lines, no scenery, no cast ground shadows, no floor, no other characters, no watermark. Strictly equal 4x6 grid, no overlapping cells. Transparent empty margins.

## Background correction

Initial atlas failed the alpha-margin check. Built-in image_gen removed its opaque white background; final output copied unchanged from /Users/leejiho/.codex/generated_images/01a1cfc2-c6ff-71b1-8c20-e02e96431d96/exec-a2968e29-a11a-4f4c-ada4-cd3e168e0a4d.png.

Exact correction prompt:

EDIT the supplied 1024x1536 game sprite atlas. Remove ALL white/gray background and ALL floor/contact shadows to TRUE TRANSPARENT ALPHA=0. Keep EVERY one of the 24 foreground character/rod/line/fish drawings unchanged, their pixel positions, size, shape, color, and exact FOUR-column SIX-row grid unchanged. Do not redesign, reposition, add, delete, crop or rearrange any foreground. Preserve fine fishing lines and pine needles. Output same 1024x1536 RGBA atlas with completely empty transparent spaces between sprites, NO white backdrop, NO checkerboard painted pixels, NO cast shadows. This is only background removal.

Final actions.png SHA-256: `56f41fdcf6919ab6fb228537391b55710bad35aef3d00de2221725e39675bd9d`
