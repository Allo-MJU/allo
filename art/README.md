# 아트 (D)

## 네이밍 규칙 (B·D 합의)

스프라이트 파일명은 **종 id 그대로** 쓴다. `data/species.json` 의 `sprite` 필드와 일치해야 코드 수정 없이 교체된다.

```
phone/assets/species/{id}.png          예) tide_keeper.png
phone/assets/egg/egg_{tier}_{stage}.png 예) egg_small_1.png  (stage 1~3: 초기/중기/부화직전)
phone/assets/egg/hatch_{n}.png          부화 연출 프레임 (금 가기 3컷, 빛 2컷)
phone/assets/ui/...                     버튼, 진행바, 도감 프레임
```

## 스펙

색, 글자, 컴포넌트, 캐릭터 표현은 [`docs/design-system.md`](../docs/design-system.md)를 따른다. 토큰 원본은 [`design/tokens.json`](./design/tokens.json)이다.

- 캐릭터는 `character-production-01`(2026-11-05 승인 12종)의 스타일라이즈드 3D다. 도트 48×48 기준은 폐기했다
- 종마다 시그니처 색 4개(base·deep·accent·tint)를 쓴다. 속성별 3색 계열은 쓰지 않는다
- 등급 차이는 배지와 부화 연출로 낸다(design-system 8절)

## 폴더

- `src/` — .aseprite 등 원본
- `export/` — png. B 가 `phone/assets/` 로 복사

## 라이선스

무료 에셋 팩을 베이스로 쓰면 **출처와 라이선스를 루트 README '에셋 출처'에 적는다.**
