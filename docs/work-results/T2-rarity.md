# T2 — 희귀도 판정과 생물 선택 검토

- 작업일: 2026-11-04
- worktree: `/Users/seokamoto/Documents/잡동 프로젝트/현대차/_workspace/c-rarity-20261104`
- 브랜치: `codex/c-rarity-20261104`
- 시작 커밋: `1f764d1c29d4179588b8b37ac3f45f0e905852a1`
- 산출 커밋: 이 문서와 probe를 포함하는 로컬 `docs(logic): document rarity policy gaps and add probe` 커밋. 정확한 SHA는 최종 보고에 기록한다.

## 결론과 이번 변경 범위

요청된 세 불일치와 희귀종 우선·지원 신호 누락을 재현했다. 제품 코드, 카탈로그, 기존 테스트 기대값은 변경하지 않았다. 신규 산출물은 관측용 `phone/packages/allo_core/tool/rarity_policy_probe.dart`와 이 문서다. probe는 실제 엔진·테이블을 호출하며, 미지원 태그를 선택 직전에 제외하는 **비교 실험**도 출력한다. 실험이 채택된 정책을 뜻하지 않는다.

현행 `docs/schema.md:172`는 미지원 비 속성을 제외해야 한다고 설명한다. 그러나 배정서가 최신 판단 근거로 지정한 보존본 `../c-run-20261104/source-snapshot/docs/schema.md:75,86–87`는 **종 등급 대 개체 등급, 희귀종 우선과 지원 신호 제한**을 명시적으로 C/D 미결정 항목으로 남겼다. 이를 근거로 지원 필터 누락도 추천 최소 패치로만 제시한다. 지금 확정 계약만으로 안전하게 바꿀 수 있는 제품 동작은 발견하지 못했다. 기대 동작을 임의로 정한 실패 테스트를 기본 suite에 추가하지 않았다.

## 원인과 실제 호출 경로

1. `phone/lib/game/game_controller.dart:65`는 차량 `envTags`를 `seenTags` 합집합에 누적한다.
2. `:79`의 `_hatch`는 태그 합집합·원시 누적 급격 조작·돌봄·**마지막 차량 상태의 capabilities**를 `engine.judge`에 전달한다.
3. `rarity_engine.dart:19–26`은 rain→wiper, tunnel/night→light 지원 여부를 속성 판정에만 적용한다. capabilities 생략(null)은 제한 없음, 빈 목록은 해당 지원 없음이다. 지원된 태그의 속성 우선순위는 rain > tunnel/night다.
4. `:30–35`는 `max(0, harshBrake + harshSteer - careCount ~/ 3)`로 tier를 계산한다. `:49`의 `harshTotal`은 보정 전 합계다.
5. controller `:80`은 `pick(r, seenTags)`에 원래 태그를 넘긴다. `RarityResult`에는 지원 목록이나 필터된 태그가 없다.
6. `species_table.dart:25–26`은 태그 조건 2개 이상인 종을 먼저 찾으며, 이 경로는 판정 속성·등급을 검사하지 않는다. `_meets`(`:36–39`)는 태그 존재와 **원시 harshTotal**만 검사한다.
7. 희귀종이 없으면 `:28–30`에서 같은 속성·판정 tier부터 낮은 tier로 검색한다. 최후 fallback은 normal1이며, 이 최후 경로는 `_meets`를 다시 검사하지 않는다.
8. controller `:82–90`은 `speciesId=s.id`, `attribute=s.attribute`, `tier=r.tier`를 game·이벤트·도감에 반영한다. 실제 부화 화면도 종 속성+game tier, 도감도 저장된 개체 tier를 표시한다. 따라서 이 문제는 단순한 디버그 출력 차이가 아니다.

## 실행으로 재현한 결과

아래 harsh는 급제동+급조향 합계다. 별도 표기가 없으면 capabilities는 `[wiper, light]`, care=0이며, 무작위 후보 선택에는 `Random(1)`을 사용했다.

