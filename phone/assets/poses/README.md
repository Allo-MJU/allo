# Vehicle character poses

Images copied unchanged from Allo-MJU/allo PR #86, commit `c24eeaa507bdec1bc7d292d096af7b1967dae07d`,
`docs/mockups/assets/<species>/{idle,move,sleep}.png`.

Only the six exact species IDs shared with `data/species.json` are included.
The other six designs have unresolved species mapping and are not substituted.
Driving uses a still move pose. The six mapped species use authored action sheets
for parked sleep/fishing and preview-only running. Original pose images remain
available as fallbacks. These are 2D rendered images, not 3D models.

## Road Sprout authored action frames

`road_sprout/run-sheet.png`, `road_sprout/fish-sheet.png`, and
`road_sprout/sleep-sheet.png` are AI-generated
animation derivatives made with the built-in image generation tool on 2026-11-11.
They are not original art delivered by PR #86. Its `move.png`, `idle.png`, and `sleep.png`
respectively served as identity references. Original source images are unchanged.
All three sheets are 1774×887 RGBA, 4 columns × 2 rows, read left-to-right/top-to-bottom.
Every mapped species uses its own action frames; no species is remapped to Road Sprout.

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

Sleep prompt: strict reference identity from sleep.png; 4×2 equal cells, eight
sequential poses at fixed left-facing camera and stable body scale: chin on paws,
inhale with chest and shell rising while paws stay planted, exhale, front paw
sliding under cheek, turn gently onto side with paws curled toward chest and tail
wrapped closer, settle sideways, roll back toward belly, return chin to paws.
Eyes closed throughout; exactly four limbs; no text/Z, backdrop, ground shadows
or whole-image scaling. True transparent background. Generated with the built-in
image tool on 2026-11-11; original sleep.png remains unchanged.

Sleep frame playback is parked-only and replaces the transformed still image
and vector Z overlay for all six mapped species.

## Remaining five species

`puddle_pip`, `lamp_moth`, `storm_lantern`, `highway_comet`, and `sea_mist` each
have their own `run-sheet.png`, `fish-sheet.png`, and `sleep-sheet.png`: eight
authored poses in a regular 4×2 grid. These are AI-generated derivatives made
with the built-in image generation tool on 2026-11-11, not additional original
deliverables from PR #86. Exact prompts and source references are recorded in
each species directory's `generation-provenance.md`. Source PNGs are unchanged.

Movement preserves each character's anatomy: Puddle Pip steps with webbed feet,
Lamp Moth beats its wings, Storm Lantern gallops, Highway Comet bounds, and
Sea Mist swims with articulated fins. Sleep changes breathing/head/limb poses;
fishing changes grip, lean and reaction through a catch-and-loss sequence.
All use the shared playback timings, lifecycle/reduced-motion freeze behavior,
and parked-only sleep/fishing gate. Actual driving continues to show static art.
