# README 배너 제작 기록

- 파일: `allo-readme-banner.png`
- 크기: 2172 × 724px (3:1)
- 제작일: 2026-11-15
- 입력: 사용자가 제공한 ALLO 로고 이미지. 글자·캐릭터·색감을 유지할 합성 기준으로 사용.
- 도구: 내장 `image_gen` 이미지 편집. CLI/API 우회나 후처리 합성 없이 생성한 PNG를 사용.
- 용도: 저장소 README 상단 배너.

## 최종 프롬프트

```text
Use case: compositing. Asset type: polished GitHub README hero banner for ALLO, a family road-trip companion collecting game. Edit the supplied image into ONE finished very wide landscape banner, roughly 3:1 aspect ratio (1800x600 composition). Input image role: exact brand logo and mascot to preserve, not a loose inspiration. Preserve the exact supplied hand-drawn ALLO lettering and smiling green-eared cream mascot, egg in the O, dark green outlines and colors; no redesign, no duplicate logo. Remove the vast white margins and make this existing logo the dominant hero in the center, occupying about 52% of banner width and 72% of height. Build a tasteful restrained illustrated scene around it in the same flat hand-drawn style: soft warm ivory sky, layered pale sage and forest-green rolling hills with a gentle winding golden road continuing the hills already in the logo. A few tiny understated leaf/flower accents near bottom corners, quiet open space at both sides, no clutter. Logo reads immediately at GitHub README width. Crisp clean edges and limited colors, premium cozy indie-game identity; not glossy, not pixel art, not a UI, no browser mockup. Text: only the exact existing letters 'ALLO' from the source image; no additional words, no slogan, no labels, no badges, no watermarks. Full-bleed rectangular canvas, no outer frame, no drop shadow, no giant white dead space. Keep original mascot face, ears, paws, egg and logo shape faithfully.
```
