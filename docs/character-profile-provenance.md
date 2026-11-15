# 캐릭터 소개 표시 문구 출처

`phone/assets/data/character_profiles.json`은 상세 화면에 표시할 소개와 성격·관심사 태그만 담는다. 이야기 12종과 기존 말투 프로필 6종을 합친 18종이다. 이야기 프로필이 있는 종은 이야기의 persona를 우선한다. 이름과 ID는 `data/characters.json`, `phone/assets/data/characters.json`, `data/species.json`과 대조했다.

## 재사용 범위

- `summary`는 원본 `persona.personality`, `persona.interests`, 필요한 경우 공개 말투를 나타내는 `persona.voice`를 한 문장으로 줄였다. `traits`에는 성격과 관심사, 공개 말투를 간단한 태그로 담았다.
- 원본 전체 프롬프트, 시스템 규칙, 안전 지침, 내부 지식 제한과 응답 지시문을 앱 자산으로 복사하지 않는다.
- 원본에 없는 출신, 부화 조건, 능력, 여행 경험, 관계 또는 게임 수치를 추가하지 않는다. 바다 지킴이·길잡이·밤하늘 박사는 원본의 성격 비유이며 실제 보호·안내 능력이나 자격을 뜻하지 않는다.
- 이 파일은 표시용 정적 자산이다. 소개 표시를 위해 런타임 서버나 LLM을 호출하지 않으며, 대화용 persona 원본을 교체하거나 대화 정책을 변경하지 않는다.
- 이야기 카탈로그의 상태는 `draft-catalog-awaiting-human-review`이며 개별 이야기에도 검토 대기 표시가 있다. 기존 프로필도 `draft-existing-style-awaiting-human-review` 상태다. 이 요약은 해당 원본을 축약한 것으로 신규 설정의 승인 기록을 뜻하지 않는다.

## 이야기 프로필 12종

원본은 `data/companion_learning/story.json`의 `stories` 배열이다. 아래 speciesId와 storyId가 일치하는 항목의 `persona.personality` 및 `persona.interests`를 사용했다. `sea_mist`의 차분한 말투는 `persona.voice`에서도 확인했다.

| speciesId | storyId | 반영한 성격·관심사 |
|---|---|---|
| `road_sprout` | `road_sprout_little_garden` | 호기심, 느린 관찰, 솔직함, 작은 식물, 여행 이야기 |
| `breeze_wyrm` | `breeze_wyrm_leaf_dance` | 호기심, 가벼운 움직임, 차분한 관찰, 잎사귀, 바람 |
| `cloud_strider` | `cloud_strider_small_steps` | 느긋함, 자기 속도, 작은 차이 발견, 조용한 산책, 작은 지도 |
| `dewcap` | `dewcap_morning_drops` | 다정함, 작은 것 관찰, 단정 전 관찰, 풀잎, 이슬 |
| `dune_roller` | `dune_roller_sand_album` | 신중함, 묵묵함, 둥근 모양, 돌의 모양, 모래 언덕, 느린 관찰 |
| `ember_crab` | `ember_crab_cozy_cover` | 수줍음, 익숙해지면 다정함, 작은 목소리의 배려, 조용한 이야기, 포근한 휴식 |
| `pebble_orbit` | `pebble_orbit_ten_centimeters` | 엉뚱한 관찰자, 작은 돌 모양, 균형과 배치에 대한 호기심 |
| `puddle_pip` | `puddle_pip_puddle_postcard` | 발랄함, 작은 변화에 놀람, 물방울, 웅덩이, 물의 여행 |
| `sea_mist` | `sea_mist_quiet_map` | 조용함, 살며시 관찰, 차분한 말투, 안개, 물방울, 그림 지도 |
| `storm_lantern` | `storm_lantern_light_sound_book` | 씩씩함, 차근차근 알아보기, 밝은 격려, 빛, 소리 |
| `lamp_moth` | `lamp_moth_word_lantern` | 불빛에 신남, 새로운 글자를 반김, 모르면 책을 찾음 |
| `highway_comet` | `highway_comet_tail_model` | 신남, 빠른 움직임, 비교하며 생각을 고침, 우주 모형, 관찰 |

## 기존 프로필 6종

원본은 `data/companion_learning/legacy_personas.json`의 `profiles` 배열이다. speciesId가 일치하는 항목의 `persona.personality`, `persona.voice`, 값이 있는 경우 `persona.interests`를 사용했다. 각 원본의 `sources`는 `docs/dialogue-style.md#2`와 `data/species.json`이다. 이야기 프로필이 있는 종에는 과거 말투표의 설정을 섞지 않았다.

| speciesId | 반영한 성격·공개 말투 |
|---|---|
| `bridge_hopper` | 깡총깡총 활발함, 다리와 건너기를 좋아함, 가끔 깡총이라는 말 사용 |
| `mountain_sprite` | 차분하고 의젓한 형·누나 느낌, 짧고 담담한 말투, 천천히 가자·괜찮아 |
| `river_glider` | 느긋하게 흘러가는 성격, 가끔 스르르라는 말 사용, 느긋하게 |
| `tide_keeper` | 잔잔하고 든든한 바다 지킴이 같은 성격, 따뜻한 말투, 파도처럼·잔잔하게 |
| `tunnel_moth` | 어둠 속 길잡이처럼 든든한 성격, 친근한 말투, 어두워도 괜찮아 |
| `star_owl` | 똑똑한 밤하늘 박사 같은 성격, 별과 달 이야기, 가끔 후후라는 말 사용 |

## 검증

JSON 파싱, schemaVersion 1, 원본 18종과 ID 집합 일치, ID 중복 없음, 소개 35~60자, 태그 2~3개 및 각 태그 2~6자를 확인했다. 각 문장을 해당 원본의 성격·관심사·공개 말투와 대조했다. UI 로딩 및 표시 검증은 이 데이터 작성 범위에 포함하지 않는다.
