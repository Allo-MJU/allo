# highway_comet 동작 시트 생성 기록

- 날짜: 2026-11-11
- 도구: built-in image_gen (imagegen skill). AI로 생성한 파생 동작 프레임이며 디자이너 원본이 아님.
- 원본: 같은 폴더의 move.png, idle.png, sleep.png. 디자인 PR #86 / c24eeaa507bdec1bc7d292d096af7b1967dae07d 기준 원본은 수정하지 않음.
- 출력: run-sheet.png, fish-sheet.png, sleep-sheet.png. 각각 1774×887 RGBA, 4열×2행, row-major 8 프레임. 프레임 크기는 443.5×443.5.
- QA: 8개 개별 포즈와 프레임 내 전체 캐릭터를 육안 확인. 토끼 앞뒤 발 관절과 귀가 달리기 동작에 따라 바뀜. 낚싯대 들기/물고기 놓치기/재정렬 확인. 잠자기는 호흡/앞발을 뺨에 넣기/옆으로 뒤척이기/복귀 확인. 세 시트 alpha min 0, max 255; 원래 alpha 보존. 낚시 시트를 어두운 남색 배경에 합성해 저알파 미리보기 노이즈가 실제로 두드러지지 않음을 확인. 기기 재생 QA는 별도.

## run-sheet.png

Reference: move.png + idle.png

Generated source: /Users/leejiho/.codex/generated_images/01a1c812-be44-72a1-8ac5-bc94b6a65483/exec-35174764-94a4-4a97-be74-3c91d51a4f0b.png

Exact prompt:

```text
Use case: stylized-concept. Production game animation sprite sheet. Use supplied images strictly as character identity and rendering style references. ONE transparent PNG, EXACTLY eight sequential poses in a perfectly aligned 4 column by 2 row equal-cell grid, row-major. Same character scale, fixed three-quarter camera, consistent torso anchor within each cell, full character and all props inside cell with 10% padding. True alpha zero outside art, no backdrop, no floor, no shadows, no grid lines, no labels, no text, no action symbols. Preserve exact color palette, anatomy, markings and soft polished game render. Articulate body parts between frames; never repeat one static pose transformed. Seamless cycle, last pose returns toward first. Character is orange comet rabbit with enormous orange ears and cream inner ears, cream cheeks/belly/paws, large orange-brown eyes, yellow spots on haunch, huge hind feet with pink pads and a fan-shaped golden fluffy comet tail. Preserve exact rabbit identity, four limbs only. Natural rabbit running/hopping cycle facing RIGHT. Frame1 hind legs planted bent, forepaws reaching;2 hind legs push backward,forepaws tuck;3 hind legs extended back,body stretches;4 aerial extension front paws forward;5 forepaws land, hind legs swing forward;6 body compresses hind knees forward;7 hindfeet plant and forepaws lift;8 begins push off returning firstpose. Ears bend and trail with momentum, tail follows torso. Real alternating limb articulation and flexion, no static image bounce. No speed trails.
```

## fish-sheet.png

Reference: idle.png

Generated source: /Users/leejiho/.codex/generated_images/01a1c812-be44-72a1-8ac5-bc94b6a65483/exec-895f02e7-ae1e-47d4-afbb-e7a33e9071ee.png

Exact prompt:

```text
Use case: stylized-concept. Production game animation sprite sheet. Use supplied images strictly as character identity and rendering style references. ONE transparent PNG, EXACTLY eight sequential poses in a perfectly aligned 4 column by 2 row equal-cell grid, row-major. Same character scale, fixed three-quarter camera, consistent torso anchor within each cell, full character and all props inside cell with 10% padding. True alpha zero outside art, no backdrop, no floor, no shadows, no grid lines, no labels, no text, no action symbols. Preserve exact color palette, anatomy, markings and soft polished game render. Articulate body parts between frames; never repeat one static pose transformed. Seamless cycle, last pose returns toward first. Character is orange comet rabbit with enormous orange ears and cream inner ears, cream cheeks/belly/paws, large orange-brown eyes, yellow spots on haunch, huge hind feet with pink pads and a fan-shaped golden fluffy comet tail. Preserve exact rabbit identity, four limbs only. Rabbit sits on hindquarters, uses its existing two front paws to grip small fishing rod. Fishing animation, character and rod face RIGHT. Rod and hanging line remain entirely within every grid cell. Eight distinct key poses:1 relaxed holding rod low;2 detects tug, head dips and forelimbs bend;3 leans back and raises rod with flexed forelimbs;4 raises tiny golden fish on line, eyes delighted;5 fish wiggles free, character leans/reaches in surprise;6 fish drops away, character leans forward looking down;7 regrips rod and lowers it;8 returns relaxed pose. Clearly articulate forelimbs,head,torso and ears/tail through action. No lake or background.
```

## sleep-sheet.png

Reference: sleep.png + idle.png

Generated source: /Users/leejiho/.codex/generated_images/01a1c812-be44-72a1-8ac5-bc94b6a65483/exec-b6ae32fb-4a5a-423c-8146-44de8b0c180c.png

Exact prompt:

```text
Use case: stylized-concept. Production game animation sprite sheet. Use supplied images strictly as character identity and rendering style references. ONE transparent PNG, EXACTLY eight sequential poses in a perfectly aligned 4 column by 2 row equal-cell grid, row-major. Same character scale, fixed three-quarter camera, consistent torso anchor within each cell, full character and all props inside cell with 10% padding. True alpha zero outside art, no backdrop, no floor, no shadows, no grid lines, no labels, no text, no action symbols. Preserve exact color palette, anatomy, markings and soft polished game render. Articulate body parts between frames; never repeat one static pose transformed. Seamless cycle, last pose returns toward first. Character is orange comet rabbit with enormous orange ears and cream inner ears, cream cheeks/belly/paws, large orange-brown eyes, yellow spots on haunch, huge hind feet with pink pads and a fan-shaped golden fluffy comet tail. Preserve exact rabbit identity, four limbs only. Sleeping rabbit curled like reference, eyes closed throughout. Frame1 curled chin on forepaws;2 inhale chest expands and ears rise slightly;3 exhale ears settle;4 one forepaw slides under cheek,head tilts;5 turns slightly onto side,forepaws curl toward chest,hindquarters shift and comet tail wraps closer;6 settles side sleeping and breathes;7 rolls back toward belly,forepaws extend;8 returns curled chin on paws. Ears fold and relax naturally with turning. Actual articulated sleep poses with breathing, tucking and small turn, not identical PNG scaled or bobbed. No Z symbols.
```