| 입력 | judge 속성/tier | 현재 pick 속성/카탈로그 tier | 지원 태그만 넘긴 비교 실험 |
| --- | --- | --- | --- |
| rain+tunnel, harsh0, light만 | dark/3 | storm_lantern water/3 | tunnel_moth dark/2 |
| rain+tunnel, harsh0, wiper만 | water/3 | storm_lantern water/3 | tide_keeper water/3 |
| rain+tunnel, harsh0, 지원 없음 | normal/3 | storm_lantern water/3 | mountain_sprite normal/3 |
| rain, harsh3, care3 | water/3 | river_glider water/2 | 동일 |
| night, harsh3 | dark/2 | lamp_moth dark/1 | 동일 |
| rain+tunnel, harsh3 | water/2 | storm_lantern water/3 | 동일 |
| rain+highway+night, harsh0 | water/3 | highway_comet dark/3 | 동일 |
| highway+night, harsh0, wiper만 | normal/3 | highway_comet dark/3 | mountain_sprite normal/3 |
| rain+tunnel+coast, harsh0 | water/3 | storm_lantern water/3 | 동일 |

- rain3+care3: 판정은 보정 harsh2라 tier3이다. tide_keeper의 `maxHarsh=2`에는 원시3을 비교하므로 탈락하고 river_glider로 내려간다.
- night3: tier2의 tunnel_moth는 tunnel을 요구한다. night만 있으면 tier1 lamp_moth로 내려간다. 돌봄과 무관한 카탈로그 조건 공백이다.
- rain+tunnel3: storm_lantern의 `maxHarsh=4`를 통과해 판정2보다 높은 카탈로그3을 선택한다. 단순히 낮은 등급 fallback만 있는 것이 아니다.
- rain+highway+night: 모든 관련 신호를 지원해도 희귀종 우선 때문에 판정 water를 dark 희귀종이 덮는다. 지원 필터만으로 속성 일치를 보장할 수 없다.
- 복수 희귀 후보: 마지막 행은 storm_lantern과 sea_mist가 모두 가능하다. 현재 구현은 후보 중 무작위 선택이며, 표의 결과는 고정 seed 한 번의 관측이다. 확률 분포나 공정성을 검증한 것이 아니다.

## C/D가 선택할 대안

| 안 | 규칙과 주요 결과 | 영향과 필요한 결정 |
| --- | --- | --- |
| **A. 지원 필터만 일관 적용 — 추천 최소안** | 기존 신호 gate를 희귀종·일반종 조건에도 적용. 원시 maxHarsh, 희귀종 우선, 종/개체 등급 차이는 유지. light만인 rain+tunnel은 tunnel_moth. 나머지 두 필수 등급 사례는 유지. | unsupported 희귀종을 막는다. fully supported 희귀종의 속성 override와 등급 차이는 남는다. C/D가 이 구분과 표시 문구를 승인해야 한다. data 수정은 필요 없다. |
| B. A + 돌봄 보정의 종 조건 반영 | 종 maxHarsh도 보정 harsh와 비교. rain3+care3은 tide_keeper. night3은 여전히 lamp_moth. | 돌봄이 카탈로그 고등급·희귀종 자격도 높인다. 안전 운전 상한을 원시값으로 둘지, 돌봄으로 넘을 수 있게 할지 결정해야 한다. rare 우선/등급 불일치는 별도로 남는다. |
| C. B + 최종 속성·등급 통일 | 희귀종도 판정 속성 및 tier와 일치하는 후보만 허용. 같은 속성의 낮은 tier fallback은 유지하되 game·이벤트·도감의 최종 tier를 선택 종 기준으로 통일. night3은 최종1, rain+tunnel3은 river_glider2. rain+highway+night은 tide_keeper3. | 종 등급=최종 개체 등급으로 확정하는 큰 변경. night에서 운전 판정2가 최종1이 되고, 돌봄·희귀종 보상의 의미가 바뀐다. controller/저장/표시 통합은 조정 담당 소유다. fallback을 금지하고 판정 tier까지 반드시 보존하려면 추가 데이터/계약 변경이 필요하다. |

이번 추천은 **A를 조정 담당의 결정 대상으로 제출**하는 것이다. A가 채택되어도 두 등급 사례를 버그가 해결됐다고 표시하면 안 된다. B와 C는 별도 결정으로 나눈다. 12종 도달성이 유지된다는 사실은 어느 안이 좋은 밸런스인지를 결정하지 않는다.

