# 알로(ALLO) 차량·폰 데이터 계약

> **2026-11-04 C 구현 기준, 2026-11-11 인증 계약 반영.** 이 문서 하나를 기준으로 A(차량), B(폰), C(로직)가 구현한다. C가 기준을 관리하고, 실제 연동에서 문제가 확인되면 이 문서를 수정해 공유한다. 과거 검토안보다 본문이 우선한다. 구현 기준 확정과 각 앱의 반영·실기 검증 완료는 구분한다.

## 1. 책임과 공통 원칙

| 영역 | 쓰는 쪽 | 읽는 쪽 | 책임 |
| --- | --- | --- | --- |
| `/meta` | 인증된 callable 서버 | 세션에 연결된 차량·폰 | 세션과 페어링 정보 |
| `/acl`, `/pairing` | 서버만 | 서버만 | 소유 UID·가입 코드 만료/시도 제한 |
| `/vehicle` | 차량 | 폰, 차량 자체 표시 | 신호 수집, 단위 변환, 누적 거리·급격 조작·환경 태그 계산 |
| `/game` | 폰 | 차량 | 품기·부화·생물 선택·지역 수집 요약 |
| `/events` | 이벤트별 지정 발신자 | 해당 소비자 | 개별 알림·세션 종료 |

- 통신은 Firebase Realtime Database를 사용한다. 차량은 REST/SSE, 폰은 FlutterFire를 사용한다.
- 차량은 게임 등급·생물을 판정하지 않는다. 폰의 `allo_core`가 판정하고 차량은 결과를 표시·발화한다.
- 시각 `createdAt`·`ts`는 epoch **밀리초**, `etaSec`·`hatchAtSec`는 **초**, `distanceM`·`hatchAtM`은 **미터**, `speedKph`는 **km/h**다.
- 전송 필드명은 본문의 이름만 쓴다. `etaSeconds`, `harshBrakeCount`, `seatRow2Occupied` 같은 별칭을 전송하지 않는다.
- Firebase에서 null이나 빈 배열/객체의 키가 없어질 수 있다. 아래에서 허용한 누락값은 null/빈 값으로 읽는다. 타입 오류를 유효한 값으로 추측해서 바꾸지 않는다.
- 좌표·아이 개인정보·주행 경로·도감 원문은 Firebase에 보내지 않는다. 도감과 이어하기 checkpoint는 폰 로컬에 저장한다. 2026-11-15 사용자 요청으로 아래 ‘친구 부탁과 방문 이력’의 목적지 ID·이름·지역·실제 도착 시각은 별도 소유자 이력에 영속 저장한다. 기존 세션 이벤트에 주소/좌표를 추가하는 허용은 아니다.

## 2. 코드 위치

| 경로 | 소유·역할 |
| --- | --- |
| `car/app/src/main/java/ai/allo/car/model/Models.kt` | A — 차량 전송/수신 모델 |
| `car/.../vehicle/`, `car/.../navi/` | A — 신호 정규화·환경/지역 태그·내비 |
| `car/.../sync/`, `car/.../gleo/` | A — 세션·발행·SSE·목적지 제안·음성 |
| `phone/lib/feed/` | B — 페어링·차량 신호/이벤트 수신·game 발행 |
| `phone/lib/game/`, `phone/lib/storage/` | B/C — 게임 상태·로컬 도감·이어하기 |
| `phone/packages/allo_core/` | C — 순수 Dart 판정·시간/지역 계산·공용 모델 |
| `data/species.json`, `data/dialogue.json` | 종 데이터, 차량·폰 대사 뱅크 원본 |
| `phone/assets/data/species.json` | 폰 패키징용 종 데이터. 원본과 일치해야 함 |
| `firebase/database.rules.json` | 실제 적용할 DB 규칙의 저장소 원본 |
| `art/`, `phone/assets/{species,egg,ui}/` | D 원본·앱 에셋 |

`car/.../`는 `car/app/src/main/java/ai/allo/car/` 아래를 뜻한다. 대사 검수는 `docs/dialogue-style.md`를 따른다. 스키마 결정이나 자동 검사 통과만으로 `reviewedBy`를 채우지 않는다.

## 3. Firebase Realtime Database

### 3.1 구조와 세션 수명

```text
/sessions/{sessionId}/acl        # server-only carUid / phoneUid
/sessions/{sessionId}/pairing    # server-only expiry / failed attempts
/sessions/{sessionId}/meta
/sessions/{sessionId}/vehicle
/sessions/{sessionId}/game
/sessions/{sessionId}/events/{pushId}
/travelHistory/{phoneUid}/visits/{visitId}  # 인증된 차량 callable만 기록
/travelHistory/{phoneUid}/places/{placeId} # 같은 transaction의 장소 요약
/travelHistory/{phoneUid}/companions/{creatureId}/places/{placeId} # 실제 동행 개체별 최신 도착
```

- `sessionId`는 차량이 생성한 UUID다. 차량이 인증된 `createVehicleSession` callable로 서버의 meta/ACL 생성을 완료한 뒤 해당 세션 데이터를 발행한다.
- 최종 종료된 세션을 다음 주행에 재사용하지 않는다. 차량은 새 세션·페어링 코드를 만들고 폰은 새 QR 또는 세션 ID+코드로 연결한다.
- 기어 P나 통신 끊김만으로 폰이 최종 종료를 추측하지 않는다. 최종 종료는 `sessionEnd` 계약을 따른다.
- 차량의 현재 종료 판정 기준은 페어링 완료된 세션에서 누적 100m 이상 주행 후 기어 P이며, 도착 이벤트가 있으면 즉시, 그렇지 않으면 안내 없음 상태에서 P 3분·안내 있음 상태에서 P 30분 유지다. 이 판정은 `SessionEndDetector`가 소유한다. 안내 상태 감지의 실측 정확도와 이벤트 전달 보장은 별개다.

### 3.2 `meta` — 서버 생성, 서버에서 폰 가입 확정

