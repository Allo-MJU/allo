# 급정거 넘어짐·회복 프레임

- 기준: #92 `5cbb6ed`의 기존 6종 run-sheet.png. 기존 에셋은 변경하지 않음.
- 생성: 2026-11-12, built-in `image_gen` (CLI/API 키 경로 사용 안 함).
- 새 산출물: `phone/assets/poses/{speciesId}/fall-sheet.png`, 각 1774×887 RGBA, 4열×2행 8프레임.
- 순서: 브레이크 자세 → 균형 상실 → 앞으로 넘어짐 → 엎드림 → 고개 들기 → 몸 일으키기 → 웅크려 회복 → 서기/호버 복귀. 좌우 방향·종별 팔다리/날개/지느러미 해부구조는 기존 달리기 에셋 기준.
- 원본 디자인/색상/종 ID를 보존하는 참고 이미지 생성. 실제 프레임별 팔다리·표정·몸 자세 변화, 회전만으로 만든 연출 아님.
- 검증: 6장 모두 alpha 최소 0/최대 255, 정확한 크기·셀 수 확인. alpha≥64 실루엣의 48개 셀 가장자리 여백은 모두 양수(최소 13px), 불투명 캐릭터의 셀 경계 침범 없음. 요청 프롬프트의 10% 여백이 모든 셀에서 엄밀하게 달성되지는 않음. 앱은 기존 독립 경계 정수 나눗셈 crop을 사용.
- storm_lantern 첫 결과의 반투명 바닥과 sea_mist 첫 결과의 격자 흔적은 image_gen 후속 배경 제거로 수정. 원본 생성 결과는 도구 저장 경로에 보존.
- 투명도 및 셀 여백은 ffmpeg alphaextract + Python 읽기 검사. 이미지를 Python으로 수정하지 않음.

## road_sprout

- 프로젝트 파일: `phone/assets/poses/road_sprout/fall-sheet.png`
- 최종 원본: `/Users/leejiho/.codex/generated_images/01a1ce54-1c38-7b20-8667-25193adf460c/exec-5c02d9db-50c1-49d7-a389-7b02432753ff.png`

### 최초 프롬프트

```text
Use case: stylized-concept. Create a production sprite sheet for the EXACT road_sprout green leaf-backed creature in the reference image; reference is identity/style/orientation only, replace running poses with a gentle stumble/fall/recovery. One transparent PNG, 4 columns by 2 rows, exactly 8 equally sized square cells, reading left to right then next row. 2:1 aspect ratio, ideally 2048x1024. Each frame same character scale, left-facing three-quarter camera, same lighting, baseline near 83% cell height, centered, all artwork within central 80% cell (10% transparent padding on EVERY side). No borders, text, grid, background, floor, sparkles, dust, or motion lines. Sequence: 1 braking with forepaws braced and body leaning backward, 2 front legs buckle and face surprised, 3 tips forward with hindquarters lifted and forepaws reaching, 4 gently lands belly-down with paws stretched forward and eyes closed, 5 rests belly-down head lifted eyes opening, 6 pushes upper body up with forepaws and tucked hindlegs, 7 rises into crouch, 8 stands comfortably on four paws ready to run. Genuine articulated limb/torso/face changes, not rotation of same drawing. Preserve round ears, orange eyes, cream muzzle and belly, dark paws, layered yellow-green leaf cape, head sprout and curled leaf-tipped tail exactly. Gentle playful, no injuries. Transparent alpha background, no color halo.
```

## puddle_pip

- 프로젝트 파일: `phone/assets/poses/puddle_pip/fall-sheet.png`
- 최종 원본: `/Users/leejiho/.codex/generated_images/01a1ce54-1c38-7b20-8667-25193adf460c/exec-c9124877-781c-4908-b37e-fce714d49efc.png`

### 최초 프롬프트

```text
Use case: stylized-concept. Create a production fall-and-recover animation sprite sheet for the EXACT creature in reference image. Reference is identity/style/orientation only. One transparent PNG, 4 columns by 2 rows, exactly 8 equally sized square cells reading left to right then next row, 2:1 aspect ratio. Each frame same character scale, same three-quarter camera and lighting, centered, all artwork within central 80% cell with 10% transparent padding on EVERY side. No borders/text/grid/background/floor/sparkles/dust/motion lines. Frame sequence: 1 braking and bracing, 2 losing balance with surprised face, 3 tipping forward with limbs reaching to catch balance, 4 gentle belly-down landing eyes closed, 5 belly-down with eyes opening and head lifted, 6 pushes up with forelimbs, 7 rises into crouch, 8 comfortably upright ready to move again. Genuine articulated pose changes of limbs/body/head, not rotation of same drawing. Gentle playful, no injuries, no new props. Preserve EXACT anatomy, silhouette, colors, materials, facial details, appendage count and identifying markings. Transparent alpha background, no color halo. Blue platypus/duck creature facing LEFT, yellow broad bill and webbed feet, cream belly, drooping blue head tuft, blue paddle tail. Keep same look. Winglike hands brace fall; feet slide under body and stand again.
```

