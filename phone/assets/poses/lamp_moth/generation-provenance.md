# lamp_moth 동작 시트 생성 기록

- 날짜: 2026-11-11
- 도구: built-in image_gen (imagegen skill). AI로 생성한 파생 동작 프레임이며 디자이너 원본이 아님.
- 원본: 같은 폴더의 move.png, idle.png, sleep.png. 디자인 PR #86 / c24eeaa507bdec1bc7d292d096af7b1967dae07d 기준 원본은 수정하지 않음.
- 출력: run-sheet.png, fish-sheet.png, sleep-sheet.png. 각각 1774×887 RGBA, 4열×2행, row-major 8 프레임. 프레임 크기는 443.5×443.5.
- QA: 8개 개별 포즈와 프레임 내 전체 캐릭터를 육안 확인. 달리기는 나방 해부구조에 맞춘 날갯짓으로 구현. 낚시는 앞다리로 낚싯대 들기/물고기 놓치기/재정렬 확인. 잠자기는 날개 펴며 호흡/고개 기울이기/날개로 몸 감싸기/복귀 확인. 세 시트 alpha min 0, max 255; 원래 alpha 보존. 미리보기 저알파 노이즈를 이유로 원본을 불필요하게 변형하지 않음. 기기 재생 QA는 별도.
- 생성 이력: 잠자기 첫 시도는 output moderation category other 오류(71b01d2f-6f2e-4b99-881b-3c24ad73d914)로 이미지 미생성. 무해한 만화 나방 수면 동작으로 프롬프트를 단순화한 재시도는 정상 완료.

## run-sheet.png

Reference: move.png + idle.png

Generated source: /Users/leejiho/.codex/generated_images/01a1c812-be44-72a1-8ac5-bc94b6a65483/exec-f38c4b8c-1328-446e-8c13-4a92a6241c5a.png

Exact prompt:

```text
Use case: stylized-concept. Production game animation sprite sheet. Use supplied images strictly as character identity and rendering style references. ONE transparent PNG, EXACTLY eight sequential poses in a perfectly aligned 4 column by 2 row equal-cell grid, row-major. Same character scale, fixed three-quarter camera, consistent torso anchor within each cell, full character and all props inside cell with 10% padding. True alpha zero outside art, no backdrop, no floor, no shadows, no grid lines, no labels, no text, no action symbols. Preserve exact color palette, anatomy, markings and soft polished game render. Articulate body parts between frames; never repeat one static pose transformed. Seamless cycle, last pose returns toward first. Character is purple lamp moth with four broad scalloped purple wings, orange-yellow luminous teardrop markings, mauve rounded head with large glossy dark eyes, two thin antennae with glowing golden spherical tips, segmented purple thorax and thin insect legs. Preserve insect anatomy: no human arms, hands or mammal legs. Travel/run animation adapted to a moth: fly facing RIGHT with powerful articulated wing beats. Frame1 wings up and legs tucked; 2 wings halfway down, antennae trail; 3 full downstroke wings swept low; 4 wings sweep backward, insect legs flex; 5 wings start recovery half-open; 6 wings raised; 7 wings fully up, antennae recoil; 8 wings start next downstroke. Wings rotate/fold at their roots naturally, head steady, not body bouncing. Keep wing patterns on each wing consistent.
```

## fish-sheet.png

Reference: idle.png

Generated source: /Users/leejiho/.codex/generated_images/01a1c812-be44-72a1-8ac5-bc94b6a65483/exec-14d97850-3500-47d6-bc5d-5b795141f248.png

Exact prompt:

