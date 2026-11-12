# sea_mist action sheets

Generated 2026-11-11 with the built-in image_gen tool. These are AI-derived animation assets, not original artist-delivered animations.

References: unchanged local move.png (run), idle.png (fishing), sleep.png (sleep), imported from PR #86 commit c24eeaa507bdec1bc7d292d096af7b1967dae07d, docs/mockups/assets/sea_mist/.

Format: eight row-major frames, four columns × two rows. Original reference files preserved.

## Exact prompts

### run-sheet.png

Create production game animation sprite sheet based strictly on this mint sea-ray character. EIGHT sequential poses in FOUR COLUMNS TWO ROWS equal square cells, transparent background alpha0, no shadow, scenery, text, labels, borders or white matte. Fixed camera slightly three-quarter right facing like reference move, fixed face/body center and scale, 10 percent padding for full wings tail and curved feelers. Preserve original elegant mint translucent manta-ray identity, cream face/body, two curved mint head feelers, navy eyes, lavender round spots and body gill markings, long slender mint lavender-tipped tail, soft glossy 3D finish. This species has NO legs or arms: locomotion running action must be an anatomically coherent energetic flying/swimming cycle using its existing two broad fins and tail. 1 fins raised ready for downstroke, 2 fins sweeping down curved tips, 3 fins low and back strong push, 4 fins level tail flick, 5 fins beginning upstroke curled edges, 6 fins high gently folded, 7 fins spread crest of stroke, 8 fins turn downward matching frame1. Expressive focused happy eyes, feelers and tail follow through. Distinct fin articulation and shape changes rather than moving same still image; no feet, invented limbs, resizing or camera rotation.

### fish-sheet.png

Create production game animation sprite sheet based strictly on mint sea-ray reference. EIGHT sequential fishing poses in FOUR COLUMNS TWO ROWS equal square cells. Transparent background alpha0, no shadow, glow, mist, scenery, text, labels, borders or white matte. Fixed slightly three-quarter facing camera, fixed body anchor and scale,10percent padding for rod/wings/tail. Preserve mint manta ray identity cream face and belly, curved mint head feelers, navy eyes, lavender fin spots and body marks, mint lavender-tip tail, soft glossy solid 3D character, no legs or invented hands. It holds a small fishing rod by gently curling its EXISTING fin tips around the handle. 1 relaxed holding rod angledleft; 2 tug fins curl tighter eyes widen; 3 leansback fins pull rod high tail curls; 4 delighted smallorangefish on line; 5 fish wrigglesfree surprised face fin reaches; 6 body dips forward reaching with fin after fish; 7 both fin tips back to rod lower with sheepish smile; 8 returns to relaxedframe1. Character actually bends fins/torso/feelers/tail across frames, not transformed duplicate still. All rod fish and body remain contained in each cell. No atmospheric effects.

### sleep-sheet.png

Generate eight sequential sleeping action frames of EXACT mint sea ray reference in uniform4columns2rows sprite sheet. True transparent background alpha0. NO white background, checkerboard, glow, haze, shadows, scenery, text or borders. Fixed frontal slightly three-quarter camera, stable size and faceanchor, full fin/tail/feelers contained10percentpadding. Preserve mint ray creamface navyclosedeyes lavenderfinspots/bodymarks curved mintheadfeelers longlavendertiptail soft3Dfinish. No invented legs or hands. Anatomy-based sleeping cycle:1 restinglow curled fins beside face eyesclosed;2 inhale creamchest subtly expands while finedges planted;3 exhale head lowers and finedges relax;4 one fin tip folds gently under cheek headtilts;5 turns slightly onto side with both fins curling around body and tail tucked;6 rests onside feelers droop breathing;7 slowly uncurls fins head returns;8 returns original restful pose. Every frame is distinct actual fin/head/body/feeler/tail articulation, not entire stillscaled/bounced. Character interior fullyopaque and clean truealpha around contour. No Z letters or dreambubbles.

### fish background extraction

undefined

## Asset QA

- sleep-sheet.png: 1774,887, alpha 0–255, 290149 fully transparent pixels.
- run-sheet.png: 1774,887, alpha 0–255, 10333 fully transparent pixels.
- fish-sheet.png: 1774,887, alpha 0–255, 909996 fully transparent pixels. Initial fishing draft had no alpha-zero pixels and was replaced by the documented background extraction output.

Visual review: inspected all eight full-sheet poses for preserved species identity and articulated body/limb or fin differences; original idle/move/sleep images unchanged. Navy-background composite inspection confirms no opaque rectangular backdrop. Some low-alpha edge residue remains; transparent-preview false-color speckles are not visible as colored speckles on navy. Exact 10-percent padding is not guaranteed: selected poses approach the cell boundary, but visible character bodies and props remain within their cells. Runtime playback and actual-device review are integration tasks, not claimed here.

Species adaptation: run is a fin-driven swimming/flying cycle without invented legs. Fishing uses curled existing fin tips; sleeping folds fins, lowers head, and rolls slightly sideways. Run has a soft luminous contour retained after navy visual review.

## Final emulator QA correction

Built-in image generation edit on 2026-11-11. Corrected cell overlap (Highway Comet fishing) or rectangular background haze (Sea Mist swimming). Final prompt:

Background extraction only for this eight-frame 4x2 swimming pet sprite sheet. Preserve the exact mint-colored manta fantasy pet poses and their scale/location, soft 3D shading, lilac markings, white belly, fins and tails. Remove all background haze, all diffuse white glows outside the body outline, and all semitransparent rectangular patches completely. Empty areas must be alpha zero. Clean natural antialiased edges, no exterior glow. Keep each entire pet inside its own equal grid cell. Do not add or change any poses or objects, no text or grid lines. True transparent background.
