# 알로(ALLO) 레포 구조 · 데이터 스키마

> 이 문서가 **팀 전체의 계약서**입니다. 변경은 C 승인 + 전원 공지.

---

## 1. 큰 그림 — 누가 무엇을 쓰고 읽는가

```
[차량 앱]  --write-->  /vehicle   --read-->  [폰 앱]
                                                |
                                             판정·계산
                                                |
[차량 앱]  <--read--   /game     <--write--  [폰 앱]
```

**원칙 — 판정은 폰에서만 합니다.**

- 차량 앱은 **센서 그 자체**. 신호를 raw로 올리고 판정하지 않습니다
- 폰 앱이 희귀도·부화를 계산해 `/game`에 씁니다
- 차 화면은 `/game`을 읽어 표시만 합니다

이렇게 나누면 차량 앱의 CPU 5% 제약을 쉽게 지키고, 게임 로직이 한 곳에만 존재합니다.

---

## 2. 레포 구조 — 모노레포

GitHub 링크 하나로 제출하므로 모노레포가 유리합니다.

```
allo/
├── README.md                  # 심사용. ⚠️ 소속·연락처 금지
├── CLAUDE.md                  # 작업 규칙 (Claude Code)
├── .gitignore
├── docs/
│   ├── schema.md              # 이 문서 (계약)
│   ├── architecture.md        # 스택 결정·근거
│   ├── verification.md        # A의 검증 8개 결과 기록
│   └── demo-scenario.md       # 시연 9단계
│
├── car/                       # A — Kotlin · Compose · Pleos SDK
│   ├── app/src/main/
│   │   ├── java/ai/allo/car/
│   │   │   ├── AlloApp.kt · MainActivity.kt
│   │   │   ├── model/Models.kt               # 3장 스키마와 1:1
│   │   │   ├── vehicle/
│   │   │   │   ├── VehicleSignalReader.kt    # Pleos 도메인별 구독
│   │   │   │   ├── AaosPropertyReader.kt     # 속도·기어 (CarPropertyManager)
│   │   │   │   ├── CapabilityChecker.kt      # 지원 신호 판별
│   │   │   │   ├── SignalDerivation.kt       # 급제동·급조향·거리
│   │   │   │   ├── EnvTagger.kt              # envTags 변환
│   │   │   │   ├── RegionTagger.kt           # 좌표 → 지역 태그 (좌표는 여기서 끝)
│   │   │   │   └── SeatPolarity.kt           # 좌석 반전 상수
│   │   │   ├── sync/
│   │   │   │   ├── FirebaseRest.kt           # REST + SSE
│   │   │   │   ├── SessionManager.kt         # 세션·페어코드·1초 발행·/game 구독
│   │   │   │   └── SessionService.kt         # 포그라운드 서비스
│   │   │   ├── ui/                           # PairingScreen · DrivingScreen · ParkedScreen
│   │   │   └── gleo/                         # GleoFunctions · GleoReceiver
│   │   ├── assets/schema.json                # Gleo 함수 정의
│   │   └── AndroidManifest.xml               # ⚠️ 읽기 권한만
│   ├── app/src/test/                         # 순수 Kotlin 단위 테스트
│   ├── build.gradle.kts · settings.gradle.kts · gradle/libs.versions.toml
│   └── local.properties.example              # ALLO_DB_URL
│
├── phone/                     # B — Flutter
│   ├── lib/
│   │   ├── main.dart                         # FEED=fake|firebase
│   │   ├── app.dart                          # 라우팅
│   │   ├── feed/                             # vehicle_feed(추상) · fake_feed ⭐ · firebase_feed
│   │   ├── game/game_controller.dart         # 세션 상태 머신
│   │   ├── screens/                          # pairing · incubating · hatching · companion · dex
│   │   └── storage/dex_store.dart            # 로컬 저장 (서버 X)
│   ├── packages/allo_core/    # C — 순수 Dart
│   │   ├── lib/src/                          # models · rarity_engine · hatch_timer · species_table
│   │   └── test/
│   ├── assets/{species,egg,ui}/              # D의 에셋 배치
│   └── pubspec.yaml
│
├── data/species.json          # C — 생물 12종
├── firebase/database.rules.json
├── art/{src,export}/          # D — 원본·png
├── scripts/                   # vc.sh · scenario_*.sh · seed_firebase.sh · fake_vehicle_feed.sh
└── apk/
```

