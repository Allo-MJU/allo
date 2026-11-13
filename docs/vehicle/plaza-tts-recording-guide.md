# Pleos 광장 TTS 제작용 대사·파일명 매칭표

작성일: 2026-11-14 · 현재 표시 캐릭터 12종 × 2개 = **WAV 24개**

## 기준과 제작 상태

- 대사 정본: [PlazaDialogue.kt](../../car/app/src/main/java/ai/allo/car/dialogue/PlazaDialogue.kt). 표시 캐릭터: [characters.json](../../data/characters.json).
- 말투 기준: [대사 가이드](../dialogue-style.md) 2·5절. 아래 목소리 안내는 제작 지시이며 읽을 대사가 아니다.
- 현재 광장 대사를 그대로 옮겼다. 기존 `allo_tts/lines.md`의 주행·부화용 대사와 구분한다.
- 아래 파일명은 **새 음성 제작·전달용 규칙**이다. 음성 생성·청취 검수·앱 파일 재생 연결은 아직 하지 않았다.
- 현재 표시하지 않는 레거시 6종(다리뛰기·산정령·강미끄럼·물결지기·터널나방·별부엉이)은 이번 제작 목록에서 제외한다.

## 파일 규칙

- 전달 폴더: `allo_tts_plaza/<species_id>/plaza_1.wav`, `plaza_2.wav`.
- 예: `allo_tts_plaza/road_sprout/plaza_1.wav`.
- 한 행 전체를 한 파일로 생성한다. 한 행에 두 문장이 있어도 파일을 나누지 않는다.
- 표의 **읽을 대사**만 읽는다. 캐릭터 이름·번호·파일명·목소리 안내를 앞뒤에 붙이지 않는다.
- 종별 두 파일은 같은 목소리를 쓴다. 표에 없는 말버릇·감탄사·단어를 추가하지 않는다.
- 광장에서 같은 친구를 누를 때 1 → 2 → 1 순서로 재생할 수 있도록 번호를 유지한다.
- 권장 전달 형식: PCM WAV, mono, 16-bit, 24 kHz. 제작 도구가 다른 샘플레이트를 쓰면 실제 값을 함께 기록한다. 이는 제작 권장값이며 현재 앱의 확정된 입력 제약은 아니다.

## 캐릭터별 제작 목록

### 1. 산들룡 (`breeze_wyrm`)

목소리 안내: 가벼운 바람을 좋아하는 호기심 많은 산책 친구. 산들산들·살랑을 가볍게 표현한다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/breeze_wyrm/plaza_1.wav` | 바람 따라 산책할래. 산들산들. |
| `allo_tts_plaza/breeze_wyrm/plaza_2.wav` | 나뭇잎 춤을 보고 싶어. 살랑. |

### 2. 구름발 (`cloud_strider`)

목소리 안내: 서두르지 않고 자기 걸음으로 걷는 느긋한 친구. 차분하고 여유 있게 말한다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/cloud_strider/plaza_1.wav` | 서두르지 않아도 좋아. 사뿐. |
| `allo_tts_plaza/cloud_strider/plaza_2.wav` | 느긋한 산책이 내 취향이야. |

### 3. 이슬갓 (`dewcap`)

목소리 안내: 작고 촉촉한 것들을 눈여겨보는 다정한 관찰자. 부드럽게 말한다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/dewcap/plaza_1.wav` | 작은 이슬을 구경하고 싶어. |
| `allo_tts_plaza/dewcap/plaza_2.wav` | 쉬는 동안 마음도 촉촉해져. |

### 4. 모래돌이 (`dune_roller`)

목소리 안내: 묵묵하고 신중하며 둥근 것을 좋아하는 친구. 차근차근 말한다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/dune_roller/plaza_1.wav` | 차근차근 걷는 게 좋아. |
| `allo_tts_plaza/dune_roller/plaza_2.wav` | 둥근 돌을 떠올렸어. 또르르. |

### 5. 불씨게 (`ember_crab`)

