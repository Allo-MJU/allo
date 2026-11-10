# Vehicle character poses

Images copied unchanged from Allo-MJU/allo PR #86, commit `c24eeaa507bdec1bc7d292d096af7b1967dae07d`,
`docs/mockups/assets/<species>/{idle,move,sleep}.png`.

Only the six exact species IDs shared with `data/species.json` are included.
The other six designs have unresolved species mapping and are not substituted.
Driving uses a still move pose; parked sleep uses sleep, fishing uses idle with
a programmatically drawn rod and bobber. These are 2D rendered images, not 3D models.

## Road Sprout authored action frames

`road_sprout/run-sheet.png` and `road_sprout/fish-sheet.png` are AI-generated
animation derivatives made with the built-in image generation tool on 2026-11-11.
They are not original art delivered by PR #86. Its `move.png` and `idle.png`
respectively served as identity references. Original source images are unchanged.
Both sheets are 1774×887 RGBA, 4 columns × 2 rows, read left-to-right/top-to-bottom.
Only Road Sprout uses these action frames; no other species is remapped to it.

Prompt set:
- Run: preserve the green leaf-backed quadruped, cream muzzle, orange eyes and
  leaf-tipped brown tail; fixed three-quarter left-facing camera and stable scale;
  eight sequential poses showing alternating articulated foreleg/hindleg reach,
  contact, recoil, passing and recovery; no whole-image bouncing; transparent grid.
- Fish: preserve the same character; sit on hindquarters, actively grip the rod
  with two front paws; eight poses of waiting, noticing a tug, leaning back to lift,
  catching a fish, reaching in surprise as it escapes, leaning forward, lowering
  the rod and settling back; stable grid with transparent background.
- Cleanup: remove the white background and ground shadows while preserving every
  character, limb, rod, thin line and fish; remove detached background speckles.

Running remains preview-only. Fishing uses actual pose frames without the earlier
whole-image transform or vector rod overlay. This is 2D frame animation, not a
rigged 3D model; art approval and refinement of in-between frames remain separate.