> `allo_core`를 `phone/packages/` 안에 두면 C가 **Flutter 설치 없이** `dart test`로 개발할 수 있습니다.

---

## 3. Firebase Realtime Database 스키마

### 3.1 전체 구조

```
/sessions/{sessionId}
  ├── meta      ← car write, phone read
  ├── vehicle   ← car write, phone + car read
  ├── game      ← phone write, car read
  └── events    ← 양쪽 write/read (일회성)
```

`sessionId` — 차량 앱이 생성하는 UUID. 주행 1회당 1개.

### 3.2 `meta`

차량 앱이 세션을 만들 때 1회 기록.

```json
{
  "createdAt": 1793620000000,
  "pairCode": "483920",
  "paired": false,
  "carAppVersion": "1.0.0"
}
```

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `createdAt` | number | epoch ms |
| `pairCode` | string | 6자리. QR이 안 될 때 수동 입력용 |
| `paired` | boolean | 폰이 붙으면 폰이 true로 변경 |
| `carAppVersion` | string | 호환성 확인 |

### 3.3 `vehicle` — 차량 앱이 1초마다 씀

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
  "capabilities": ["wiper", "light", "seat", "odometer", "eta"]
}
```

| 필드 | 타입 | 비고 |
| --- | --- | --- |
| `ts` | number | 전송 시각 |
| `gear` | `"P"\|"R"\|"N"\|"D"` | 정차 판정의 기준. AAOS `GEAR_SELECTION` |
| `speedKph` | number | AAOS `CarPropertyManager` |
| `distanceM` | number | **세션 누적**. Odometer 델타 또는 속도 적분 |
| `harshBrake` | number | **세션 누적 횟수** |
| `harshSteer` | number | 동일 |
| `wiperLevel` | 0\|1\|2\|3 | 0=off |
| `headlightOn` | boolean | |
| `seatRow2` | boolean | ⚠️ SDK 값 반전 처리 후 |
| `etaSec` | number \| **null** | **내비 미사용 시 null** |
| `envTags` | string[] | 아래 표 |
| `capabilities` | string[] | **이 차에서 실제 읽히는 신호 목록** |

**`envTags` 값**

| 태그 | 조건 |
| --- | --- |
| `rain` | `wiperLevel > 0` |
| `tunnel` | `headlightOn` && 주간 시간대 |
| `night` | 일몰 이후 |
| `highway` | `speedKph > 80` 이 60초 이상 지속 |
| `coast` / `mountain` / `city` | 차량 앱이 위치로 판정 후 **태그만** 전송 |

> ⚠️ **위도·경도는 절대 올리지 않습니다.** 지역 판정도 차량 앱 안에서 끝내고 태그만 보냅니다. 아동 개인정보 요건이자 심사 가점 포인트입니다.

**`capabilities`가 중요한 이유** — 차종마다 읽히는 신호가 다릅니다. 폰 앱은 이 목록을 보고 "이 차에선 비 속성을 못 쓴다"를 알아야 합니다.

### 3.4 `game` — 폰 앱이 계산해서 씀

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
  "hatchAtSec": null
}
```

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `eggTier` | `"small"\|"mid"\|"large"` | 알 등급 |
| `stage` | `"idle"\|"incubating"\|"hatched"` | |
| `progress` | 0.0~1.0 | 차 화면 진행바에 사용 |
| `speciesId` | string \| null | 부화 후에만 |
| `attribute` | `"water"\|"dark"\|"normal"` \| null | |
| `tier` | 1\|2\|3 \| null | |
| `careCount` | number | 감싸기·노래 횟수 |
| `lookOutCount` | number | 창밖 보기 성공 횟수 |
| `hatchAtM` | number \| null | 거리 기준 부화 지점 |
| `hatchAtSec` | number \| null | ETA 기준 부화 지점 |
| `regionCollectionKnown` | boolean | 폰의 지역 수집 기록 요약을 사용할 수 있는지. 기본 false |
| `uncollectedRegions` | string[] | 현재 기기 도감에 수집 기록이 없는 coast/mountain/city |

> `hatchAtM`과 `hatchAtSec`는 최대 하나만 유효합니다. `hatchAtSec`는 해당 알의 인정된 품기 시간(초)이며 차량 세션의 절대 시각이 아닙니다. 지급 보류/idle에서는 둘 다 null일 수 있습니다.