```json
{
  "createdAt": 1793620000000,
  "pairCode": "483920",
  "paired": false,
  "carAppVersion": "1.0.0"
}
```

| 필드 | 타입 | 의미 |
| --- | --- | --- |
| `createdAt` | number | 서버가 확정한 세션 생성 시각(epoch ms). 클라이언트 수정 불가 |
| `pairCode` | string | 숫자 6자리. 앞자리 0을 보존 |
| `paired` | boolean | 기본 false. 폰의 연결 기록 성공 시 true |
| `carAppVersion` | string | 차량 앱 버전 |

QR은 `allo://pair?sid={UUID}&code={6자리}`다. 수동 연결도 세션 ID와 코드가 필요하며, 코드만으로 세션을 검색하는 경로는 이번 계약에 없다. 폰은 익명 인증 후 `joinVehicleSession` callable에서 코드·만료·단일 폰 소유권·종료 여부 검증을 통과해야 읽기/쓰기를 시작한다. 서버가 `paired=true`와 `paired` 이벤트 및 phoneUid를 함께 기록한다. 저장한 연결 정보도 동일 인증 UID로 서버에서 재검증한다. 신규 연결 코드 유효 기간은 10분, 실패 제한은 5회, 세션 공유 데이터 접근은 생성 후 24시간이다. 세부 권한과 검증은 [Firebase 인증 계약](../firebase/AUTH_SESSION.md)을 따른다.

### 3.3 `vehicle` — 차량의 현재 스냅샷

차량은 쓰기가 끝난 뒤 약 1초 간격으로 다음 스냅샷을 발행한다. 정확한 1Hz나 모든 중간 신호의 전달을 보장하는 기록 스트림은 아니다. 값이 같아도 `ts`를 갱신한다.

```json
{
  "ts": 1793620012000,
  "gear": "D",
  "speedKph": 82.4,
  "distanceM": 14300,
  "harshBrake": 2,
  "harshSteer": 1,
  "wiperLevel": 2,
  "headlightOn": false,
  "seatRow2": true,
  "etaSec": 2280,
  "envTags": ["rain", "highway"],
  "turns": [{ "type": "right", "inM": 230 }, { "type": "uturn", "inM": 910 }],
  "headingDeg": 87.5,
  "capabilities": ["wiper", "light", "seat", "odometer", "speed", "gear", "eta", "turns"]
}
```

| 필드 | 타입 | 의미 |
| --- | --- | --- |
| `ts` | number | 스냅샷 생성 시각(epoch ms). GPS 관측 시각이 아님 |
| `gear` | string | `P`, `D`, `R`, `N` |
| `speedKph` | number | AAOS 속도를 km/h로 변환한 값 |
| `distanceM` | number | 차량 세션 누적 거리(m). 알마다 0으로 만들지 않음 |
| `harshBrake`, `harshSteer` | number | 차량 세션 누적 횟수. 알별 평가는 폰이 기준점을 분리 |
| `wiperLevel` | number | 정규화한 0/1/2/3. 0은 꺼짐 |
| `headlightOn` | boolean | 하향등 켜짐 |
| `seatRow2` | boolean | SDK 극성 보정 후 2열 점유 |
| `etaSec` | number 또는 null/누락 | 사용할 수 있는 양수 ETA(초). 안내/ETA가 없으면 null |
| `envTags` | string[] | 관측 환경 태그. 누락은 빈 목록 |
| `headingDeg` | number 또는 null/누락 | 차의 진행 방향(도, 0~360, 북쪽 0·시계 방향). 내비 현재 위치 콜백의 heading. 모르면 null |
| `turns` | object[] 또는 누락 | 내비 경로 안내의 다음 회전들. 가까운 순 최대 3개. 안내 중이 아니거나 없으면 빈 목록 또는 누락 |
| `cornering` | object 또는 누락 | 조향 센서에서 만든 창밖 회전 표시 전용 v1 값. `{version:1,bend,receivedAtMs}`. 사용할 수 없으면 생략 |
| `capabilities` | string[] | 실제 지원하는 신호 목록 |

지원 이름은 `wiper`, `light`, `seat`, `odometer`, `brake`, `steering`, `speed`, `gear`, `eta`, `turns`다. 차량 앱 내부의 `steerDeg`, `brakePressed`, `odometerM`를 별도 전송 필드로 추가하지 않는다.

2026-11-15 사용자 요청의 조향 연동은 원본 조향각 대신 `cornering` 표시 요약을 사용한다. `bend`는 유한한 -1~1 값이며 음수는 왼쪽, 양수는 오른쪽, 0은 직진이다. 물리 도로 곡률·핸들 각도나 게임 판정값이 아니다. `receivedAtMs`는 SDK가 값을 전달한 epoch ms이며 새 하드웨어 관측 시각을 보장하지 않는다. 차량은 조향 지원, D 기어, 2km/h 초과의 유효한 최신 속도, SDK 수신 2500ms 이내 조건에서만 전송한다. 오류·비정상 각도·오래된 값이면 필드를 생략한다. 기존 `harshSteer` 산출은 유지한다.

폰은 알 수 없는 버전·잘못된 값은 무시하고 Unity의 선택적 `route.cornering`으로 전달한다. Unity는 같은 수신 시각을 반복한 메시지로 유효 시간을 연장하지 않는다. 실제 조향 신호를 사용할 수 있는 동안 내비 예정 회전과 이중으로 회전하지 않으며, 이미 진입한 회전 구간은 보존한다. 신호가 없거나 만료되면 기존 내비 경로 표현을 사용한다. 위도·경도는 추가하지 않는다. 이번 요청에서 도시·산·해안·고속도로 분류는 아래의 기존 근사 방식을 유지하기로 했다.

현재 파생 기준을 유지한다. 급제동은 속도 감소율 12km/h/s 이상, 급조향은 속도 15km/h 이상에서 조향각 변화율 90도/s 이상이며 각각 2초 쿨다운을 둔다. 거리는 Odometer의 양수 증가분을 사용하고, 없거나 정체/감소하면 이전 속도를 적분한다. SDK 거리 km→m 변환은 차량 안에서 한다.

