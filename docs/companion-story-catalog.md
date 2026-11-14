# 동행 친구 고정 스토리 카탈로그

작성: 2026-11-14 · **신규 11편은 사람의 내용 검토 전 초안**

서버 전용 원본은 `data/companion_learning/story.json`이다. 2026-11-14 사용자 추가 지시로 폰 번들 `phone/assets/data/companion_learning.json`은 종·스토리·버전·장면 ID만 담는 공개 manifest로 분리한다. 페르소나·이야기 본문·지식·다음 장면 결정은 서버에만 둔다. 카탈로그 스키마는 1이며 12편 모두 콘텐츠 버전 1이다. 총 36장면, 지식 항목 22개다. 기존 길싹이 1편의 내용·장면 ID·버전·직렬화된 본문은 그대로 보존했다.

이번에 이야기를 작성했다는 것은 사용자가 각 줄거리와 페르소나를 승인했거나 사람이 검수했다는 뜻이 아니다. 신규 11편은 각각 `contentStatus: draft-awaiting-human-review`, `reviewedBy: null`로 표시했다. 기존 길싹이 샘플 또한 사람이 검수 완료한 콘텐츠로 승격하지 않았다. 이 메타데이터는 검토 상태 표시이며 기존 런타임에 release 배포 차단 기능을 추가한 것은 아니다.

## 캐릭터 기준과 범위

기준은 `origin/dev`의 `c15c12e`에서 확인한 **표시용 원본 12종**인 `data/characters.json`이다. 신규 6종 이름과 성격은 같은 커밋의 `docs/dialogue-style.md` 5절 및 `car/app/src/main/assets/companion-dialogue.json`의 이름·출신·취향·기분 대사를 확인했다. 이 대사에는 신규 6종의 출신이 아직 미정이라고 적혀 있다. 새 스토리는 그 출신을 정하지 않고 가상 활동 하나를 서술한다. 종 이름만으로 속성·등급·출생지·부화 조건·능력을 만들지 않는다.

`data/species.json`의 예전 게임 규칙 12종과 표시용 원본 12종은 다르다. 예전 종의 ID·저장·획득 조건은 이번 작업으로 변경하지 않는다. 다리뛰기·산정령·강미끄럼·물결지기·터널나방·별부엉이는 예전 규칙 카탈로그에 남지만 이번 표시용 12편 확장의 대상에 포함하지 않았다. 새 6종의 이야기 데이터가 생겼다는 사실만으로 해당 종의 소유·획득 경로가 구현된 것은 아니다.

이 카탈로그는 [부화 후 고정 스토리 설계](superpowers/specs/2026-11-12-companion-story-learning-design.md)를 따른다. 창밖 환경에 맞춰 화면 속 장난감 실험을 고르는 `window_stories_ko.json`의 8편은 별도 모드다. 해당 대사·분기·카드·캐릭터 자료는 덮어쓰지 않았다.

## 이야기 목록

모든 이야기는 아래 순서의 3장면으로 끝난다. AI는 현재 장면의 사건과 허용 지식을 페르소나에 맞게 설명하며, 새 사건·다른 결말·다음 장면·보상을 만들지 않는다. 진도는 아이의 다음 이야기 선택으로만 이동한다.