#### 지역 수집 추천 요약 — C 작업 기준 확정, 2026-11-04

추천 기준은 **현재 기기 도감의 지역 수집 기록**이며 실제 방문 이력이 아니다. A가 이슈 #9에서 필드명과 아래 네 상태에 동의했고, C 사용자가 이번 구현 진행을 승인했다. 이 문서의 확정은 차량 앱 구현·팀 전체 적용·실기 검증 완료를 뜻하지 않는다.

| 수신 값 | 의미 |
| --- | --- |
| known 누락/false | 미확인. 목록을 사용하지 않고 기본 추천 |
| true + 유효한 목록 | 해당 미수집 지역에서 추천 |
| true + 빈 배열/목록 누락/null | 확인 결과 미수집 후보 없음. 기본 추천으로 되돌리지 않음 |
| known 자료형 오류 또는 true + 잘못된 목록/원소 | 미확인. 잘못된 원소를 제거해 후보 없음으로 만들지 않음 |

RTDB는 빈 배열 키를 지울 수 있으므로 폰은 모든 `/game.set()`에 known을 포함한다. 허용 지역은 coast/mountain/city뿐이며 none/unknown 같은 값을 목록에 넣지 않는다. 좌표·도감 원문·지역별 시간은 Firebase에 보내지 않는다.

폰이 도감 전체를 정상적으로 읽고 형식을 확인한 경우 요약을 만든다. 정상 빈 도감은 known=true이고 세 지역 모두 미수집이다. 과거 유효한 regionTag는 기존 수집 기록으로 유지하고, null/누락은 어느 지역에도 더하지 않는다. 손상 기록·알 수 없는 지역 값·읽기/저장 실패는 known=false로 처리한다. 저장 성공 후 요약을 갱신하며 새 알 지급 때 기존 도감 요약을 보존한다. 이 known 조건은 관측의 정확성이나 실제 미방문을 보장하지 않는다.

#### 알별 지역 집계 — 사용자 확인, 2026-11-04

- 알 지급부터 부화까지 관측한 지역의 시간을 합산한다. 동행 시간은 제외하고 새 알은 새 집계를 시작한다.
- 시간은 폰의 단조 증가 시계로 측정하며 앱 중단 시간은 제외한다. 패킷 수를 체류 시간으로 사용하지 않는다.
- 최근 수신한 지역은 **최대 5초**만 유지한다. 20초간 새 신호가 없으면 최대 5초는 이전 지역, 나머지 15초는 미확인이다. 신호가 정상적으로 계속 오면 지역 시간도 계속 누적된다.
- 지역 태그가 없거나 여러 지역이 충돌하면 미확인이다. 중복/역순 신호는 같은 시간을 다시 더하거나 태그 유효기간을 연장하지 않는다.
- 최장 지역 W가 유일하고, 그 시간 W가 두 번째 지역 S와 미확인 U의 합보다 큰 경우(W > S + U)에만 그 지역을 기록한다. 동률·충분한 근거 없음은 regionTag=null이다.
- 앱 중단·복구에서는 누적 시간을 유지하되 오래된 지역 태그를 열린 구간으로 복구하지 않는다. 차량에서 새로운 ts로 재발행하는 오래된 GPS 정보까지 이 5초 규칙이 검증하지는 못한다. 차량 위치 신선도는 A의 별도 확인 사항이다.

#### 반복 부화와 이어하기 — 사용자 확인, 2026-11-04