| 태그 | 현재 차량 산출 기준 |
| --- | --- |
| `rain` | `wiperLevel > 0` |
| `night` | Asia/Seoul 19:00 이상~06:00 미만 |
| `tunnel` | `headlightOn && !night` |
| `highway` | 속도 80km/h 초과가 60초 이상 지속. 80 이하에서 지속시간 초기화 |
| `coast`, `mountain`, `city` | 차량의 기준점·반경 lookup. 겹치면 coast→mountain→city 순, 미분류면 지역 태그 없음 |

위 태그는 센서 기반 추정이다. 실제 비·터널·고속도로·일몰을 확인한 사실로 확대하지 않는다. 현재 GPS는 최근 SDK 좌표 캐시를 사용하며 **새로운 GPS 30초 TTL은 채택하지 않는다.** SDK 관측 시각/정차 중 갱신 주기는 A의 실측 대상으로 남기되, 이 때문에 나머지 wire 계약을 보류하지 않는다.

`turns` 원소는 `{type, inM}`이다. 차 창밖(Unity)이 경로대로 교차로·회전·유턴을 그리는 데만 쓰며 게임 판정에 쓰지 않는다.

- 출처는 Pleos NaviHelper `onTBTInfo(List<TBTInfo>)`다. 차량 앱이 받은 목록을 정규화해 다음 스냅샷에 싣는다.
- `inM`은 그 회전까지 남은 거리(m, 0 이상 정수)다. `TBTInfo.distance`를 반올림한다.
- `type`은 아래 다섯 가지로 정규화한다. 그 밖의 안내(직진, 터널, 톨게이트, 휴게소, 고가·지하차도, 합류, 경유지, 알 수 없음)는 싣지 않는다.

| `type` | `TurnType` 원본 |
| --- | --- |
| `left` | `TURN_LEFT`, `TURN_SHARP_L` |
| `right` | `TURN_RIGHT`, `TURN_SHARP_R` |
| `uturn` | `TURN_UTURN` |
| `keepLeft` | `TURN_KEEP_L`, `TURN_ENTER_IC_L`, `TURN_EXIT_IC_L` |
| `keepRight` | `TURN_KEEP_R`, `TURN_ENTER_IC_R`, `TURN_EXIT_IC_R` |

`headingDeg`는 Pleos NaviHelper `CurrentLocationInfo.heading`이다. 창밖 도로를 차가 실제로 꺾는 만큼 휘게 하는 데만 쓰고 판정에 쓰지 않는다. 같은 콜백의 위도·경도·주소는 보내지 않는다(절대 규칙 2). heading 이 NaN·무한대이거나 위치 정보를 아직 받지 못했으면 null 이다.

`TBTInfo.description`(도로명·교차로명)과 좌표는 위치를 드러내므로 보내지 않는다. 내비가 경로 안내 중이 아니면(`Guidance` 가 GUIDING 이 아니면) 빈 목록을 보낸다. `turns` 수신 여부는 기기에서 확인할 항목이다(에뮬레이터 내비가 `onTBTInfo`를 보내는지 미확인).

Debug 지역 override는 좌표 미수신·lookup을 우회하는 시연 기능이다. debug 빌드에서 활성화한 지역 태그도 정상 `envTags`로 전송되고 폰 로컬 도감에 저장된다. 그 기록을 실측 위치 증거로 사용하지 않는다.

### 3.4 `game` — 폰의 전체 상태

**폰은 `/game` 전체를 `set()`으로 교체한다.** `/game/uncollectedRegions/0` 같은 원소별 쓰기와 깊은 경로 patch는 사용하지 않는다. 차량에 깊은 patch merge 구현을 필수로 요구하지 않는다.

```json
{
  "ts": 1793620012500,
  "eggTier": "mid",
  "stage": "incubating",
  "progress": 0.62,
  "speciesId": null,
  "attribute": null,
  "tier": null,
  "careCount": 3,
  "lookOutCount": 1,
  "hatchAtM": 25000,
  "hatchAtSec": null,
  "regionCollectionKnown": true,
  "uncollectedRegions": ["coast", "mountain"]
}
```

| 필드 | 타입 | 의미 |
| --- | --- | --- |
| `ts` | number | 폰 상태 작성 시각(epoch ms) |
| `eggTier` | string | `small`, `mid`, `large` |
| `stage` | string | `idle`, `incubating`, `hatched`. 동행은 hatched이며 별도 DB stage 없음 |
| `progress` | number | 0~1 |
| `speciesId` | string 또는 null/누락 | 부화한 종 ID |
| `attribute` | string 또는 null/누락 | `water`, `dark`, `normal` |
| `tier` | number 또는 null/누락 | 개체 판정 등급 1/2/3 |
| `careCount`, `lookOutCount` | number | 해당 알의 돌봄·창밖 보기 횟수 |
| `hatchAtM` | number 또는 null/누락 | 거리 모드의 해당 알 목표(m) |
| `hatchAtSec` | number 또는 null/누락 | 시간 모드의 해당 알 품기 목표(초). 세션 절대 시각이 아님 |
| `regionCollectionKnown` | boolean | 폰 도감 요약을 사용할 수 있는지. 기본 false |
| `uncollectedRegions` | string[] | 도감에 수집 기록이 없는 `coast`, `mountain`, `city` |

두 hatch 기준은 최대 하나만 유효하다. idle/지급 보류에서는 둘 다 null일 수 있다. 새 알은 이전 종·등급·돌봄·판정 구간을 초기화하지만 기존 도감과 연결 정보는 보존한다.

#### 지역 추천 요약

추천 기준은 **현재 폰 도감의 수집 기록**이다. 실제 방문 이력이 아니다.