```text
Use case: stylized-concept. Production game animation sprite sheet. Use supplied images strictly as character identity and rendering style references. ONE transparent PNG, EXACTLY eight sequential poses in a perfectly aligned 4 column by 2 row equal-cell grid, row-major. Same character scale, fixed three-quarter camera, consistent torso anchor within each cell, full character and all props inside cell with 10% padding. True alpha zero outside art, no backdrop, no floor, no shadows, no grid lines, no labels, no text, no action symbols. Preserve exact color palette, anatomy, markings and soft polished game render. Articulate body parts between frames; never repeat one static pose transformed. Seamless cycle, last pose returns toward first. Character is purple lamp moth with four broad scalloped purple wings, orange-yellow luminous teardrop markings, mauve rounded head with large glossy dark eyes, two thin antennae with glowing golden spherical tips, segmented purple thorax and thin insect legs. Preserve insect anatomy: no human arms, hands or mammal legs. Moth sits hovering low with wings partially open and changing angle for balance; uses its existing front pair of slender insect legs to grip small fishing rod, other insect legs remain tucked, absolutely no human hands. Fishing animation, character and rod face RIGHT. Rod and hanging line remain entirely within every grid cell. Eight distinct key poses:1 relaxed holding rod low;2 detects tug, head dips and forelimbs bend;3 leans back and raises rod with flexed forelimbs;4 raises tiny golden fish on line, eyes delighted;5 fish wiggles free, character leans/reaches in surprise;6 fish drops away, character leans forward looking down;7 regrips rod and lowers it;8 returns relaxed pose. Clearly articulate forelimbs,head,torso and wings through action. No lake or background.
```

## sleep-sheet.png

Reference: sleep.png

Generated source: /Users/leejiho/.codex/generated_images/01a1c812-be44-72a1-8ac5-bc94b6a65483/exec-e405c64a-92fa-46f1-92b8-f57cd6b998ca.png

Exact prompt:

```text
Use case: stylized-concept. Production game animation sprite sheet. Use supplied images strictly as character identity and rendering style references. ONE transparent PNG, EXACTLY eight sequential poses in a perfectly aligned 4 column by 2 row equal-cell grid, row-major. Same character scale, fixed three-quarter camera, consistent torso anchor within each cell, full character and all props inside cell with 10% padding. True alpha zero outside art, no backdrop, no floor, no shadows, no grid lines, no labels, no text, no action symbols. Preserve exact color palette, anatomy, markings and soft polished game render. Articulate body parts between frames; never repeat one static pose transformed. Seamless cycle, last pose returns toward first. Character is purple lamp moth with four broad scalloped purple wings, orange-yellow luminous teardrop markings, mauve rounded head with large glossy dark eyes, two thin antennae with glowing golden spherical tips, segmented purple thorax and thin insect legs. Preserve insect anatomy: no human arms, hands or mammal legs. Eight gentle sleeping animation frames of this cartoon moth. 1 head bowed,eyes closed,wings draped;2 breathing in,wings gently part;3 breathing out,wings settle;4 head tilts to one side, antennae dip;5 wings fold around body;6 head rests against folded wing;7 wings open slightly as head turns back;8 returns original bowed-head sleeping position. Keep its existing insect anatomy and closed eyes, no text or symbols.
```

## 실패한 첫 sleep 프롬프트 (출력 없음)

Reference: sleep.png + idle.png

```text
Use case: stylized-concept. Production game animation sprite sheet. Use supplied images strictly as character identity and rendering style references. ONE transparent PNG, EXACTLY eight sequential poses in a perfectly aligned 4 column by 2 row equal-cell grid, row-major. Same character scale, fixed three-quarter camera, consistent torso anchor within each cell, full character and all props inside cell with 10% padding. True alpha zero outside art, no backdrop, no floor, no shadows, no grid lines, no labels, no text, no action symbols. Preserve exact color palette, anatomy, markings and soft polished game render. Articulate body parts between frames; never repeat one static pose transformed. Seamless cycle, last pose returns toward first. Character is purple lamp moth with four broad scalloped purple wings, orange-yellow luminous teardrop markings, mauve rounded head with large glossy dark eyes, two thin antennae with glowing golden spherical tips, segmented purple thorax and thin insect legs. Preserve insect anatomy: no human arms, hands or mammal legs. Sleeping moth: wings draped down around its insect body like reference, eyes gently closed, antennae golden tips. Frame1 resting head bowed,wings draped;2 inhale thorax expands subtly,wings gently part;3 exhale,wings settle;4 front insect legs tuck beneath cheek, head tilts;5 body turns slightly sideways,wings fold closer;6 settles on side, antennae droop;7 rolls back facing original angle,wings open slightly;8 returns resting bowed head. No invented paws or hands. Actual articulated sleep poses with breathing, tucking and small turn, not identical PNG scaled or bobbed. No Z symbols.
```