## 12종 도달성 영향

- PR #21의 기존 `test/species_table_test.dart:29–61`은 실제 judge→pick을 통과하는 12개 입력을 이미 갖고 있다. 그대로 재실행해 12종 도달을 확인했다. 신규 도달성 테스트를 복제하지 않았다.
- 그 12개 입력은 wiper/light 전체 지원, care=0이며 각 희귀종 입력의 판정도 해당 종 속성/tier와 일치한다. 따라서 **A/B/C를 위와 같이 정의하면 기존 12개 경로는 정적 검토상 모두 보존된다.** 후보 정책 자체를 제품 코드로 구현·실행한 검증은 아니다. 채택 후 동일 테스트를 다시 실행해야 한다.
- A 채택 시 미지원 신호를 이용한 경로는 의도적으로 사라진다. 현 카탈로그와 기존 gate 기준으로 light만 있으면 normal 기본3+dark 기본3+highway_comet=7종, wiper만 있으면 normal 기본3+water 기본3+sea_mist=7종, 둘 다 없으면 normal 기본3종이 남는다. 이는 조건별 정적 예상이며 전수 실행 결과는 아니다. 차종마다 12종을 보장하려면 별도 대체 획득 정책이 필요하다.
- `SpeciesTable.unreachable()`(`:42–47`)은 종의 속성/tier를 직접 가정해 `_meets`만 호출한다. 선택 우선순위나 실제 engine 결과를 거치지 않으므로 12종 선택 도달성의 증거로 사용하지 않는다. 이 메서드의 결과로 실제 engine→pick 테스트를 대체하지 않는다.

## 채택 후 적용할 구체적 API/패치 제안

### A의 최소 연결: RarityResult에 지원 태그 스냅샷 보존

소유 범위 안 두 파일만으로 현재 controller 호출까지 연결 가능한 제안이다. 이번에는 적용하지 않았다.

1. `rarity_engine.dart` 안에 기존 gate를 재사용하는 private 필터를 만든다. rain은 wiper 필요, tunnel/night는 light 필요, highway/지역/알 수 없는 태그는 그대로 둔다. null capabilities의 기존 제한 없음 의미도 유지한다.
2. `RarityResult`에 `final Set<String>? supportedTags;`와 선택 인자 `this.supportedTags`를 추가한다. 기존 수동 생성자는 null로 호환한다. `judge`는 원본 `seenTags`를 변경하지 않고 필터한 집합의 `Set<String>.unmodifiable(...)` 스냅샷을 넣으며, 같은 집합으로 attribute를 판정한다.
3. `SpeciesTable._meets`는 기존 태그 검사에 더해 `r.supportedTags != null && !s.requiredTags.every(r.supportedTags!.contains)`이면 false를 반환한다. maxHarsh·희귀종 우선·fallback·최종 출력은 그대로 둔다.
4. 이후 회귀 테스트는 실제 judge→pick 경로로 light만/wiper만/빈 capabilities 및 fully supported rare를 검증한다. null capabilities와 기존 수동 RarityResult 호환도 유지한다. 기존 12종 테스트를 재사용한다.

`pick(..., capabilities: ...)` 선택 인자만 추가하는 방식도 가능하지만 현재 controller가 이를 전달하지 않아 누락이 재발한다. 위 스냅샷 방식은 controller/models/export/Firebase 스키마 수정이 필요 없다. 반대로 모든 희귀종에 `s.attribute == r.attribute`를 바로 추가하는 패치는 지원 필터 이상의 정책 C 일부를 몰래 채택하므로 A에 포함하지 않는다.

### B/C 및 공유 파일 연결