| 수신 상태 | 차량의 해석 |
| --- | --- |
| known 누락 또는 false | 미확인 → 기본 추천. 목록이 있어도 사용하지 않음 |
| true + 유효한 비어 있지 않은 목록 | 그 미수집 지역에서 추천. 중복 지역은 한 번만 취급 |
| true + 빈 배열, 목록 키 없음 또는 null | 확인 결과 미수집 지역 없음 → 후보 없음. 기본 추천으로 되돌리지 않음 |
| known 타입 오류, true + 잘못된 목록 타입/원소/알 수 없는 지역 | 미확인 → 기본 추천. 오류 원소를 지워 빈 목록으로 만들지 않음 |

`["none"]`, `["unknown"]`은 쓰지 않는다. RTDB가 빈 배열 키를 지워도 true를 함께 보내면 후보 없음과 모름을 구분할 수 있다. `/game` root null·세션 교체·손상 snapshot에서는 이전 지역 요약을 버린다. 차량은 두 필드를 raw JSON에서 위 표대로 정규화할 수 있으며, 구버전 폰의 누락 필드는 unknown으로 처리한다.

**과거 기록 처리:** 정상적인 과거 `regionTag`가 coast/mountain/city이면 수집 기록으로 인정한다. 첫 태그 방식으로 만든 기록도 버리지 않으며 새 시간 집계 결과로 소급 설명하지 않는다. null/누락은 어느 지역에도 더하지 않는다. 전체 도감의 읽기·형식 확인 성공 후 known=true로 만들고, 정상 빈 도감은 세 지역 모두 미수집이다. 손상 기록·알 수 없는 지역 값·읽기/저장 실패는 known=false다.

폰은 도감 저장 성공 후 요약을 갱신하고, idle·품기·부화·상호작용·새 알·복구를 포함한 모든 전체 set에 요약을 유지한다. 늦은 이전 연결의 발행이 새 연결에 섞이지 않도록 한다.

**차량 추천:** 현재 지역 제외·근거리 후보 정렬은 현행 추천기를 유지한다. 다음 상태를 구분한다: 모든 지역 수집 완료 / 미수집 지역은 있지만 현재 지역 제외 등으로 후보 없음 / 주변 목록에 후보 없음 / 대안 소진. 모두를 “모두 방문했다”로 표현하지 않는다. 세션이나 수집 요약이 바뀌면 제안 캐시를 비우고 수락 직전에 후보 유효성을 확인한다. 지역 추천만으로 특정 생물 획득을 보장하지 않는다. 현 카탈로그에서 지역 조건이 있는 종은 `sea_mist`이며 coast 외 조건도 필요하다.

#### 알별 지역 시간

- 알 지급부터 부화까지 폰의 단조 증가 시계로 관측 시간을 누적한다. 동행·앱 중단 시간은 제외한다.
- 가장 최근 지역은 최대 **5초**만 인정한다. 20초간 새 신호가 없으면 최대 5초는 이전 지역, 15초는 미확인이다. 정상 신호가 계속 오면 계속 누적된다.
- 지역 없음·복수 지역 충돌은 미확인이다. 중복/역순 신호는 같은 시간을 더하거나 태그 유효기간을 연장하지 않는다.
- 최장 지역 W가 유일하고 그 시간이 두 번째 지역 S와 미확인 U의 합보다 클 때(**W > S + U**)만 그 지역을 기록한다. 동률·부족한 근거는 `regionTag=null`이다.
- 새 알은 새 집계를 시작한다. 중단 복구는 합계를 유지하되 오래된 열린 태그를 복구하지 않는다. 수신 공백 5초는 GPS 관측 정보 자체의 신선도를 보증하지 않는다.

#### 부화·이어하기 — 2026-11-14 사용자 변경

- 차량 페어링 성공 시 폰이 여행당 알 하나를 자동 준비한다. 기본 크기는 small이며 차 안에서 크기나 새 알을 선택하지 않는다. 여행 identity는 실제 sessionId이고 데모 여행에도 별도 영속 identity를 쓴다.
- 이전 여행의 진행 중인 미부화 알은 같은 eggId·진도·호감도·사진 완료 상태로 이어 키운다. 이어 키운 여행도 그 알 하나로 진행하며 추가 알을 지급하지 않는다.
- 동일 여행 재연결·QR 코드 재발급·앱 재시작·tier 변경 요청으로 재지급하지 않는다. 부화·실패·버리기 후에도 같은 여행의 지급 기회는 복원되지 않는다.
- 반복 지급·부화 후 30분 재지급은 제거한다. 80분 초과의 ‘40분 품기’는 부화 계산 상한으로만 유지한다.
- 각 알은 지급 시 사용할 수 있는 ETA로 계획을 고정한다. 도중 ETA 변경·소실이나 다음 여행 이어하기로 현재 알을 되감지 않는다.
- ETA 2분 이상~80분 이하: 절반을 분 단위로 내려 부화 시간을 계산한다. 11분이면 5분, 80분이면 40분이다.
- ETA 80분 초과: 부화 계획은 40분. 그 뒤 새 알을 자동 지급하지 않는다.
- ETA 없음: 기존 거리 모드. 목표는 small 5km, mid 25km, large 75km다. ETA가 나중에 나타나도 해당 알의 모드는 유지한다.
- ETA 2분 미만 등 계획 보류 조건은 기존 부화 계산 규칙을 따른다. 계획 보류를 새 알 지급 권리로 취급하지 않으며 같은 여행의 지급/이어하기 identity를 보존한다.
- 앱 중단 중 경과 시간·추가 거리·급격 조작은 진행에 합산하지 않는다. 인정된 시간·거리·지역·돌봄·판정 횟수는 로컬 checkpoint로 복구한다.
- 여행별 지급/승계 기록은 tier별 checkpoint와 분리해 기존 namespace/profile 안에 저장한다. 앱 저장소 범위에서 중복을 막으며, 이 변경이 새 서버 보관 필드나 기기 간 지급 보장을 추가하지는 않는다.
- 부화 저장 실패는 같은 결과를 먼저 재시도한다. 새 여행의 알로 덮어쓰지 않는다. 이전 세션의 지연 API/신호/저장 결과를 새 알에 적용하지 않는다.
- 기존 도감·거리 중복 방지·진행 중 알을 지우지 않는다. 종료된 여행의 지급 기록과 미부화 알 이어하기를 구분한다.
- 구체적인 화면·상태 전환은 [여행당 한 알과 캐릭터 탭 대화](superpowers/specs/2026-11-14-trip-egg-character-invitation-design.md)를 따른다. wire 필드명과 전체 game writer는 유지한다.

