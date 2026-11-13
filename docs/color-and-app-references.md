---
name: ALLO
colors:
  surface: "#FFFFFF"
  surface-soft: "#F4F7F3"
  ink: "#111111"
  ink-muted: "#56675D"
  line: "#DDE6DE"
  control-outline: "#738478"
  shell-yellow: "#FCCC44"
  growth-green: "#1D9965"
  action-green: "#146B49"
  success-surface: "#E8F5ED"
  error-ink: "#A1282B"
  error-surface: "#FFF2F1"
  car-surface: "#181C1E"
  car-ink: "#F4F8F5"
---

# 알로 색상 가이드와 참고 앱

![알로 색상표와 참고 앱](./assets/allo-colors-and-app-references.png)

## 색상 가이드

| 색 | HEX | 쓰는 곳 |
|---|---|---|
| 흰색 | `#FFFFFF` | 폰 화면의 기본 면, 어두운 버튼의 글자 |
| 알 노랑 | `#FCCC44` | 윗껍질, 부화, 새 친구 라벨처럼 발견에 해당하는 순간 |
| 알 초록 | `#1D9965` | 로고 몸체, 진행바와 성장 표시 |
| 동작 초록 | `#146B49` | `감싸기`, `봤어!` 등 다음 행동과 선택된 탭 |
| 먹색 | `#111111` | 검은 LLO, 제목, 본문, 노란 라벨 위 글자 |
| 옅은 녹색 면 | `#F4F7F3` | 알과 캐릭터 뒤의 조용한 면, 필터와 구역 분리 |
| 보조 글자 | `#56675D` | 남은 시간의 설명, 환경, 보조 문구 |
| 구분선 / 입력 테두리 | `#DDE6DE` / `#738478` | 구획을 나누는 얇은 선 / 흰 입력칸의 식별 경계 |
| 완료 면 | `#E8F5ED` | 연결 확인과 완료 상태에 동작 초록 글자·아이콘을 곁들임 |
| 오류 글자 / 면 | `#A1282B` / `#FFF2F1` | 연결 코드 오류나 재연결이 필요한 상태 |
| Pleos 바탕 / 글자 | `#181C1E` / `#F4F8F5` | 정차 중 앱 창 안에서 큰 글자와 필요한 상태만 표시 |

흰색 글자와 동작 초록의 대비는 **6.50:1**, 먹색 글자와 알 노랑은 **12.46:1**이다. 흰색과 알 초록의 조합은 **3.62:1**이므로 작은 버튼 글자에는 동작 초록을 쓴다. [W3C 텍스트 대비 기준](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)

## 참고 앱