## lamp_moth

- 프로젝트 파일: `phone/assets/poses/lamp_moth/fall-sheet.png`
- 최종 원본: `/Users/leejiho/.codex/generated_images/01a1ce54-1c38-7b20-8667-25193adf460c/exec-173b1c3b-6750-4bf8-b28f-4e2df80803ab.png`

### 최초 프롬프트

```text
Use case: stylized-concept. Create a production fall-and-recover animation sprite sheet for the EXACT creature in reference image. Reference is identity/style/orientation only. One transparent PNG, 4 columns by 2 rows, exactly 8 equally sized square cells reading left to right then next row, 2:1 aspect ratio. Each frame same character scale, same three-quarter camera and lighting, centered, all artwork within central 80% cell with 10% transparent padding on EVERY side. No borders/text/grid/background/floor/sparkles/dust/motion lines. Frame sequence: 1 braking and bracing, 2 losing balance with surprised face, 3 tipping forward with limbs reaching to catch balance, 4 gentle belly-down landing eyes closed, 5 belly-down with eyes opening and head lifted, 6 pushes up with forelimbs, 7 rises into crouch, 8 comfortably upright ready to move again. Genuine articulated pose changes of limbs/body/head, not rotation of same drawing. Gentle playful, no injuries, no new props. Preserve EXACT anatomy, silhouette, colors, materials, facial details, appendage count and identifying markings. Transparent alpha background, no color halo. Purple moth facing RIGHT with four purple wings bearing golden luminous markings, small purple legs, glossy dark eyes, two curved antennae with glowing yellow bulbs. Adapt fall sequence to insect anatomy: wings flare to brake, uneven wingbeat tips it forward, legs reach, gentle belly-down low wings, lift head, push up on legs, spread wings, recover upright hover. Do not invent mammal limbs.
```

## storm_lantern

- 프로젝트 파일: `phone/assets/poses/storm_lantern/fall-sheet.png`
- 최종 원본: `/Users/leejiho/.codex/generated_images/01a1ce54-1c38-7b20-8667-25193adf460c/exec-f1812daf-d8d2-48d0-ad50-d4c41fb0e1ff.png`

### 최초 프롬프트

```text
Use case: stylized-concept. Create a production fall-and-recover animation sprite sheet for the EXACT creature in reference image. Reference is identity/style/orientation only. One transparent PNG, 4 columns by 2 rows, exactly 8 equally sized square cells reading left to right then next row, 2:1 aspect ratio. Each frame same character scale, same three-quarter camera and lighting, centered, all artwork within central 80% cell with 10% transparent padding on EVERY side. No borders/text/grid/background/floor/sparkles/dust/motion lines. Frame sequence: 1 braking and bracing, 2 losing balance with surprised face, 3 tipping forward with limbs reaching to catch balance, 4 gentle belly-down landing eyes closed, 5 belly-down with eyes opening and head lifted, 6 pushes up with forelimbs, 7 rises into crouch, 8 comfortably upright ready to move again. Genuine articulated pose changes of limbs/body/head, not rotation of same drawing. Gentle playful, no injuries, no new props. Preserve EXACT anatomy, silhouette, colors, materials, facial details, appendage count and identifying markings. Transparent alpha background, no color halo. Yellow stocky four-legged thunder creature facing RIGHT, dark storm-cloud lobes around head, yellow lightning markings, orange eyes, glowing yellow chest, dark claws, short tail. All four legs remain anatomically correct through stumble and push-up.
```

### 배경 정리 프롬프트

```text
Precise background extraction edit. Keep all EIGHT existing creature poses, colors, anatomy, shading, layout, cell positions, scale, and 4x2 grid alignment EXACTLY unchanged. Remove EVERY background pixel, ground plane, floor shadow, haze, glow outside the creature silhouettes, color speckles and visible grid/border line. Result must have completely transparent alpha=0 empty space around each sprite, including all corners and all cell boundaries. Preserve body highlights/white belly and any glowing markings INSIDE the character. Do not add outlines, do not redraw characters or change the animation. The entire canvas is transparent except crisp antialiased character silhouettes. No checkerboard pixels baked into image. No floor beneath characters.
```