| 종 ID · 이름 | 고정 이야기 | 시작 → 중간 → 결말 | 연결 소재 |
| --- | --- | --- | --- |
| `road_sprout` · 길싹이 | 길싹이의 작은 정원 | 화분 발견 → 물의 이동 → 잎을 만나 정원이라 부름 | 식물 성장·물·빛 |
| `breeze_wyrm` · 산들룡 | 산들룡의 잎사귀 무대 | 움직이지 않는 무대 → 바람과 리본 → 춤 이름과 방향 표시 완성 | 움직이는 공기·풍향 |
| `cloud_strider` · 구름발 | 구름발의 느린 산책 지도 | 종이에 안 들어가는 길 → 축척 정하기 → 쉼터 기호를 넣어 완성 | 지도·축척·미터와 센티미터 |
| `dewcap` · 이슬갓 | 이슬갓의 작은 물방울 기록장 | 비 없는 날의 물방울 → 이슬과 비 구별 → 이슬 없는 날도 기록 | 응결·관찰 조건 |
| `dune_roller` · 모래돌이 | 모래돌이의 멈춘 모래 사진 | 모래 언덕 사진 → 모래의 이동 알아보기 → 설명을 붙인 그림 앨범 | 모래 언덕·풍화와 이동 |
| `ember_crab` · 불씨게 | 불씨게의 포근한 책 자리 | 독서 자리 준비 → 열의 이동 알아보기 → 자유롭게 쉬는 자리 완성 | 단열·덮개의 역할 |
| `pebble_orbit` · 조약별 | 조약별의 딱 맞는 전시대 | 겹치는 종이 모형 → 같은 단위로 재기 → 10센티미터 전시대 완성 | 길이·같은 단위의 덧셈 |
| `puddle_pip` · 웅덩이삐약 | 웅덩이삐약의 사라진 물 그림 | 웅덩이 테두리 그림 → 줄어든 물 → 여러 물길의 엽서 완성 | 증발·물순환 |
| `sea_mist` · 바다안개 | 바다안개의 흐릿한 그림 지도 | 안개 그림 → 수증기와 구별 → 범례를 붙인 가상 지도 | 안개·물방울·지도 기호 |
| `storm_lantern` · 폭풍등 | 폭풍등의 번쩍 소리책 | 실내 그림책 → 천둥의 까닭 → 빛과 소리의 책 완성 | 번개·공기·빛과 소리 |
| `lamp_moth` · 등불나방 | 등불나방의 글자 등불 | 뜻 모를 표시 → 훈민정음 해례본 읽기 → 기호 뜻을 쓴 전시판 | 한글 창제와 해례본·기호 |
| `highway_comet` · 고속혜성 | 고속혜성의 거꾸로 꼬리 | 잘못 붙인 모형 꼬리 → 실제 자료 확인 → 이온 꼬리 방향을 고쳐 완성 | 혜성·태양·모형의 한계 |

영어는 별도 시험을 만들지 않고 지식 항목의 `words`에 한국어 뜻과 함께 둔다. 이야기에 어울릴 때 단어 하나를 연결할 수 있으며 매 응답에 넣거나 반복·발음을 강요하지 않는다. 과학·역사·지리·수학·생활 상식은 카탈로그 전체에 분산하고 모든 장면에 전 과목을 넣지 않았다.

부모님 제안은 **36장면 중 6장면**에만 있다. 기존 길싹이 1장면, 신규 구름발·이슬갓·불씨게·바다안개·등불나방 각 1장면이다. 모두 나중에 운전하지 않는 보호자와 할 수 있는 선택 사항이다. AI는 서버가 가진 원문 제안과 서버 빈도 정책을 따라야 하며 제안을 진행 조건으로 만들지 않는다. 새 대화 API의 제안 횟수 제한은 서버의 일시적인 개체/스토리별 카운터가 맡고 앱이 판단하지 않는다. 대화 원문을 영구 저장하지 않으며 서버 재시작 시 빈도 카운터는 초기화된다.

## 사실 자료와 출처

가상 정원·작업실·그림 지도·종이 모형은 스토리 설정이다. 지식 항목의 실재 사실과 분리한다. 지도 1:100, 가상 길 3미터, 종이 2·3·5센티미터 등은 직접 정한 예시이며 현실 여행이나 사용자 데이터가 아니다. 덧셈·단위 변환은 예시 계산이고 출처에서 이 이야기를 관측했다는 뜻이 아니다.

신규 자료의 `checkedOn`은 2026-11-14다. 다음 공식 기관의 페이지를 직접 열거나 검색 결과 본문으로 확인해 설명을 작성했다. 각 지식 항목에는 실제 사용한 출처만 연결했다. 기존 길싹이 출처의 날짜 2026-11-12는 변경하지 않았다.

