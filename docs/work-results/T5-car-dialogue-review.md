# T5 — `car_*` 대사 기술·표현 사전 검토

검토일: 2026-11-04 (KST). **AI 사전 검토이며 C 담당자의 사람 검수가 아니다.** `reviewedBy`·`reviewedAt`을 채우지 않았고, 아래의 ‘사전 통과’도 배포 승인이나 사람 검수 완료를 뜻하지 않는다. 이슈 #19의 애착 경계 결정 전 착수 제한은 사람의 최종 검수에 남아 있다. 이번 배정은 기술 대조와 판단 자료 작성까지만 허용한다.

## 1. 범위와 고정한 소스

| 구분 | ref / SHA | 확인 내용 |
| --- | --- | --- |
| 작업 위치 | `_workspace/c-dialogue-20261104`, `codex/c-dialogue-20261104` | 기존 독립 worktree 사용. 소유 산출물은 이 파일뿐 |
| 시작점 S | `19e17b07592a80bf971b21ac22adc7aec6ac08ff` | dev + #21 회귀 테스트; 이 보고서의 제품 코드 관찰은 D/P 기준 |
| dev D | `011751328d1918c3a7695e9468cb9449a6932547` | `gh api repos/Allo-MJU/allo/commits/dev --jq .sha`로 확인 |
| PR P | [#24](https://github.com/Allo-MJU/allo/pull/24), `fix/car-gleo-accept` | OPEN, base `dev` D, 최신 조회 head `700ddb8778db84aea499edca9142f1391222f04c`, `updatedAt=2026-11-04T06:10:19Z` |
| 분담 근거 | [이슈 #19](https://github.com/Allo-MJU/allo/issues/19) | C 담당 `car_*` 24문장. 애착 경계는 미결정. 댓글 없음(조회 시점) |

연결 GitHub 도구의 PR/이슈 조회가 404를 반환해, 인증된 로컬 `gh`의 읽기 전용 조회로 확인했다. P는 로컬 Git 객체에도 있어 `git show`로 원문을 고정했다. 원격 push·댓글·리뷰·PR 작성은 하지 않았다. ‘최신’은 이 조회 시점의 head이며 이후 갱신을 포함하지 않는다.

이 문서에서 **D:L696**은 D의 `data/dialogue.json` 696행을 뜻한다. 본문에서 ref를 따로 쓰지 않은 코드 행 번호는 S 기준이다. 검토 대상 JSON, 스타일, 설계, validator, 차량 소스와 폰 controller는 D와 S가 동일하다. 코어 `models.dart`는 S에서 숫자 구분 밑줄만 정리되어 값과 줄 번호가 같다. 따라서 D 대사를 S의 실제 구현과 대조하되, P의 개선을 D에 이미 들어간 것으로 취급하지 않았다.

고정 원문: [D 대사](https://github.com/Allo-MJU/allo/blob/011751328d1918c3a7695e9468cb9449a6932547/data/dialogue.json), [P 대사](https://github.com/Allo-MJU/allo/blob/700ddb8778db84aea499edca9142f1391222f04c/data/dialogue.json).

## 2. 재집계

‘문장 수’는 이슈의 분담 단위인 **`lines` 배열 원소 수**다. 한 원소 안의 여러 발화 문장을 따로 세지 않았다. 표의 #는 해당 배열의 **1 기반** 순서다.

| 키 묶음 | D 키 | D 문장 | P 키 | P 문장 |
| --- | ---: | ---: | ---: | ---: |
| `car_egg_status` | 3 | 6 | 3 | 6 |
| `car_hatch` | 4 | 8 | 4 | 8 |
| `car_suggest` | 3 | 3 | 3 | 3 |
| `car_suggest_none` | 3 | 3 | 4 | 4 |
| `car_accept` | 2 | 3 | 4 | 5 |
| `car_unknown` | 1 | 1 | 1 | 1 |
| **C 합계** | **16** | **24** | **19** | **27** |
| 전체 뱅크(집계·기계 검사만) | 100 | 195 | 103 | 198 |

D의 C 16키와 P의 C 19키 모두 `reviewedBy: null`이다. P는 기존 24원소를 수정·삭제하지 않고 3키·3원소를 추가했다. D 판정은 사전 통과 8, 수정 제안 12, 사람 판단 필요 4다. 다른 파트 171문장은 의미·표현 검토 범위에 포함하지 않았다.

## 3. 대조 근거

| 근거 | 실제 동작 / 검토에 적용한 한계 |
| --- | --- |
| E1 — `docs/dialogue-style.md:5-18,51-64`, `docs/ai-dialogue-design.md` 2·3·5·6절 | 앱→운전자 존댓말, 슬롯 밖 숫자·장소 금지. 구체적인 차 음성 기준은 45자, `car_suggest`만 80자·4문장. 설계 초안의 25자/5초 및 공통 규칙 첫 행과 서로 다르다. 여기서는 실행 validator와 스타일 3-1절의 45/80자를 적용하고, 어느 길이 기준을 최종 채택할지는 팀에 남긴다. 애착 경계 (b)는 추천/임시값이며 확정하지 않는다 |
| E2 — `GleoFunctions.kt:26-50,107-109`, `hatch_timer.dart:31-57`, 코어 `models.dart:3-10,79-119` | `progress`는 **부화 진행률 0..1**이며 차에서 `(progress*100).toInt()`로 변환한다. 도착 진행률·남은 분이 아니다. `0.62→62`, `0→0`, `1→100`; 소수점 버림이다. `eggTier` small/mid/large와 희귀도 `tier` 1/2/3은 별개다. `tier_word`는 작은/중간/**긴**이다. ‘긴’은 코드·스타일에 같이 있는 현재 명칭이라 자동 오탈자로 확정하지 않는다. ETA 모드에서는 등급별 시간이 달라지지 않으므로 ‘긴=더 긴 부화 시간’도 단정하지 않는다 |
| E3 — `game_controller.dart:48-91`, `DialogueBank.kt:32-64` | 시작 시 speciesId/attribute/tier는 null, 부화할 때 실제 종·속성을 채운다. 이름은 종 테이블의 `nameKo`만 사용한다. `{name}`을 못 채우면 해당 문장을 건너뛰고 다음 후보/고정 문장을 쓴다. `car_hatch` 조회는 종→@속성→*이며 `not_yet`은 idle도 포함한다. `hatched` 상태는 현 controller에서 도착 시 초기화하지 않는다 |
| E4 — `rarity_engine.dart:18-35`, `species_table.dart:21-39`, `data/species.json:5-19` | 물 종의 조건에는 모두 rain이 있다. dark는 night **또는 tunnel**이다. normal tier1은 거친 운전에서도 가능하다. 종 조건은 실제 `speciesId`와 함께 봐야 하며 속성만으로 밤길·부드러운 운전 원인을 일반화하면 안 된다. rain은 게임 태그이며 현재 날씨의 별도 검증 결과가 아니다 |
| E5 — `SessionManager.kt:104-121`, `DestinationSuggester.kt:28-82,90-127`, 코어 `models.dart:107-119,175-202`, `game_controller.dart:84-91` | 차는 `unvisitedRegions=null` 고정: 방문 기록을 모르는 폴백이다. 폰은 부화 시 누적 태그의 첫 지역 하나를 로컬 도감에 저장하며 `/game`에 지역·방문·미수집·계절 정보를 보내지 않는다. 수집하지 않음≠방문하지 않음. 추천기는 종·소유 도감·계절을 조회하지 않는다. 산/도심 전용 종은 현 테이블에 없고 바다안개도 coast 외 rain 등 조건이 필요하다 |
| E6 — `GleoFunctions.kt:53-99`, `DestinationSuggester.kt:66-82,103-127` | `{region_word}`=바다/산/도심, `{place}`=고정 후보명. `{km}`는 ‘ 직선으로 약 Nkm예요.’ 전체 문장 또는 빈 문자열. N은 5km 단위 반올림, 최소 5. 위치가 있으면 120km 이내 **고정 목록**을 필터링한다. 위치가 없으면 거리 없이 지역 순서다. 후보 없음은 현실의 장소/생물 부재를 증명하지 않는다. 2분 내 대안은 캐시된 목록의 다음 후보, 소진 후 재시도는 다시 추천 가능하다 |
| E7 — D `SessionManager.kt:116-121`, `navi/NaviEtaReader.kt:86-91`, `GleoFunctions.kt:101-105` | D는 유효 제안이면 내비 초기화·요청 예외와 무관하게 destination을 반환하고 accepted 이벤트를 시도한다. 실제 안내 시작 성공을 확인하지 않는다. P는 아래 5절처럼 개선됐지만 SDK 요청 전달 성공과 실제 안내 시작 확인은 다르다 |
| E8 — `DialogueBank.kt:52-99`, `SessionManager.kt:41-43`, `car/app/build.gradle.kts:18-20` | 조사는 받침 유무와 `으로/로`의 ㄹ 예외를 처리한다. data 전체를 assets로 패키징하고, **실행 시** debug는 미검수 포함/release는 reviewedBy 있는 키만 로드한다. ‘검수된 문장만 빌드 파일에 포함’과는 다르다. 현재 release는 미검수 뱅크 문장을 쓰지 않고 코드 폴백을 쓴다. 검수 여부는 키 단위여서 한 원소만 승인하려고 같은 키의 reviewedBy를 채우면 다른 원소도 함께 활성화된다 |
| E9 — `phone/lib/screens/pairing_screen.dart:45-58`, `game_controller.dart:48-60` | `startIncubating(tier)` API는 있으나 현재 화면 호출은 fake 시작의 small 고정이다. 알 선택 화면이 제공된다고 안내할 근거는 없다. 후속 폰 PR의 화면 도입 여부는 이번 D 검토에 소급하지 않는다 |

차량 파일의 경로 접두사는 `car/app/src/main/java/ai/allo/car/`, 코어 파일의 접두사는 `phone/packages/allo_core/lib/src/`, controller는 `phone/lib/game/`다. E1의 외부 법령·논문·모델 성능 주장은 이번 작업에서 재검증하거나 결론의 근거로 사용하지 않았다.

## 4. D의 24문장별 결과

수정 후보는 **검토용 패치 제안**이다. 뱅크에 적용하지 않았고 사람 승인도 받지 않았다. ‘—’는 원문 유지 후보다. 여러 판정 사유가 겹치면 명백한 사실 오류를 먼저 ‘수정 제안’으로 표시했다.

| ID · source | key · # | 원문 | 판정 | 이유 · 수정 문장 후보 |
| --- | --- | --- | --- | --- |
| D01 · D:L696 | `car_egg_status\|*\|incubating` #1 | {tier_word} 알이 {progress}퍼센트 자랐어요. 부드럽게 가면 좋은 아이가 나와요. | **사람 판단 필요** | 진행률/슬롯은 맞다(E2). ‘좋은 아이’의 가치 평가와 주행 결과 보상 표현 허용 수준은 사람이 정해야 한다. tier는 운전 품질뿐 아니라 care/종 조건과도 관련된다. 후보: `{tier_word} 알이 {progress}퍼센트 자랐어요.` |
| D02 · D:L697 | `car_egg_status\|*\|incubating` #2 | {tier_word} 알이 {progress}퍼센트 자랐어요. 지금처럼 부드럽게 가 주세요. | **수정 제안** | 상태 분기는 ‘지금’ 운전이 부드럽다고 검사하지 않는다(E2). 운전자 행동 요청을 붙이지 않는 후보: `{tier_word} 알이 {progress}퍼센트 자랐어요.` ‘긴 알’ 명칭은 별도 사람 확인 |
| D03 · D:L704 | `car_egg_status\|*\|hatched` #1 | 이미 깨어났어요. 도착까지 같이 가고 있어요. | **사전 통과** | 현 부화 후 동행 설명에 부합(E3). ETA/도착 여부를 확인하는 문장은 아니므로 도착 직후 잔존 상태·반복 품기 통합 시 다시 검토한다. 현재 구현에서 원문 유지 후보 — |
| D04 · D:L705 | `car_egg_status\|*\|hatched` #2 | {name}{name:이/가} 깨어나서 뒷자리와 같이 가고 있어요. | **사전 통과** | 실제 종 이름과 조사로 치환한다(E3/E8). 이름 없으면 이 원소를 건너뛴다. 뒷자리 점유 센서를 확인했다는 뜻으로 확장하지 않는다. — |
| D05 · D:L712 | `car_egg_status\|*\|idle` #1 | 아직 품고 있는 알이 없어요. | **사전 통과** | 초기 idle과 맞다(E3). Gleo는 미지 stage도 idle로 취급하므로 잘못된 상태의 검증까지 보장하지 않는다. — |
| D06 · D:L713 | `car_egg_status\|*\|idle` #2 | 뒷자리 폰에서 알을 고르면 시작돼요. | **수정 제안** | 현재 선택 UI가 없다(E9). 운전자에게 폰 조작을 유도하지 않는 최소 후보: `아직 품고 있는 알이 없어요.` 선택 UI가 통합된 뒤 실제 흐름에 맞춰 재검수 |
| D07 · D:L720 | `car_hatch\|@water\|hatched` #1 | 물 속성 {name}{name:이/가} 깨어났어요! 뒷자리에 물어보세요. | **사람 판단 필요** | 이름/물 속성은 맞다(E3). 운전자에게 뒷자리와 대화하도록 권하는 후반부를 허용할지 주의 분산 관점에서 사람 판단 필요. 화면 조작 지시는 아니다. 후보: `물 속성 {name}{name:이/가} 깨어났어요.` |
| D08 · D:L721 | `car_hatch\|@water\|hatched` #2 | {name}{name:이/가} 깨어났어요. 비 오는 날이 만든 아이예요. | **사전 통과** | 현 물 종은 모두 누적 rain을 요구(E4). 현재도 비가 온다거나 정확한 날씨 센싱을 했다는 보장은 아니다. 향후 rain 불필요 물 종 추가 시 재검토. — |
| D09 · D:L728 | `car_hatch\|@dark\|hatched` #1 | 어둠 속성 {name}{name:이/가} 깨어났어요! 뒷자리에 물어보세요. | **사람 판단 필요** | 속성은 맞다. D07과 같은 대화 권유 판단. 후보: `어둠 속성 {name}{name:이/가} 깨어났어요.` |
| D10 · D:L729 | `car_hatch\|@dark\|hatched` #2 | {name}{name:이/가} 깨어났어요. 밤길이 만든 아이예요. | **수정 제안** | 낮에 tunnel만 거쳐도 터널나방 가능(E4). `night` 없는 반례가 있다. 후보: `어둠 속성 {name}{name:이/가} 깨어났어요.` |
| D11 · D:L736 | `car_hatch\|@normal\|hatched` #1 | {name}{name:이/가} 깨어났어요! 뒷자리에 물어보세요. | **사람 판단 필요** | 종/normal 분기는 맞다. D07과 같은 대화 권유 판단. 후보: `{name}{name:이/가} 깨어났어요.` |
| D12 · D:L737 | `car_hatch\|@normal\|hatched` #2 | {name}{name:이/가} 깨어났어요. 부드러운 운전 덕분이에요. | **수정 제안** | 거친 운전 tier1 길싹이도 해당 속성이고, 부화 자체는 timer 기준이다(E2/E4). 원인 단정을 삭제하는 후보: `{name}{name:이/가} 깨어났어요.` |
| D13 · D:L744 | `car_hatch\|*\|not_yet` #1 | 아직 깨어나지 않았어요. | **사전 통과** | non-hatched 응답과 맞다(E3). 알의 존재·남은 시간은 말하지 않는다. — |
| D14 · D:L745 | `car_hatch\|*\|not_yet` #2 | 조금만 더 가면 깨어나요. | **수정 제안** | 0% 또는 idle도 들어오며 임박 조건을 검사하지 않는다(E3). 후보: `지금은 부화 소식이 없어요.` |
| D15 · D:L752 | `car_suggest\|*\|first` #1 | {region_word} 쪽에서만 나오는 아이가 있어요. {place}까지 안내할까요?{km} 같은 {region_word}{region_word:이라면/라면} 다른 곳도 괜찮아요. | **수정 제안** | 각 지역 전용 종의 존재·획득 가능성을 조회하지 않는다(E5). 장소/직선거리 슬롯은 맞다(E6). 후보: `{region_word} 쪽 {place}도 있어요.{km} 안내할까요?` |
| D16 · D:L759 | `car_suggest\|*\|unvisited` #1 | {region_word} 쪽은 아직 안 가보셨네요. 거기서만 나오는 아이가 있어요. {place}까지 안내할까요?{km} | **수정 제안** | 정상 연결에서는 미방문 정보가 없어 현재 도달하지 않는 분기다. 미수집을 넘겨도 미방문은 증명되지 않으며 지역 독점 종 일반화도 틀린다(E5). 후보: `{region_word} 쪽 {place}도 있어요.{km} 안내할까요?` 미수집 문구는 계약/판정 통합 뒤 별도 검토 |
| D17 · D:L766 | `car_suggest\|*\|alt` #1 | {region_word} 쪽 {place}도 있어요.{km} 안내할까요? | **사전 통과** | 고정 목록의 대안, 선택적 직선거리, 수락 질문과 맞다(E6). 가까운 모든 장소를 탐색했다는 뜻은 아니다. — |
| D18 · D:L773 | `car_suggest_none\|*\|all_visited` #1 | 가까운 곳은 다 가보셨어요. 다음 계절에 새 아이가 나와요. | **수정 제안** | 방문 완료/계절 해금 둘 다 보장하지 않는다(E5). 현재 null 연결에서는 도달하지 않으며, future 빈 목록도 방문 증거가 아니다. 후보: `지금은 추가로 제안할 곳이 없어요.` |
| D19 · D:L780 | `car_suggest_none\|*\|none_nearby` #1 | 가까운 곳에는 새 아이가 나오는 곳이 없어요. | **수정 제안** | 120km 이내 고정 후보 부재를 신규 생물 부재로 확대한다(E5/E6). 후보: `가까운 곳에서 추천할 장소를 찾지 못했어요.` |
| D20 · D:L787 | `car_suggest_none\|*\|exhausted` #1 | 근처에서 추천할 곳은 여기까지예요. 내비에서 원하는 곳을 직접 고르셔도 돼요. | **수정 제안** | 목록 소진과 맞지만 위치 미상 땐 ‘근처’를 보장하지 않는다. 주행/정차 구분 없이 내비 직접 선택을 권한다(E6). 후보: `지금 추천할 장소는 여기까지예요.` |
| D21 · D:L794 | `car_accept\|*\|ok` #1 | {place}까지 안내를 시작할게요. | **수정 제안** | D는 내비 실패도 성공 발화 가능(E7). P도 실제 안내 시작 확인까지는 아니다(5절). 후보: `{place}까지 안내를 요청했어요.` 단, D에서 이 과거형을 사용하려면 요청 전달 실패를 구별하는 P 수준 연결이 선행되어야 한다 |
| D22 · D:L795 | `car_accept\|*\|ok` #2 | {place}{place:으로/로} 갈게요. 안내를 시작해요. | **수정 제안** | 조사 지원은 맞으나 ‘갈게요’/‘안내를 시작해요’가 실행 결과를 앞선다(E7/E8). 후보: `{place}{place:으로/로} 가는 경로를 요청했어요.` 적용 전제는 D21과 같다 |
| D23 · D:L802 | `car_accept\|*\|none` #1 | 먼저 어디로 갈지 물어봐 주세요. | **사전 통과** | 제안 없음/2분 만료에 맞는 재질문 안내(E6/E7). 운전자 대상 목적지 질문이며 아이 개인정보 역질문이 아니다. — |
| D24 · D:L809 | `car_unknown\|*\|*` #1 | 모르는 요청이에요. | **사전 통과** | 미지원 함수 응답과 맞다. 다만 현재 receiver는 허용 함수 밖 action을 먼저 버리므로 일반 외부 호출 경로에서는 이 응답까지 도달하지 않는다(`GleoReceiver.kt:18-25`). — |

명백한 독점·비밀·죄책감·개인정보 역질문·외모 평가·구매 유도는 이 24원소에서 확인하지 못했다. 이것이 미결정 애착 경계에 대한 승인이나 전체 195문장에 대한 판정은 아니다. 위 사람 판단 항목은 사람이 실제로 읽고 결정해야 한다.

## 5. P(#24 최신 head) 차이와 추가 3문장

P에서 기존 24원소의 원문은 모두 D와 같다. 스타일은 추가 상황을 열거하고 validator는 `route_active`, `not_ready`를 허용한다. `docs/ai-dialogue-design.md`는 D와 같다.

| source | key · # | P 추가 원문 | 판정 | 이유 · 수정 문장 후보 |
| --- | --- | --- | --- | --- |
| P:L794 | `car_suggest_none\|*\|route_active` #1 | 지금은 길 안내 중이에요. 안내가 끝나면 다시 물어봐 주세요. | **사전 통과** | `SessionManager.suggestDestination()`의 ETA non-null gate에 대응한다(P `sync/SessionManager.kt:104-105`). ‘안내 중’은 이 gate의 의미에 한정한다. 실제 모든 내비 안내 상태를 탐지한다고 주장하지 않는다. — |
| P:L816 | `car_accept\|*\|route_active` #1 | 지금은 길 안내 중이라 목적지를 바꾸지 않을게요. | **사전 통과** | 유효한 제안이 있고 routeActive이면 요청하지 않는 분기와 맞다(P `gleo/DestinationSuggester.kt:138-143`). 제안 없음/만료가 먼저면 `none`이 나온다. — |
| P:L823 | `car_accept\|*\|not_ready` #1 | 내비가 아직 준비되지 않았어요. 잠시 뒤에 다시 말해 주세요. | **수정 제안** | P `navi/NaviEtaReader.kt:102-107`은 초기화 전뿐 아니라 임의 SDK 요청 예외도 false로 돌려준다. ‘아직 준비되지 않음’만으로 원인을 확정하면 안 된다. 후보: `내비 안내를 요청하지 못했어요. 잠시 뒤에 다시 말해 주세요.` |

P `DestinationFlow.accept(routeActive, request)`는 Boolean 요청 실패 시 제안을 소비하지 않고 `NaviNotReady`를 돌려준다. `SessionManager.acceptDestination()`은 `Started`일 때만 accepted 이벤트를 시도한다. `GleoFunctions.respondAccept()`는 성공 시 silent callback을 돌리고 `GleoReceiver`가 같은 문장을 직접 발화하도록 변경한다(P `gleo/GleoFunctions.kt:105-118`, `gleo/GleoReceiver.kt:29-34`, `sync/SessionManager.kt:117-130`). 제안은 `asking`, 제안 불가는 `fail`로 구별한다.

이는 D의 ‘실패해도 안내 시작을 말함’을 줄인다. 그러나 `Started`는 **SDK `requestRoute()` 호출이 예외 없이 반환함**을 뜻한다. 비동기 경로 생성·안내 활성화 성공까지 확인한 것은 아니므로 기존 D21/D22의 ‘안내 시작’ 단정은 P에서도 수정 제안으로 유지한다. ETA non-null을 routeActive로 사용하는 한계와 실기기 안내/음성 수신 여부는 이번 작업에서 검증하지 않았다. `navAction` 같은 새 입력 계약을 추가한 것은 아니며, P는 `ACTION_PARAM`의 `confirm` 파싱을 개선했다.

## 6. 자동 검증 실행과 사람 검수의 차이

| 직접 실행 | 결과 | 의미 |
| --- | --- | --- |
| `bash scripts/check_c.sh dialogue` | exit 0; `키 100개 · 문장 195개 · 실패 0 · 미검수 100` | S/D 뱅크의 기존 build validator 규칙 통과. wrapper의 `git diff --check` 포함 |
| `python3 scripts/validate_dialogue.py --strict` | **exit 1**; `실패 100 · 미검수 100` | 100키 모두 reviewedBy 없음. 실패는 전부 `reviewedBy 없음`. 예상된 미검수 상태이며 전체 strict 통과가 아니다 |
| D/P 각각의 고정 Git blob에서 validator `main([])` 실행 | D exit 0, 100키·195문장·실패 0·미검수 100; P exit 0, 103키·198문장·실패 0·미검수 103 | P validator와 P JSON을 같은 ref로 검사했다. dev validator에 새 상황이 없는 문제를 섞지 않았다 |
| 같은 validator `check_key`/`check_line`을 C 항목에 적용 | D 16키·24원소 오류 0; P 19키·27원소 오류 0 | C만의 형식 검사. 사람 검수 완료가 아니며 strict 대체도 아니다 |
| JSON 원소별 D/P 비교 | 기존 C 24원소 동일, 추가 3키·3원소 | 삭제/기존 문장 변경 없음 |
| 결과표 key/#/원문 대조, `git diff --check` | 누락·중복·원문 차이 없음, whitespace 오류 없음 | 이 보고서의 24+3원소 대응 검증 |
| 표 안의 수정 후보 17개에 기존 `check_line` 적용 | 오류 0 | 후보의 형식·대표값 길이 검사이며 의미/표현의 사람 승인은 아님 |

고정 ref 실행은 아래처럼 파일을 덮어쓰지 않고 각 ref의 Python validator 자체를 실행했다. `Path.read_text`의 입력만 해당 ref의 JSON blob으로 바꾸므로 다른 worktree/공용 파일을 수정하지 않는다. 코어 소스 테스트나 차량 APK 빌드를 대신하는 실행은 아니다.

```bash
python3 - <<'PY'
import json, subprocess
from pathlib import Path
from unittest.mock import patch
root = Path.cwd()
read = Path.read_text
for ref in ('011751328d1918c3a7695e9468cb9449a6932547',
            '700ddb8778db84aea499edca9142f1391222f04c'):
    def blob(path):
        return subprocess.check_output(['git', 'show', ref + ':' + path], text=True)
    source = str(root / 'scripts/validate_dialogue.py')
    ns = {'__name__': 'review_validator', '__file__': source}
    exec(compile(blob('scripts/validate_dialogue.py'), source, 'exec'), ns)
    texts = {str(root / p): blob(p)
             for p in ('data/dialogue.json', 'data/species.json')}
    def virtual_read(self, *args, **kwargs):
        return texts[str(self)] if str(self) in texts else read(self, *args, **kwargs)
    print(ref)
    with patch.object(Path, 'read_text', virtual_read):
        assert ns['main']([]) == 0
    data = json.loads(texts[str(root / 'data/dialogue.json')])
    car = [e for e in data['entries'] if e['key'].startswith('car_')]
    ids, words = ns['load_species']()
    for e in car:
        assert not ns['check_key'](e['key'], ids)
        for line in e['lines']:
            assert not ns['check_line'](e['key'], line, set(data['placeholders']),
                                        ns['ENGLISH_PACK'] | words)
    print('C keys/lines:', len(car), sum(len(e['lines']) for e in car))
PY
```

validator가 확인하는 것은 알려진 키/상황·슬롯, 대표 예시값 길이, 한글/금칙어/일부 역질문·운전 개입 패턴 등이다. **실제 상태와 원인의 일치, 미방문과 미수집의 차이, 계절 구현, 내비 성공, 애착 표현 적정성은 확인하지 않는다.** 설계의 ‘상황별 필수 슬롯 포함’도 현재 구현은 필수 슬롯 목록을 강제하지 않는다. 따라서 실패 0이어도 4절의 의미 오류가 남는다.

조사 검토는 실제 `DialogueBank.josa/render` 소스와 기존 `DialogueBankTest.kt:14-30`의 사례를 읽어 확인했다. `물결지기+가`, `산정령+이`, `바다+라면`, `산+이라면`, `서울+로`/`북한산 국립공원+으로`의 처리가 있다. 현 템플릿의 조사 슬롯은 모두 같은 값 슬롯 바로 뒤에 있다. validator의 `render_sample`은 실제 받침 분기를 실행하지 않고 항상 조사 앞쪽 예시를 고른다. 단일 대표 이름/장소/거리로 검사하므로 실제 모든 슬롯 조합의 길이·발음까지 검증한 것은 아니다. Kotlin 단위 테스트는 이번 문서 작업에서 실행하지 않았다.

기존 규칙 검사상 24+3원소의 숫자·장소는 허용 슬롯에 있고, 문장 안에 숫자/장소를 새로 고정한 경우는 없다. `{km}`는 단순 숫자가 아니라 문장 전체라서 뒤에 ‘km’를 다시 붙이면 안 된다. 슬롯 미제공 시 문장 선택 제외와 `{km}=""`인 정상 생략은 다르다. 실제 TTS 길이/억양·운전자 주의 분산·실차 Gleo/내비 응답·전체 슬롯 조합·다른 파트 대사 의미·후속 폰 PR은 미검증이다.

## 7. 조정 담당에게 넘길 최소 변경 제안

이 절은 공용 파일 변경 요청이다. 이번 커밋에 제품 코드나 공용 문서 변경은 없다.

1. **대사 + 폴백을 함께 고치기.** 4절 후보를 A에게 전달해 `data/dialogue.json`과 `GleoFunctions`의 동일 의미 폴백을 같이 바꾸는 패치를 만든다. D `GleoFunctions.kt:32-39,73-86,102-105`에는 좋은 아이/뒷자리 질문/지역 전용 종/계절/내비 직접 선택/안내 시작 단정이 남아 있다. P도 해당 의미 폴백을 대부분 유지한다. JSON만 고치면 현재 release의 고정 발화는 바뀌지 않는다.
2. **내비 결과 문구는 실제 API 단계에 맞추기.** P의 `AcceptResult.Started`를 채택할 경우 success 발화는 ‘안내를 요청했어요’로 제한하고, `NaviNotReady` 문구는 초기화 전/SDK 요청 실패를 모두 포괄하게 한다. 실제 ‘안내를 시작했어요’가 필요하면 요청 반환과 별도로 내비의 안내 활성 상태 이벤트를 확인한 시점에 발화하도록 A가 연결한다. 새 이벤트/스키마 필드는 임의 추가하지 않는다.
3. **지역 계약 확정 전에는 중립 후보 문구 사용.** 미수집 지역 입력을 연결할 때 `unvisitedRegions`/`Suggestion.unvisited`에 그대로 넣지 않는다. 예를 들어 판단 자료가 필요하면 `CollectionContext { unknown, knownMissing(regionTags) }`와 방문 이력을 구분하고, 순수 입력인 `offer(..., collectionContext)`가 ‘미수집’ 문구를 선택하게 한다. 이는 타입/API 제안이며 최종 지역 선정·시간 기반 수집 판정·스키마 직렬화의 확정안이 아니다. unknown이면 지금처럼 중립 문구를 사용한다. 실제 방문 근거 없이 ‘안 가보셨네요’/‘다 가보셨어요’를 선택하지 않는다.
4. **표현·길이 기준은 사람 결정 후 적용.** ‘좋은 아이’, 운전자에게 뒷자리 대화 권유, ‘긴 알’ 명칭, 동행 표현의 반복 품기 전환 이후 의미를 사람이 확인한다. 애착 경계와 25/45/80자 기준 충돌은 C가 단독 확정하지 않는다. 문구 확정 후 필요한 슬롯 조합/TTS를 A와 확인하고 기존 validator를 다시 실행한다.
5. **사람 검수 기록은 최종 단계.** 후보 문구와 같은 키의 모든 원소를 C 담당자가 실제로 읽은 뒤에만 `reviewedBy: "C"`와 실제 검수일을 채운다. 검수하지 않은 다른 파트 키는 유지한다. 전체 `--strict` 미검수 0은 B/D를 포함한 전원 검수 후 별도 실행해야 한다.

## 8. 산출·미결정 경계

산출물은 `docs/work-results/T5-car-dialogue-review.md` 한 파일이다. 폰 의미와 차량 추천 경로는 읽기 전용 하위 검토 2개로 교차 확인했고, 원문·집계·validator·최신 P 차이는 메인 작업자가 직접 대조했다. 대사 원본, 검수 메타데이터, 공유 스타일/설계/스키마, 운영 DB와 원격 협업 상태는 변경하지 않았다.

사람 애착/표현 기준, 알 명칭·길이 기준, 지역 수집/방문 계약과 최종 지역 선정, 반복 품기 통합 뒤 문구, 실제 내비 안내 시작 및 TTS 실차 확인은 남아 있다. 이 보고서는 이슈 #19를 완료 처리하거나 사람 검수 착수/완료를 대신하지 않는다. 최종 로컬 커밋 SHA는 완료 메시지로 전달한다.
