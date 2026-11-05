# 아트 (D)

스타일·캐릭터·화면 기준은 [`docs/art-direction.md`](../docs/art-direction.md)를 따른다. 시안은 `design/`에 있다.

## 네이밍 규칙 (B·D 합의)

스프라이트 파일명은 **종 id 그대로** 쓴다. `data/species.json` 의 `sprite` 필드와 일치해야 코드 수정 없이 교체된다. 기본 포즈(idle)가 이 파일이고, 나머지 상태는 접미사만 붙인다.

```
phone/assets/species/{id}.png                 idle (기본 포즈. 예: tide_keeper.png)
phone/assets/species/{id}_{state}.png         (제안, B 확인 전) state: happy, sleepy, look, surprise, signature
phone/assets/egg/egg_{tier}_{stage}.png       예) egg_small_1.png  (stage 1~3: 초기/중기/부화직전)
phone/assets/egg/hatch_{n}.png                부화 연출 프레임 (금 가기 3컷, 빛 2컷)
phone/assets/egg/pattern_{tag}.png            (제안, B 확인 전) 알 환경 무늬 레이어. tag 는 schema 의 envTags
phone/assets/ui/...                           버튼, 진행바, 도감 프레임
```

종 12개 × 6상태 = 72장이다. 상태 PNG가 없을 때 idle로 대체할지는 B와 합의한다.

## 스펙

- 소프트 3D 일러스트, 실제 알파 채널이 있는 투명 PNG. 체크무늬 배경을 그림에 넣지 않는다
- 원본 1024×1024, export 512×512
- 앉은 3/4 정면, 12종 같은 카메라·크기. 발끝이 캔버스 아래에서 8% 위인 같은 기준선. 그림자는 별도 레이어 권장
- 눈은 크고 둥근 짙은 브라운에 흰 하이라이트 2점. 머리·등 돌기는 둥글고 뭉툭하게
- 속성별 색 계열: water Sky `#A9D4F1` / dark Lavender `#C9B9E8` / normal Sage `#B9D0B9`
- 등급이 높을수록 장식·재질·이펙트 밀도를 높인다 (색만 바꾸면 티가 안 남). 규칙은 art-direction 5절

## 폴더

- `src/` — 원본 (.psd, .blend, 생성 프롬프트 기록 등)
- `export/` — png. B 가 `phone/assets/` 로 복사
- `design/` — 시안 HTML (`characters.html`, `wireframes.html`). 브라우저로 연다. 레퍼런스 시트 이미지(`ref/`)는 IP 확인 후 추가

## 라이선스

무료 에셋 팩이나 생성 도구를 쓰면 **출처·도구·라이선스를 루트 README '에셋 출처'에 적는다.** 생성 프롬프트와 수정 이력은 `src/prompts.md`에 보관한다.