| 사용처 | 공식 자료 · 확인한 범위 |
| --- | --- |
| 길싹이 기존 자료 | [ESA Astro farmer](https://climatedetectives.esa.int/astro-farmer/), [USGS Capillary Action and Water](https://www.usgs.gov/water-science-school/science/capillary-action-and-water) · 기존 식물 자료와 확인일 보존 |
| 산들룡 | [NOAA Origin of Wind](https://www.noaa.gov/jetstream/synoptic/origin-of-wind) · 움직이는 공기, 깃발 방향과 불어오는 쪽 |
| 구름발·바다안개 | [Geoscience Australia 지도 읽기](https://www.ga.gov.au/scientific-topics/national-location-information/topographic-maps/map-reading-guide) · 축척과 실제 거리, 기호와 범례 |
| 구름발·조약별 | [NIST SI Units: Length](https://www.nist.gov/pml/owm/si-units-length) · 미터·센티미터·밀리미터 |
| 이슬갓 | [Met Office Dew](https://weather.metoffice.gov.uk/learn-about/weather/types-of-weather/temperature/dew) · 표면 냉각과 응결, 이슬의 조건 |
| 모래돌이 | [NPS Great Sand Dunes Geology](https://www.nps.gov/grsa/learn/nature/geology.htm), [NPS Weathering](https://www.nps.gov/subjects/erosion/weathering.htm) · 모래 이동·쌓임과 제자리 풍화 구별 |
| 불씨게 | [호주 정부 YourHome Insulation](https://www.yourhome.gov.au/passive-design/insulation) · 단열은 열의 이동을 늦춤. 보통 담요에 적용한 설명은 이 원리의 일상 예시 |
| 웅덩이삐약·바다안개 | [USGS Water Cycle for Kids](https://water.usgs.gov/edu/watercycle-kids-int.html) · 증발·스며듦·흐름·수증기와 액체 물 구별 |
| 바다안개 | [NOAA Fog and Clouds](https://www.nesdis.noaa.gov/about/k-12-education/atmosphere/whats-the-difference-between-fog-and-clouds) · 지표 부근의 구름, 물방울과 얼음 알갱이 |
| 폭풍등 | [NWS Understanding Lightning: Thunder](https://www.weather.gov/safety/lightning-science-thunder) · 급격히 가열된 공기와 천둥, 빛과 소리의 도착 차이 |
| 등불나방 | [UNESCO Hunminjeongum Manuscript](https://www.unesco.org/en/memory-world/hunminjeongum-manuscript?hub=1081) · 1443년 문자 창제와 1446년 해례본 간행 구별 |
| 고속혜성 | [NASA What Is a Comet?](https://spaceplace.nasa.gov/comets/en/) · 얼음·먼지, 태양 근처 활동과 이온·먼지 꼬리 구별 |

자동 검사 범위는 표시용 12종의 중복 없는 수록, 장면 3개·첫 장면·고정 순서·종료·순환 없음, 비어 있지 않은 페르소나, 지식 ID와 출처의 참조, 폰 manifest의 식별 정보 일치와 본문·페르소나 미포함, 모든 36장면의 서버 조회 및 현재 장면의 허용 지식만 프롬프트에 들어가는지다. 테스트는 `server/affinity/tests/test_learning.py`에 있다. `data/characters.json`이 있는 최신 체크아웃에서는 실제 표시 레지스트리와도 비교한다. 이전 체크아웃에서도 검증할 수 있도록 위 커밋에서 확인한 12개 ID를 테스트 기대값으로 명시했다.

사람이 남은 검토는 줄거리·캐릭터 말투·10세 가독성·학습 설명의 정확성과 과도한 일반화 여부, 실제 제공자 응답 평가다. 자동 참조 검사나 공식 URL 존재만으로 이 검토를 완료했다고 하지 않는다. 이번 데이터 작업에는 Android/Unity 화면·음성·실제 차량·아이 사용성 검증과 배포가 포함되지 않는다.

## 직접 대화용 후속 적용

새 차 안 UI는 이 12편을 장면 순서대로 낭독하지 않는다. 서버가 고정된 배경 설정과 페르소나·검증 지식을 자연 대화의 근거로 사용한다. 기존 6개 부화 종은 `data/companion_learning/legacy_personas.json`의 서버 전용 대화 프로필을 사용하며, 미제공 출생지나 고유 이야기를 만들지 않는다. 앱 manifest는 이 12편과 기존 6종의 대화 참조를 합친 18개 식별 정보만 갖고, 이야기 본문·지식·페르소나는 서버에 남는다. 기존 캐릭터 이야기와 말투의 검토 전 상태는 유지한다.
