# puddle_pip action sheets

Generated 2026-11-11 with the built-in image_gen tool. These are AI-derived animation assets, not original artist-delivered animations.

References: unchanged local move.png (run), idle.png (fishing), sleep.png (sleep), imported from PR #86 commit c24eeaa507bdec1bc7d292d096af7b1967dae07d, docs/mockups/assets/puddle_pip/.

Format: eight row-major frames, four columns × two rows. Original reference files preserved.

## Exact prompts

### run-sheet.png

Create production game animation sprite sheet based strictly on reference character. Exactly EIGHT sequential poses in uniform FOUR COLUMNS TWO ROWS equal square cells. True transparent alpha background, no ground shadow, white matte, scenery, text, labels or borders. Same camera, same scale and torso anchor each cell; full body and tail stay inside cell with 10 percent padding. Preserve blue duck-platypus identity: yellow broad bill, floppy blue crest, sleepy blue eyelids, cream belly, two blue arms, two yellow webbed feet, broad blue flat tail, smooth 3D toy rendering. Three-quarter left facing throughout. Genuine articulated running cycle: 1 left foot reaching front right foot pushing behind, opposite arms swing; 2 left heel lands, elbows swing; 3 weight over planted left foot right knee tucked; 4 airborne passing feet; 5 right foot reaches front left pushes rear; 6 right heel lands; 7 weight over right foot left knee tucks; 8 passing feet returning to frame1. Distinct limb poses, subtle crest/tail follow-through. No whole-character bouncing copies, no extra limbs or character redesign. Stable face proportions and coherent seamless cycle.

### fish-sheet.png

Create production game sprite sheet from this exact blue platypus duck character. Exactly EIGHT sequential fishing poses arranged FOUR COLUMNS TWO ROWS equal square cells. True transparent alpha background, no shadows, water, landscape, text, borders or matte. Fixed three-quarter left-facing camera and character scale/body anchor, generous10 percent padding keeping all rod/fish/tail inside each cell. Preserve blue floppy crest, sleepy eyelids, yellow bill/webbed feet, cream belly and blue broad flat tail in smooth3D toy finish. Character sits on hindquarters and ACTIVELY HOLDS a small brown fishing rod using its two existing blue arms. Frame1 relaxed holding rod angledleft. Frame2 tug, eyes widen and arms bend. Frame3 leansback pulling rod high. Frame4 triumphant open bill catch small orange fish on line. Frame5 fish wrigglesfree, character surprised reaches arm. Frame6 bendsforward trying to catch slippingfish. Frame7 both hands back on rod lowersit, sheepish face. Frame8 settles like frame1. Expressive torso arm head crest and tail articulation, genuine different body poses, stable identity, no extra limbs, no bobbing same still image. Rod and thin line stay fully visible per cell.

### sleep-sheet.png

Generate eight sequential sleeping action frames of EXACT reference blue duck platypus in uniform 4columns2rows sprite sheet, true transparent background alpha0, no glow/shadow/mist/scenery/text/borders. Fixed slightly three-quarter left camera, scale and body anchor, fullbody tail and crest contained10percentpadding. Preserve same blue body, floppybluecrest, yellowbill/webbedfeet, creambelly, broadblueflat tail and smooth3Dtoyfinish. Eyes remainclosed. Real anatomy changes:1 sitting reclined asleep with two feet forward and arms beside belly;2 gentle inhale belly/chest slightly rises while feet anchored;3 exhale chin lowers;4 left arm bends hand under cheek head tilts;5 sleepy little side turn curling torso and feet closer, crest droops;6 settles side curled with small breathing chestchange;7 gently uncurls head and arms;8 returns relaxed sitting pose matchingframe1. No whole-image scaling/bobbing, create different jointed arm/head/body/foot positions. Do not add letters Z or dream bubbles. Character fully opaque interior, clean alpha outside body.

## Asset QA

- sleep-sheet.png: 1774,887, alpha 0–255, 814800 fully transparent pixels.
- fish-sheet.png: 1774,887, alpha 0–255, 56960 fully transparent pixels.
- run-sheet.png: 1774,887, alpha 0–255, 932894 fully transparent pixels.

Visual review: inspected all eight full-sheet poses for preserved species identity and articulated body/limb or fin differences; original idle/move/sleep images unchanged. Navy-background composite inspection confirms no opaque rectangular backdrop. Some low-alpha edge residue remains; transparent-preview false-color speckles are not visible as colored speckles on navy. Exact 10-percent padding is not guaranteed: selected poses approach the cell boundary, but visible character bodies and props remain within their cells. Runtime playback and actual-device review are integration tasks, not claimed here.

Species adaptation: run alternates webbed feet and arm swings. Fishing bends arms, leans back, catches and loses a fish. Sleeping changes chest breathing, hand-to-cheek pose and tucked side curl.