### 3.5 `events` — 개별 알림

```json
{
  "ts": 1793620030000,
  "type": "hatched",
  "by": "phone",
  "payload": {"speciesId": "tide_keeper", "tier": 3}
}
```

`ts`는 epoch ms, `type`은 아래 이름, `by`는 car/phone이다. `payload`는 **키별 타입을 가진 JSON 객체**이며 빈 객체가 생략되면 `{}`로 읽는다. 전부 문자열인 map으로 가정하지 않는다.

| type | by | payload | 의미·소비 |
| --- | --- | --- | --- |
| `paired` | phone (서버가 기록) | 생략 또는 `{}` | 연결 기록. 현재 차 화면은 meta.paired로 연결 표시 |
| `hatched` | phone | speciesId:string, tier:number | 부화 발생. 현재 차량 발화는 game.stage 변화로 동작 |
| `lookOutPrompt` | phone | `{}` | 창밖 보기 기록 |
| `gleoSpeak` | phone | 이번 계약에서 payload/수신 기능 미사용 | 이름만 예약. 자유 텍스트 발화 기능을 추가하지 않음 |
| `destinationSuggest` | car | region:string, status:string | 아래 제안·수락 계약 |
| `sessionEnd` | car | `{}` | 해당 차량 세션의 최종 종료 |

현재 Kotlin `GameEvent`의 문자열 payload map은 차량의 기존 송신 이벤트에만 맞는다. 폰의 숫자 tier 이벤트를 새로 소비할 때는 JSON 타입을 유지하는 모델을 사용해야 한다. 현재 폰은 차량 이벤트 중 sessionEnd만 처리하며, destinationSuggest를 폰 화면에 표시하는 기능까지 구현됐다는 뜻은 아니다.

#### `destinationSuggest`

```json
{"region":"coast","status":"offered"}
```

```json
{"region":"coast","status":"accepted"}
```

- region은 coast/mountain/city다. 좌표·목적지 이름은 이벤트에 넣지 않는다.
- offered는 차량이 목적지를 제안했다는 뜻이다.
- **accepted는 운전자의 수락 후 SDK 목적지 요청을 예외 없이 전달한 성공**이다. 실제 경로 안내 시작까지 확인한 이벤트로 해석하지 않는다.
- SDK 미준비·요청 실패·안내 중 또는 안내 상태 미확인일 때 accepted를 보내지 않는다. 실제 안내 시작 확인이 필요해지면 별도 확인 신호를 먼저 정의하고 이 의미를 바꾼다.

#### `sessionEnd`

- 차량은 마지막 vehicle 쓰기를 시도한 뒤 종료 이벤트를 보낸다. 재시도/재연결로 중복될 수 있으며 프로세스 종료·네트워크 실패에서 무손실 전달을 보장하지 않는다. 최종 쓰기가 실패했다면 폰은 서버에 저장된 마지막 값까지만 읽을 수 있다.
- 폰은 이벤트 수신 즉시 새 품기·상호작용을 막고 저장한다. 품기 중 필요한 마지막 vehicle을 다시 읽어 늦은 콜백을 보완한다. 이미 부화한 상태까지 항상 재조회하는 계약은 아니다.
- 이벤트의 timestamp가 연결 시각보다 오래됐다는 이유로 종료를 무시하지 않는다. 종료된 세션 재연결은 거부한다. 같은 pushId/같은 세션 종료의 중복 처리로 저장·화면 이동을 반복하지 않는다.
- 읽기·도감/진행 저장·페어링 정보 삭제가 실패하면 완료로 표시하지 않고 재시도를 제공한다. 저장 완료 전에 새 연결로 넘어가지 않는다.
- 폰의 체크포인트용 `endSession()` 호출 자체는 차량의 최종 종료를 뜻하지 않는다. 앱 중단/화면 이탈 저장과 차량 종료를 구분한다.

### 3.6 저장 범위

Firebase에는 세션 연결용 meta, 현재 vehicle/game, 이벤트만 보낸다. 좌표·아이 이름/생년월일/연락처·주행 경로·도감 원문·지역 시간 합·이어하기 checkpoint를 보내지 않는다. 지역 요약 두 필드만 차량과 공유한다.

### 3.7 접근 만료와 데이터 정리

DB 규칙의 원본은 [`firebase/database.rules.json`](../firebase/database.rules.json)이다. 이 문서에 별도 규칙 사본을 두지 않는다. 정상적인 생성 시각 기준 24시간 조건은 **접근 제한**이며 자동 삭제가 아니다.

매일 정리 준비는 #37을 따른다. 유효한 createdAt이 24시간 이상 지난 세션만 조건부 삭제 후보로 하고, meta 없는 고아·잘못된/미래 시각은 보존해 검토한다. READY와 삭제 opt-in을 명시적으로 설정하기 전에는 운영 정리를 활성화하지 않는다. 일일 실행은 정확히 생성 후 24시간에 삭제를 보장하지 않는다. 이 계약 확정은 IAM·Secrets·활성화·실제 삭제 승인이 아니다.

## 4. 생물 데이터와 판정

`data/species.json`의 종 ID, 속성, 카탈로그 tier, requires.envTags(AND 조건), maxHarsh, hint, sprite를 원본으로 사용한다. 폰 패키징 복사본과 일치시킨다. 기본 9종(속성3×등급3)+복합 조건 희귀3종을 유지한다.