목소리 안내: 조금 수줍지만 다정하게 인사하는 친구. 포근하고 조심스럽게 말한다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/ember_crab/plaza_1.wav` | 살짝 인사하러 왔어. 반가워. |
| `allo_tts_plaza/ember_crab/plaza_2.wav` | 포근하게 쉬고 싶은 날이야. |

### 6. 고속혜성 (`highway_comet`)

목소리 안내: 빠른 것을 좋아하는 신나는 혜성. 활기차게 말하되 문장을 급하게 읽지 않는다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/highway_comet/plaza_1.wav` | 광장 한 바퀴, 신나게 달려! 슝! |
| `allo_tts_plaza/highway_comet/plaza_2.wav` | 쌩쌩 달리고 잠깐 쉬는 거야. |

### 7. 등불나방 (`lamp_moth`)

목소리 안내: 불빛만 보면 신나는 친구. 밝게 말하고 반짝을 신나게 표현한다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/lamp_moth/plaza_1.wav` | 작은 불빛만 봐도 신나. 반짝! |
| `allo_tts_plaza/lamp_moth/plaza_2.wav` | 환한 빛을 따라 산책하고 싶어. |

### 8. 조약별 (`pebble_orbit`)

목소리 안내: 작은 모양과 균형을 궁금해하는 엉뚱한 관찰자. 호기심을 담아 말한다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/pebble_orbit/plaza_1.wav` | 동그란 모양이 참 재미있어. |
| `allo_tts_plaza/pebble_orbit/plaza_2.wav` | 천천히 둘러보고 싶어. 빙글. |

### 9. 웅덩이삐약 (`puddle_pip`)

목소리 안내: 물웅덩이에서 첨벙 노는 아기 새. 발랄하게 말하고 삐약을 자연스럽게 살린다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/puddle_pip/plaza_1.wav` | 첨벙첨벙, 물놀이가 제일 좋아! |
| `allo_tts_plaza/puddle_pip/plaza_2.wav` | 촉촉한 풀밭에서 놀고 싶어. 삐약! |

### 10. 길싹이 (`road_sprout`)

목소리 안내: 뭐든 신기해하는 처음 만나는 친구. 밝고 호기심 있게 감탄한다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/road_sprout/plaza_1.wav` | 풀잎이 반짝인다! 정말 신기해. |
| `allo_tts_plaza/road_sprout/plaza_2.wav` | 새로운 친구를 만나고 싶어! |

### 11. 바다안개 (`sea_mist`)

목소리 안내: 몽글몽글 조용한 안개. 작고 부드러운 목소리로 말하되 알아듣기 쉽게 한다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/sea_mist/plaza_1.wav` | 살며시 다가왔어. 몽글몽글. |
| `allo_tts_plaza/sea_mist/plaza_2.wav` | 조용히 쉬는 시간이 참 좋아. |

### 12. 폭풍등 (`storm_lantern`)

목소리 안내: 씩씩한 등불. 자신감 있게 말하고 번쩍을 밝게 표현한다.

| 파일 경로 | 읽을 대사 |
| --- | --- |
| `allo_tts_plaza/storm_lantern/plaza_1.wav` | 광장에 씩씩한 등불 등장! 번쩍! |
| `allo_tts_plaza/storm_lantern/plaza_2.wav` | 내 작은 불빛으로 환하게 비출게. |

## 전달 전 확인

- [ ] 12개 캐릭터 폴더와 WAV 24개가 모두 있다.
- [ ] 각 파일의 실제 발화가 표의 대사와 일치한다. 생략·추가·다른 종 목소리가 없다.
- [ ] 문장 시작과 끝이 잘리지 않고, 잡음·과도한 무음·찢어지는 소리가 없다.
- [ ] 종별 두 파일의 목소리와 음량이 일관된다.
- [ ] 산들산들·사뿐·또르르·빙글·삐약·번쩍·몽글몽글·반짝·슝 등의 발음을 확인했다.
- [ ] 사용한 TTS 도구·목소리 ID·속도 설정·음성 형식과 검수 결과를 함께 전달한다.

※ 파일이 준비되면 이 표의 종 ID와 순번을 기준으로 앱에 연결하고, 캐릭터 전환·다시 듣기·화면 이탈 시 중지를 검증한다.