- 각 알 지급 시 사용할 수 있는 ETA로 그 알의 일정을 고정한다. 그 알 도중 ETA가 바뀌거나 사라져도 이미 정한 품기 시간을 되돌리지 않는다. 다음 알을 지급할 때 ETA를 다시 확인한다.
- ETA가 2분 이상 80분 이하이면 절반을 분 단위로 내린 시간 동안 품고, 나머지는 동행한다. 11분은 품기5+동행6, 정확히80분은40+40이다.
- ETA가 80분을 초과하면 품기40+동행30 뒤 같은 크기의 다음 알을 지급한다. 81분은40+30+5+6, 150분은40+30+40+40, 300분은5개 알이다.
- ETA가 없으면 기존 거리 모드(알 목표 거리의 절반)를 사용한다. 유효 ETA가 2분 미만이면 새 알 지급을 보류하고 기존 동행 상태를 유지한다. 첫 알이 없으면 idle로 대기한다.
- 앱 중단 시간은 진행에서 제외한다. 같은 알의 인정된 경과시간·단계·돌봄·판정 태그와 필요한 세션 기준점을 로컬에 저장해 복구한다. 새 알은 기존 주행 구독을 다시 시작하지 않는다.
- 새 알마다 돌봄·태그·급제동·급조향 평가 구간을 새로 시작한다. 차량 세션 누적 카운터를 새 알의 카운터로 그대로 사용하지 않는다. 기존 도감과 거리 중복 방지 기록은 보존한다.
- 부화 결과 저장이 실패하면 재시도할 결과를 보존하고 다음 알 지급으로 덮어쓰지 않는다. 종료 화면과 최종 저장은 반복 지급보다 우선한다.
- 앱 일시중단은 동행 회차도 복구하지만, 차량의 최종 종료까지 마친 부화 회차는 다음 차량 주행에서 새 알을 시작할 수 있도록 정리한다. 도감과 거리 중복 방지 기록은 유지한다.

희귀도 최소 수정도 사용자 확인으로 적용한다. rain은 wiper, tunnel/night는 light 지원 여부를 속성 판정과 생물 선택 양쪽에 동일하게 적용한다. 지원 목록이 없는 기존 직접 호출의 호환성은 유지한다. 기존 희귀종 우선·종/개체 등급 차이·돌봄 공식은 바꾸지 않는다.

이 계약은 운영 Firebase 삭제 활성화나 사람의 대사 검수 표시를 승인하지 않는다.

### 3.5 `events` — 일회성 신호

상태 폴링만으로는 "방금 부화했다"를 차 화면이 놓칠 수 있습니다. 이벤트 큐로 확실하게.

```
/sessions/{sessionId}/events/{pushId}
```

```json
{
  "ts": 1793620030000,
  "type": "hatched",
  "by": "phone",
  "payload": { "speciesId": "tide_keeper", "tier": 3 }
}
```

| `type` | 보내는 쪽 | 받는 쪽이 할 일 |
| --- | --- | --- |
| `paired` | phone | 차 화면이 페어링 완료 표시 |
| `hatched` | phone | 차 화면 부화 연출 + Gleo 발화 |
| `lookOutPrompt` | phone | — (기록용) |
| `gleoSpeak` | phone | 차량 앱이 Gleo로 발화 |
| `destinationSuggest` | car | 폰에 제안 표시 |
| `sessionEnd` | car | 폰이 도감 저장 후 정리 |

#### `sessionEnd` 소비 계약 — 2026-11-04 로컬 검토안

이 변경은 로컬 구현·검토를 위한 계약안이다. 팀 전체 공지, 원격 반영, Firebase 배포를 완료했다는 뜻이 아니다. 기존 경로·이벤트 필드·`stage` 값은 추가하거나 변경하지 않는다.

- 차량의 `sessionEnd`는 **해당 세션의 최종 종료**다. 폰은 수신 즉시 그 세션의 새 품기와 상호작용을 막고, 진행 중인 알의 거리·세션별 반영 위치 또는 이미 부화한 생물의 도감 저장을 마친다. 마지막 `/game` 결과는 유지한다.
- 폰의 기존 `endSession()`은 화면 이탈·품기 시작 전에 진행을 저장하는 **체크포인트**에도 사용한다. 체크포인트만으로 차량 세션을 최종 종료하거나 같은 세션의 재개를 금지하지 않는다. 원격 종료와 저장 동작을 구분한다.
- 이벤트 구독은 페어링한 세션에 고정한다. 같은 세션의 기존 `sessionEnd`가 구독 시 다시 전달돼도 최종 종료로 처리하며, `ts`가 현재 연결 시각보다 과거라는 이유로 무시하지 않는다. 다른 세션으로 바뀐 뒤 도착한 이전 구독·읽기 응답은 새 세션에 적용하지 않는다.
- Firebase 페어링은 메타 검증 후 해당 세션의 기존 이벤트에서 `by=car`, `type=sessionEnd`가 확인되면 거부한다. 확인과 연결 사이에 발생한 종료도 이벤트 구독에서 처리한다. 종료된 세션을 다시 사용하지 않고 차량의 **새 QR·세션 코드**로 연결한다.
- 정상 차량 루프는 마지막 `/vehicle` 쓰기를 시도한 뒤 종료 이벤트를 보낸다. 폰은 종료 저장 전에 해당 세션의 최신 저장 스냅샷을 한 번 읽어 마지막 신호 콜백이 늦게 도착하는 경우를 보완한다. Fake 읽기는 마지막으로 발행한 값을 반환하며 시간·거리를 진행시키지 않는다.
- 중복 종료와 수동 저장이 겹쳐도 종료 저장 작업을 공유한다. 읽기·도감 저장·진행 저장·페어링 정보 삭제가 실패하면 완료로 표시하지 않고 재시도를 제공한다. 실패 중에는 보관한 진행과 부화 결과를 유지하고 새 연결·새 품기를 막는다. 저장소 API가 `false`를 반환한 경우도 실패로 처리한다.
- 부화 전 진행은 기존 거리 이어하기 기록을 보존한다. 부화 후에는 도감 저장과 소비한 세션 거리의 체크포인트를 보존해 같은 거리를 다시 사용하지 않는다. 새 시간 정책이나 ETA 진행의 영구 복원은 이 변경 범위에 포함하지 않는다.