지원 정보는 속성 판정과 생물 선택 양쪽에 같은 기준으로 적용한다: rain은 wiper, tunnel/night는 light가 필요하다. 빈 capabilities는 해당 지원 없음이며 기존 코어 직접 호출에서 지원 인자 생략(null)은 호환을 위해 제한 없음으로 둔다. 현재 카탈로그의 희귀종 우선, 종 tier와 개체 판정 tier의 차이, 돌봄 보정과 원시 maxHarsh 조건은 유지한다. 다른 밸런스 변경은 이 계약에 포함하지 않는다.

## 5. 적용과 확인

- **A:** 지역 요약 네 상태 정규화, root null/손상 값 초기화, 수집 기준 문구·키 명칭, 후보 없음 사유 구분, 요약/세션 변경 시 캐시 초기화와 수락 전 확인을 이 기준으로 맞춘다. 최종 vehicle 쓰기→sessionEnd 순서와 재시도(#27)는 후속 수정 반영 후 중복·실패 경로를 확인한다. GPS 갱신 실측 결과가 나오면 C에게 알려 본문을 수정한다.
- **B/C:** #36에서 전체 game set·지역 요약·여행당 한 알·로컬 복구를 이 기준으로 구현한다. 스키마 문서와 모순되는 별도 규칙을 만들지 않는다.
- **통합 확인:** 정상/미확인/빈 후보/손상 요약, 새 알 전후 필드 유지, 여행별 지급 경계·저장 실패·중단 복구, 최종 종료·새 세션, 실제 차량/Firebase 왕복을 확인한다. 로컬 테스트 통과를 실기 검증으로 표시하지 않는다.

현재 기준의 측정 한계는 GPS 캐시 신선도, 종료 이벤트 배달, 실제 내비 안내 시작 확인이다. 미측정 값을 임의의 TTL이나 성공 보장으로 바꾸지 않고 현재 의미로 구현한다. 문제가 확인되면 C가 이 문서를 갱신하고 A/B가 따라 수정한다.

## 거점 로컬 계약 2026-11-12

[거점 구현 기준](base-camp.md)은 종별 역할, 시설별 병렬 작업, 실제 시간 기반 오프라인 진행, 주행·활동 재료, 음식/도감/속도 보너스, 훈련 행동을 정의한다. C의 BaseCampController가 기존 도감에서 영속 개체 참조를 만들고 별도 `baseCamp.v1.<profile>` JSON에 거점과 중복 방지 상태를 함께 저장한다. 기존 도감·부화 저장과 차량 game wire는 변경하지 않는다. 앱 화면의 기존 차량 샘플/행동을 명시적으로 전달받으며 새 차량 구독을 만들지 않는다. UI/3D 연결과 실기 확인은 별도 작업이다.
## 6. 호감도 부화 데모 계약 2026-11-11

사용자 확정 규칙은 [호감도 부화 구현 기준](affinity-hatching.md)을 따른다. 기존 3주제/3점 초안 대신 0~100 호감도, 발화 +12/60초·-12·중립0, 쓰다듬기 +3/10초, 구역 놓기 +7/15초, 50점 필수 사진 업로드(+15), 100점 즉시 부화를 사용한다. 2026-11-14 변경으로 페어링 시 자동 준비하고 여행당 한 알만 진행한다. 미부화 알은 다음 여행으로 이어 키우며 부화 후 활성30분 재지급은 하지 않는다. 기존 호감도·사진 규칙과 부화 시간/거리 계산은 유지한다.

새 모드의 `/game`은 `contractVersion:2`와 `affinity:{score:number,target:100,phase:string,photoCompleted:boolean}`을 추가한다. phase는 incubating/photoRequired/resultPending/hatched/failed/discarded다. photoRequired는 stage=incubating, 저장 성공 후만 stage=hatched, 실패/버리기는 stage=failed로 표시한다. progress는 시간/거리 진행률이다. 앱-local 체크포인트에는 별도의 affinity 회차 상태를 저장한다. 사진 ID·원문·발화·인증토큰은 `/game`에 넣지 않는다. 구버전 차량에 신규 UI가 구현됐다고 가정하지 않으며 새모드는 입력UI와 연결한 데모에서 선택한다.

`DexEntry.sourceEggId`는 신규 결과의 로컬 중복 방지 키이며 기존 행에는 없어도 된다. 같은 키 결과 재시도에서 도감 중복을 만들지 않는다. 결과를 선택한 pending 회차를 먼저 저장한 뒤 도감에 적용하고 최종 체크포인트를 저장한다.

발화 내용 판정과 사진 저장은 RTDB와 별도인 데모 API다. 텍스트는 API 판정 후 앱/서버에 기록하지 않고, 사진은 데모방 인증 하에 서버에 저장·조회한다. 엔드포인트와 제한은 구현 기준 문서를 따른다. 새 API를 공개 서버에 배포하거나 기존 운영 DB 규칙을 적용했다는 뜻이 아니다.

## 주차 낚시 capability v1 (2026-11-11)

차량 #92 구현의 추가 계약은 [차량 주차 낚시와 폰 저장 계약 v1](vehicle/fishing-integration.md)을 따른다. 폰 단일 전체 `/game` writer를 유지하며 v2 동행·gameRevision과 별도 `fishing.version=1` 요약을 합성한다. 차량 `/vehicle/fishingPresence`는 주차·화면 활성 증거 및 lease echo를 보낸다. `fishingRequested` 이벤트는 폰에 의도를 전달하며 저장 완료나 보상 확정을 의미하지 않는다. 구버전/누락 시 낚시 시작은 비활성화한다. 공용 예시는 `data/fixtures/fishing-v1.json`이다. 개발용 Firebase 권한 규칙은 변경하지 않는다.

### 호감도 부화 연결 보완 (2026-11-12)

PR #93의 `affinity {score, target, phase, photoCompleted}` 요약은 낚시·동행과 동일한 전체 game snapshot에 합성한다. `score`는 소수일 수 있으며, `phase`는 사진 퀘스트·저장 대기·결과를 구분한다. #91의 `gameRevision`은 유지하고 기존 `ready` 형식의 차량 입력도 호환한다. 구체적인 단계와 검증 경계는 [호감도 차량 연결](vehicle/affinity-integration.md)을 따른다.


### 주차 재료·도감·거점 표시 확장 (2026-11-12)

폰 단일 game writer가 `contractVersion=2`/`gameRevision`와 함께 저장된 PR100 상태를 읽기 전용으로 보낸다. `collectionSummary` v1은 wood/stone/ingredient 현재 보유량과 speciesIds(수집 종ID 중복 제거), speciesCount를 제공한다. Firebase의 빈 목록 생략 시 speciesCount=0으로 빈 도감을 구분한다. 블록 미수신/저장 로드 실패는 0개로 추정하지 않는다.

`baseSummary`는 기존 역할/시설 요약에 facilityLevels(시설ID→0~3), activeTaskKinds(건설·요리·훈련 전체), foodInventory(음식ID→재고), recipeBook(음식ID→누적 제작 횟수)를 추가한다. 기존 필드는 호환하며 최근 식사를 추정하지 않는다. 차량은 주차 후 확인만 제공하고 보상/도감/시설을 변경하지 않는다. 상세 계약: [주행 자동 낚시와 주차 확인](vehicle/driving-auto-fishing.md).

## 개인 캐릭터 대화 역할 2026-11-14

[여행당 한 알과 캐릭터 탭 대화](superpowers/specs/2026-11-14-trip-egg-character-invitation-design.md)에 따라 개인 대화 흐름·페르소나·본문·장면 이동은 별도 인증 서버 API가 결정한다. 폰/Unity는 입력·소유 대상 검증·표시·TTS·요청 수명 관리와 서버 승인 장면 참조 저장만 맡는다. 페르소나·지식·스토리 원문을 폰 번들에 배포하지 않는다. 기존 RTDB 전체 game writer와 폰의 알/부화 판정 책임은 유지한다.

## 차량 진입/직접 대화 후속 변경 2026-11-14

[차량 연결 진입과 직접 대화](superpowers/specs/2026-11-14-cabin-pairing-direct-conversation-design.md)에 따라 최초 미연결 차 안은 연결 버튼 하나를 표시한다. QR 또는 직접 입력으로 성공한 페어링에서만 기존 여행당 알 준비를 수행하고 fake 초기화는 자동 연결/지급하지 않는다. 알/친구 상태·호감도·사진·시간/거리 진행은 독립 유지한다. 캐릭터 클릭은 서버 `greet`/`chat`으로 곧바로 연결하며 새 UI에 메뉴·챕터 낭독·다음 장면 버튼을 표시하지 않는다. 기존 작성형 API는 구버전 호환용이다. 서버 고유 페르소나와 고정 배경·학습자료는 앱에 포함하지 않는다. 게임 wire와 기존 지급/승계 계약은 바꾸지 않는다.

후속 [직접 조작 변경](superpowers/specs/2026-11-14-cabin-toss-and-rest-design.md)에서 연결 버튼은 차량 제목 자리에 배치한다. 간식·물·공·인형은 원형 버튼으로 고른 뒤 방향 스와이프로 던지며, 유효한 동작 뒤 기존 `commonCare`를 보낸다. 캐릭터 더블 탭 후 자유 배치는 로컬 표현이고 새 보상이나 서버 좌표 저장을 추가하지 않는다. 쿠션·담요에 놓을 때는 기존 돌봄 승인 경로를 사용한다.

## 미수집 친구와 마을 표시 선택 2026-11-15

[사용자 확정 변경](superpowers/specs/2026-11-15-collection-rewards-village-selection-design.md)에 따라 새 부화는 현재 도감의 미수집 종에서만 선택한다. 기존 환경·주행 조건에 맞는 후보를 우선하며 그 후보가 모두 수집됐으면 남은 종에서 고른다. 기존 도감·소유 개체와 이미 저장 중인 부화 결과는 지우거나 다시 추첨하지 않는다.

현재 카탈로그 12종을 모두 수집한 뒤의 새 여행은 알 대신 `berry_snack` 3개를 받는다. 여행별 지급 영수증과 음식 재고는 거점 로컬 저장에 함께 확정한다. 재접속·앱 재시작·저장 재시도로 같은 여행의 간식을 중복 지급하지 않으며, 12번째 종을 얻은 여행에는 알과 간식을 함께 지급하지 않는다. 기존 `baseSummary.foodInventory`에 저장된 재고가 반영되며 새 Firebase 보상 명령이나 제어 권한은 추가하지 않는다.

마을의 표시 친구 0~4개체는 소유 개체 ID 기반의 폰 로컬 설정이다. 초기 설정이 없는 경우만 기존 첫 4개체를 기본으로 사용하며 명시적인 빈 선택을 유지한다. 표시 선택은 건설·요리·훈련 배정 및 차량 동행 선택과 독립이고 체험/실제 프로필을 분리한다. Flutter→Unity의 로컬 표시 snapshot/action만 확장하며 RTDB 데이터 계약은 유지한다.

## 친구 부탁과 방문 이력 2026-11-15

사용자가 친구마다 각각 이틀 주기와 ‘여행 이력은 DB, 퀘스트 진행은 폰, 본문은 기존 이야기 서버’ 구조를 승인했다. [설계](superpowers/specs/2026-11-15-companion-quests-travel-history-design.md)와 [계획](superpowers/plans/2026-11-15-companion-quests-travel-history.md)을 따른다.

### 방문 기록

`recordDestinationVisit` callable 입력은 `sessionId, visitId, routeRevision, placeId, placeName, regionTag, arrivedAtMs, companionIds`다. `routeRevision`은 `route_<hex>` 형식의 문자열이다. 서버는 요청에 임의의 owner UID를 받지 않고 익명 인증된 세션 차량의 carUid와 서버 ACL phoneUid를 확인한다. 결과는 `{visitId,recorded:true}`다. 좌표·주소·주행 경로 필드는 허용하지 않는다.

`travelHistory/{phoneUid}`의 `visits/{visitId}`와 `places/{placeId}`를 한 transaction으로 기록한다. visits 값에는 visitId가 중복 포함되지 않으며 map key가 식별자다. 값은 위 입력 중 visitId를 제외한 필드에 `receivedAtMs`와 `evidence:destination-arrived`가 추가된다. 빈 companionIds는 RTDB에서 생략될 수 있다. places는 `{placeId,placeName,regionTag,visitCount,lastArrivedAtMs}`다. 같은 visitId/같은 내용 재시도는 횟수를 늘리지 않고, 다른 내용 충돌은 거절한다. 소유 폰 UID만 읽으며 차량·다른 UID·미인증과 클라이언트 직접 쓰기는 금지한다. 이 경로는 세션24시간 만료와 독립적으로 유지된다.

현재 폰은 장소 요약 전체와 `arrivedAtMs` 기준 최근 방문200개를 별도 읽는다. `visits`는 해당 필드 인덱스를 가진다. 읽기·인증·형식 오류는 unknown이며 빈 이력으로 추측하지 않는다. 새로운 폰 설치의 익명 UID는 기존 UID의 이력에 자동 연결되지 않는다. 현재 구현은 물리적 차량/사람 신원을 증명하지 않는다.

차량은 같은 세션의 경로·목적지와 대응하는 실제 `onDestinationArrived` 콜백만 기록한다. 내비 요청 성공·목적지 목록·P단 정차·경로 종료는 방문 완료가 아니다. 취소/새 경로는 이전 상관관계를 폐기한다. 경로 종료 뒤에는 최대30초 동안 실제 도착 이벤트를 기다린다. 운전자가 고른 기존18개 카탈로그의 ID는 `place_` + SHA256(region+개행+name)의 앞16hex다. 차량 내부의 이름·좌표 대응으로 SDK의 목적지 스냅을 최대500m까지 처리하고, 다른 것은 provider POI 또는 경로별 unknown ID로 구분한다. 가까운 동명 지점과 실제 SDK 콜백 순서는 별도 기기 검증이 필요하다.

### 차량으로 전달하는 부탁과 동행 식별

기존 전체 game writer에 선택적 `travelRequest:{wishId,targetRegion,targetPlaceId}`를 추가한다. targetPlaceId가 있으면 차량은 그 장소만 제안하며 기존 주차/연결/진행 경로 보호와 운전자 확인을 유지한다. 이 요청 전달로 퀘스트가 완료되지 않는다.

기존 companion 블록에 선택적 `ownedCreatureId`를 추가한다. displayId와 별개인 폰의 안정적인 소유 개체 ID다. 폰은 실제 저장된 선택 entry를 도감/거점 registry와 대조하고 복원하며, 차량은 유효한 현재 선택 친구만 방문의 companionIds에 넣는다. phone/car 위치 모두 동행으로 볼 수 있고 없거나 모르면 빈 목록이다. 전체 소유 친구를 모두 동행했다고 간주하지 않는다.

### 친구별 로컬 상태와 본문

거점 로컬 저장은 개체별 최초 관측 anchor와 `CompanionQuest`를 보관한다. 최초 부탁은 즉시 가능하고 48시간 구간은 anchor에서 계산한다. 미수락 부탁은 다음 구간으로 교체할 수 있고 만료된 옛 제안 수락은 거절한다. 수락한 부탁은 완료까지 유지한다. 개체가 같은 종이어도 독립이다.

음식 부탁은 기존 foodFeed 성공의 재고1개 차감·효과·완료를 한 로컬 저장으로 확정한다. 이야기 부탁은 사용자의 명시적 관찰 확인이며 실제 시야를 센서로 판정했다고 하지 않는다. 여행 부탁은 수락 후 실제 도착·정확한 장소·해당 동행 개체 ID가 모두 맞아야 완료되며 같은 방문의 반복 처리는 개체별로 멱등이다. 새로운 완료 재화를 추가하지 않는다.

본문은 `POST /v1/companion/quest-template`에서 받는다. 입력 `{speciesId,kind,variant}`의 variant는0~2147483647 정수다. 응답은 `{schemaVersion:1,templateId,templateVersion,speciesId,kind,title,text,storyId,targetFoodId,targetRegion}`이며 마지막3개는 해당 종류가 아니면null이다. 현재 실제 고정 스토리 자료가 없는 legacy6종의 이야기 요청은 먹이로 반환한다. 폰에는 본문/페르소나를 번들하지 않는다.

Unity의 `quests` snapshot과 openQuest/laterQuest/acceptQuest/observeQuest/requestQuestTravel intent는 앱 로컬 표시 계약이다. 마을·상세·도감의 `?`는 자동 본문/TTS를 열지 않는다. 과거 방문·오랜만이라는 문장은 실제 확인한 동행 이력이 있을 때만 사용하고, 장소 후보는 확인된 방문을 제외한다. 현재 바다 재방문 간격 기본값은14일이다. 서버와 SDK가 배포/구동되었다는 증거 없이 실사용 완료로 표시하지 않는다.

방문 이력 보완: 같은 owner transaction은 `companions/{creatureId}/places/{placeId}`에도 동행이 확인된 최신 도착을 기록한다. 값은 canonical visit과 동일한 필드에 embedded `visitId`를 포함한다. 더 오래된 도착·중복·동행자가 없는 도착은 이 인덱스를 바꾸지 않는다. 폰은 장소 요약·최근 방문200개·이 인덱스를 별도 읽고, 실제 근거와 동행 일치를 검증해 병합한다. 따라서 오래된 수락 후 도착과 캐릭터의 마지막 바다 방문이 최근200개 밖으로 밀려도 새 인덱스에 있으면 복구할 수 있다. 인덱스 이전 자료는 별도 백필하지 않으며 최근200개 밖의 이전 동행 이력은 없는 것으로 단정하지 않는다.