- B: `harshTotal`의 원시 의미는 유지한다. 별도 `effectiveHarshTotal`을 result에 추가하고 `_meets`의 비교값을 합의 후 교체하는 안을 권한다. care 비율/음수 clamp는 engine의 동일 계산을 사용한다. `models.dart`의 maxHarsh 설명과 공용 문서도 조정 담당이 맞춰야 한다.
- C: 선택 함수에서 희귀 후보의 속성/tier 검사를 추가하고, controller `_hatch`가 사용하는 최종 tier를 game·hatched 이벤트·DexEntry 세 곳에 일관되게 연결한다. 최종 canonical 결과를 하나로 생성해 세 경로가 함께 사용하는 방식도 가능하다. controller/models/export/스키마의 실제 수정은 조정 담당에게 남긴다.
- 동적 capabilities 변화 시 현재 코드는 알 전체 태그 합집합과 마지막 capabilities를 조합한다. 태그 관측 시점의 지원 여부를 저장할지 현재 지원만 볼지도 추가 결정 대상이다. 이번 probe는 고정 capabilities 사례만 다룬다.

## data/species.json 변경 제안 — 이번에는 읽기만 함

- A에는 카탈로그 변경이 필요 없다. B도 `maxHarsh` 의미를 바꾸는 엔진 정책만으로 가능하나 기존 힌트와 보상 의도를 C/D가 검토해야 한다.
- night3의 판정 tier2를 유지하면서 종 tier도2로 맞추려면 dark2의 야간 획득 경로가 필요하다. 예를 들어 tunnel_moth의 조건을 night **또는** tunnel로 확장할 수 있으나, 현재 `requires.envTags`는 AND 조건이다. 배열에 night를 추가하면 OR가 아니라 둘 다 필요해져 해결되지 않는다.
- OR를 채택할 경우 구체안은 `requires.anyEnvTags: ["night", "tunnel"]`을 추가하고 `_meets`에서 적어도 하나를 확인하는 것이다. 기존 `envTags`는 계속 AND로 유지하고, 희귀종 분류를 단순 배열 길이로 판단하는 로직도 함께 검토해야 한다. 이는 모델/스키마 확장이므로 조정 담당과 C/D 승인 대상이다.
- dark2의 envTags를 빈 배열로 바꾸는 대안은 스키마 확장은 없지만 모든 dark 환경에서 출현하고 "터널을 지나면" 힌트·종 정체성과 달라진다. D와 이름/힌트를 맞춰야 한다. 새 13번째 종 추가나 임의 tier 재배치는 이번 범위에서 추천하지 않는다.

## 실행한 검증과 한계

- `bash scripts/check_c.sh core`: exit 0, 기존 코어 테스트 **28개 전부 통과**. 실제 엔진→pick 12종 테스트 포함. analyzer 오류·경고 없음; 기존 info 2건(`unnecessary_library_name`, `dangling_library_doc_comments`) 유지. pub의 lints 새 버전 알림이 있었고 의존성 선언/lock은 수정하지 않았다.
- `dart run phone/packages/allo_core/tool/rarity_policy_probe.dart`: exit 0, 위 9개 사례와 비교 실험 JSON 출력 확인. Dart가 PATH에 없으면 `/Users/seokamoto/.cache/allo-tools/flutter/bin/dart` 사용.
- `dart format --output=none --set-exit-if-changed phone/packages/allo_core/tool/rarity_policy_probe.dart`: 형식 확인.
- `git diff --check`: 공백 오류 확인.
- 읽기 전용 서브에이전트가 정책 권위·호출 경로·도달성 대안을 독립 검토했고, 메인에서 실제 probe와 suite 결과를 확인했다.
- 후보 A/B/C는 미구현이다. Flutter/차량 실기·원격 최신 PR·Firebase 송수신·출현 분포·안전 운전 밸런스는 검증하지 않았다. 외부 push/PR/팀 메시지/운영 DB 쓰기를 수행하지 않았다.

## 조정 담당에게 필요한 결정

1. 미지원 신호 태그를 희귀종의 획득 조건에서도 배제하는 A를 채택할지.
2. 카탈로그 tier와 개체 판정 tier를 별개로 둘지, 최종 공개 tier를 하나로 맞출지.
3. 돌봄이 tier뿐 아니라 maxHarsh 기반 종/희귀종 자격까지 보정할지.
4. fully supported 희귀종의 속성 override와 복수 희귀 후보의 무작위 선택을 유지할지.
5. night tier2 공백을 fallback으로 수용할지, 카탈로그/OR 조건을 변경할지.