**현재 차량 송신의 한계:** `sessionEnd`에는 종료 이유·최종 스냅샷·최종 신호 번호가 없다. 마지막 `/vehicle` 쓰기가 실패해도 종료할 수 있고, 종료 이벤트 전송 실패를 재시도하지 않으며 앱 정지 직전 전송도 유실될 수 있다. 폰의 한 번 읽기는 서버에 성공적으로 저장된 값까지만 보완한다. 통신 끊김이나 오래된 신호만으로 종료를 단정하거나 유실된 거리·종료 이벤트를 복원하지 않는다. 차량 송신 보장은 A의 별도 변경·검증이 필요하다.

### 3.6 저장하지 않는 것

- ❌ 위도·경도
- ❌ 아이 이름·생년월일·연락처
- ❌ 도감 (→ **폰 로컬 저장**)
- ❌ 주행 경로

서버에는 **주행 1회 동안의 임시 상태만** 남습니다.

### 3.7 보안 규칙 (초안)

```json
{
  "rules": {
    "sessions": {
      "$sid": {
        ".read": "now - data.child('meta/createdAt').val() < 86400000",
        ".write": "now - data.child('meta/createdAt').val() < 86400000 || !data.exists()",
        "vehicle": { ".validate": "newData.hasChildren(['ts','gear'])" },
        "game":    { ".validate": "newData.hasChildren(['ts','stage'])" }
      }
    }
  }
}
```

> 24시간 조건은 접근을 제한할 뿐 데이터를 삭제하지 않는다. 사용자가 선택한 매일 정리는 별도 준비 코드로 제공하며, 운영 활성화 전에는 동작하지 않는다. 유효한 생성 시각이 24시간 이상 지난 세션만 조건부 삭제 대상으로 삼고, meta 없는 고아와 손상 시각은 검토 대상으로 남긴다. 매일 실행은 정확히 24시간째 삭제를 보장하지 않으며 실행 지연·실패 시 더 오래 남을 수 있다. 운영 인증·활성화·실제 삭제는 별도 검증 단계다.

---

## 4. `data/species.json` — 생물 테이블

```json
{
  "version": 1,
  "species": [
    {
      "id": "tide_keeper",
      "nameEn": "Tide Keeper",
      "nameKo": "물결지기",
      "attribute": "water",
      "tier": 3,
      "requires": { "envTags": ["rain"], "maxHarsh": 2 },
      "hint": "비 오는 날 부드럽게 달리면",
      "sprite": "species/tide_keeper.png"
    }
  ]
}
```

**12종 구성**

| | normal | water | dark |
| --- | --- | --- | --- |
| tier 1 | 1종 | 1종 | 1종 |
| tier 2 | 1종 | 1종 | 1종 |
| tier 3 | 1종 | 1종 | 1종 |
| 희귀 | 3종 (조건 복합: rain+tunnel 등) |

---

## 5. Day 1에 확인할 것

- [ ] C — Firebase 프로젝트 생성, 위 스키마로 샘플 1건 수동 삽입
- [ ] B — 그 샘플을 읽어서 콘솔에 출력
- [ ] A — 빈 앱에서 `/vehicle`에 1건 쓰기 성공
- [ ] 전원 — `docs/schema.md`에 이 문서 커밋

이 넷이 되면 **그날부터 완전 병렬**입니다.