| 앱 | 참고 기능 |
|---|---|
| Pokémon Sleep | 수면 기록 후 캐릭터를 발견하고 도감을 채우는 흐름. [공식 게임 소개](https://www.pokemonsleep.net/en/pokemon/) |
| Finch | 현실의 목표와 알의 부화를 연결하는 Micropet Lab. [공식 도움말](https://help.finchcare.com/hc/en-us/articles/37780505907469-Using-the-Micropet-Lab) |
| Pikmin Bloom | 이동 중 얻은 엽서와 날짜별 활동을 다시 보는 기록. [공식 제품 소개](https://pikminbloom.com/en) · [Lifelog](https://scopelyexplore.helpshift.com/hc/en/11-pikmin-bloom/faq/2148-lifelog/) |
| LEGO Builder | 3D 모델의 확대·회전과 조립 진행 저장. [공식 기능 소개](https://www.lego.com/en-us/builder-app) |
| Pokémon GO | 이동 경로에서의 캐릭터 발견과 수집. [GO Wild Area 공식 소개](https://pokemongo.com/gowildarea/global) |

## 성격별 추가 참고 (2026-11-12 조사)

위 다섯 앱은 수집 흐름 중심이다. 아래는 차량 연동·뒷자리·아이·영어 대화라는 알로의 다른 성격에 맞춘 참고다.

### 차 움직임과 화면 연동

| 참고 | 참고 기능 | 알로에 적용 |
|---|---|---|
| Apple Vehicle Motion Cues | 화면 가장자리 점이 가속 시 아래, 제동 시 위, 회전 시 옆으로 움직임. iOS 26부터 크기·색·개수 조절. [heise](https://heise.de/en/news/New-function-in-iOS-18-How-the-iPhone-combats-motion-sickness-9794655.html) · [9to5Mac](https://9to5mac.com/2024/10/11/ios-18-fixed-my-motion-sickness-problem-with-one-new-feature/) | 폰 화면 테두리에 껍질 조각·반짝이를 같은 원리로 흘리는 연출. 효과가 입증되지 않았으므로 멀미 대책이 아니라 재미 연출로만 쓴다 |
| holoride Elastic Content | 차의 회전·가속에 맞춰 가상 세계가 움직이고, 남은 시간·경로에 맞춰 콘텐츠 길이가 바뀜. [MIXED 소개 기사](https://mixed-news.com/en/holoride-launches-and-brings-virtual-reality-to-cars/) (공식 사이트는 2026-11-12 기준 접속 불가) | 여행 한 판 3막 구조를 남은 시간에 맞춰 늘리고 줄이는 근거 |

### 차와 폰 연결

| 참고 | 참고 기능 | 알로에 적용 |
|---|---|---|
| Audi × AirConsole, Pictionary Car Party | 폰으로 QR을 찍어 차에 연결, 최대 4명. 운전석 쪽은 digital curtain으로 가림. [Audi 보도자료](https://www.audi.com/en/media-releases/gaming-fun-on-the-go-audi-integrates-airconsole-16729) | 페어링 화면과 운전자 보호 방식의 비교 대상. 심사에서 언급될 수 있는 경쟁 사례 |

### 차량 플랫폼 규칙

| 참고 | 참고 기능 | 알로에 적용 |
|---|---|---|
| Pleos Connect 디자인 가이드 | 내장 UI와 아이콘·용어·인터랙션 일치, 한 손 조작, 보이는 버튼보다 큰 터치 영역, Standard·Lite·Wide 화면 대응. [App Design Guide](https://document.pleos.ai/en/docs/pleos-only/vehicle-app-planning-guide/intro) · [Layout](https://pleos.ai/playground/resources/en/docs/docs-design-pleos/getting-started/layout) | `car/` 화면의 Lite 축소안과 터치 영역 기준 |
| AAOS 주차 중 앱 규칙 | Google Play 게임 카테고리는 주행 중 UI 표시·오디오 재생 불가. [Parked and passenger apps](https://developer.android.com/design/ui/cars/guides/app-types/parked-passenger-apps) · [Car app quality](https://developer.android.com/docs/quality-guidelines/car-app-quality) | 주행 중 차 화면에 펫 애니메이션을 띄우는 것이 Pleos에서 허용되는 범위인지 `verification.md`에 확인 기록이 필요하다 |

### 아이용 시각 언어

| 참고 | 참고 기능 | 알로에 적용 |
|---|---|---|
| Duolingo 캐릭터 가이드 | 최소한의 도형과 평면 원근, 둥근 사각형·원·둥근 삼각형 위주. [캐릭터 가이드](https://design.duolingo.com/illustration/characters) · [shape language](https://blog.duolingo.com/shape-language-duolingos-art-style/) | 12종 스프라이트 포즈를 늘릴 때 형태 기준 |
| Khan Academy Kids | 캐릭터가 활동을 안내하고, 모은 액세서리로 캐릭터를 꾸밈. 광고 없는 화면. [Khan Academy 블로그](https://blog.khanacademy.org/supporting-english-language-acquisition-with-khan-academy-kids/) | 캐릭터 안내 방식과 부모 신뢰 요소 |
| Toca Boca | 글·튜토리얼·패배 없이 조작만으로 이해되는 놀이. [Kill Screen](https://www.killscreen.com/what-designers-can-learn-about-play-children/) · [GamesBeat](https://gamesbeat.com/how-toca-boca-got-100m-mobile-downloads-by-putting-kids-first/) | 부화·`봤어!` 흐름을 아이콘과 동작만으로 읽히게 하는 기준 |

### 캐릭터 영어 대화

| 참고 | 참고 기능 | 알로에 적용 |
|---|---|---|
| Duolingo Video Call × Rive | 정해진 클립 대신 표정 조각을 실시간 조합. 듣기·생각·대답 상태 분리, 시작·본 대화·마무리 구조. [Rive 사례](https://rive.app/blog/duolingo-s-ai-powered-video-call-brings-lily-to-life) · [Duolingo 블로그](https://blog.duolingo.com/ai-and-video-call) | `phone/lib/child_chat/`의 캐릭터 표정 상태와 대화 구조 |

### 수집과 도감

| 참고 | 참고 기능 | 알로에 적용 |
|---|---|---|
| Neko Atsume | 도감(Catbook)과 기념품(memento)이 분리. 자주 온 고양이일수록 기념품 확률 상승. [위키 Game Menu](https://nekoatsume.fandom.com/wiki/Game_Menu) | 같은 생물과 여러 번 여행했을 때의 보상 설계 |
| Tamagotchi Uni | 알 색이 달라도 태어나는 아기는 같음. [위키 Egg](https://tamagotchi.fandom.com/wiki/Egg) | 알이 결과를 예고하는 알로와 대비되는 사례 |