## highway_comet

- 프로젝트 파일: `phone/assets/poses/highway_comet/fall-sheet.png`
- 최종 원본: `/Users/leejiho/.codex/generated_images/01a1ce54-1c38-7b20-8667-25193adf460c/exec-86c3715f-2ea8-4297-922a-2c2b5305acaa.png`

### 최초 프롬프트

```text
Use case: stylized-concept. Create a production fall-and-recover animation sprite sheet for the EXACT creature in reference image. Reference is identity/style/orientation only. One transparent PNG, 4 columns by 2 rows, exactly 8 equally sized square cells reading left to right then next row, 2:1 aspect ratio. Each frame same character scale, same three-quarter camera and lighting, centered, all artwork within central 80% cell with 10% transparent padding on EVERY side. No borders/text/grid/background/floor/sparkles/dust/motion lines. Frame sequence: 1 braking and bracing, 2 losing balance with surprised face, 3 tipping forward with limbs reaching to catch balance, 4 gentle belly-down landing eyes closed, 5 belly-down with eyes opening and head lifted, 6 pushes up with forelimbs, 7 rises into crouch, 8 comfortably upright ready to move again. Genuine articulated pose changes of limbs/body/head, not rotation of same drawing. Gentle playful, no injuries, no new props. Preserve EXACT anatomy, silhouette, colors, materials, facial details, appendage count and identifying markings. Transparent alpha background, no color halo. Orange rabbit creature facing RIGHT, enormous long backward swept ears, cream muzzle/belly/paws, yellow dots on back and warm yellow fluffy tail. Hands reach forward and knees buckle, belly-down with ears flopped, hands push up, knees tucked, then stand. Keep ears entirely inside each cell.
```

## sea_mist

- 프로젝트 파일: `phone/assets/poses/sea_mist/fall-sheet.png`
- 최종 원본: `/Users/leejiho/.codex/generated_images/01a1ce54-1c38-7b20-8667-25193adf460c/exec-3ff5a5c6-2d14-41ce-8e55-f81643df5ca9.png`

### 최초 프롬프트

```text
Use case: stylized-concept. Create a production fall-and-recover animation sprite sheet for the EXACT creature in reference image. Reference is identity/style/orientation only. One transparent PNG, 4 columns by 2 rows, exactly 8 equally sized square cells reading left to right then next row, 2:1 aspect ratio. Each frame same character scale, same three-quarter camera and lighting, centered, all artwork within central 80% cell with 10% transparent padding on EVERY side. No borders/text/grid/background/floor/sparkles/dust/motion lines. Frame sequence: 1 braking and bracing, 2 losing balance with surprised face, 3 tipping forward with limbs reaching to catch balance, 4 gentle belly-down landing eyes closed, 5 belly-down with eyes opening and head lifted, 6 pushes up with forelimbs, 7 rises into crouch, 8 comfortably upright ready to move again. Genuine articulated pose changes of limbs/body/head, not rotation of same drawing. Gentle playful, no injuries, no new props. Preserve EXACT anatomy, silhouette, colors, materials, facial details, appendage count and identifying markings. Transparent alpha background, no color halo. Pale mint and cream manta-ray sea spirit facing RIGHT, curled hornlike head fins, dark blue eyes, lavender spots and stripe markings, two wide side fins and long lavender-tipped tail. Adapt fall to fins: flare fins braking, lose hover balance, nose forward with fins reaching, gentle belly-down fins folded, raise head, prop up with fins, spread fins, upright hovering recovery. Do not invent feet or mammal hands.
```

### 배경 정리 프롬프트

```text
Precise background extraction edit. Keep all EIGHT existing creature poses, colors, anatomy, shading, layout, cell positions, scale, and 4x2 grid alignment EXACTLY unchanged. Remove EVERY background pixel, ground plane, floor shadow, haze, glow outside the creature silhouettes, color speckles and visible grid/border line. Result must have completely transparent alpha=0 empty space around each sprite, including all corners and all cell boundaries. Preserve body highlights/white belly and any glowing markings INSIDE the character. Do not add outlines, do not redraw characters or change the animation. The entire canvas is transparent except crisp antialiased character silhouettes. No checkerboard pixels baked into image. No floor beneath characters.
```
