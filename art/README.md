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

- 도트 48×48, 팔레트 16색 이내
- 속성별 색 계열: water 청 / dark 보라 / normal 녹
- tier 가 높을수록 실루엣이 복잡하고 장식이 많게 (색만 바꾸면 티가 안 남)

## 폴더

- `src/` — .aseprite 등 원본
- `export/` — png. B 가 `phone/assets/` 로 복사

## 라이선스

무료 에셋 팩을 베이스로 쓰면 **출처와 라이선스를 루트 README '에셋 출처'에 적는다.**
