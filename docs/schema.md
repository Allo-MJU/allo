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

> `hatchAtM`과 `hatchAtSec` 중 하나만 채워집니다. ETA가 있으면 `hatchAtSec`, 없으면 `hatchAtM`.

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

#### `sessionEnd` 소비 동작 — #25 구현 범위

차량·폰 공통 계약의 확정본은 C가 작성한 [PR #38](https://github.com/Allo-MJU/allo/pull/38)의 `docs/schema.md`를 기준으로 한다. 아래는 #25의 종료 소비 구현 범위를 설명한다. #38 반영 시 해당 확정본으로 통합하며, 이 구현은 기존 경로·이벤트 필드·`stage` 값을 추가하거나 변경하지 않는다. 계약 확정과 실제 차량·Firebase 통합 검증 완료는 별개다.

- 차량의 `sessionEnd`는 **해당 세션의 최종 종료**다. 폰은 수신 즉시 그 세션의 새 품기와 상호작용을 막고, 진행 중인 알의 거리·세션별 반영 위치 또는 이미 부화한 생물의 도감 저장을 마친다. 마지막 `/game` 결과는 유지한다.
- 폰의 기존 `endSession()`은 화면 이탈·품기 시작 전에 진행을 저장하는 **체크포인트**에도 사용한다. 체크포인트만으로 차량 세션을 최종 종료하거나 같은 세션의 재개를 금지하지 않는다. 원격 종료와 저장 동작을 구분한다.
- 이벤트 구독은 페어링한 세션에 고정한다. 같은 세션의 기존 `sessionEnd`가 구독 시 다시 전달돼도 최종 종료로 처리하며, `ts`가 현재 연결 시각보다 과거라는 이유로 무시하지 않는다. 다른 세션으로 바뀐 뒤 도착한 이전 구독·읽기 응답은 새 세션에 적용하지 않는다.
- Firebase 페어링은 메타 검증 후 해당 세션의 기존 이벤트에서 `by=car`, `type=sessionEnd`가 확인되면 거부한다. 확인과 연결 사이에 발생한 종료도 이벤트 구독에서 처리한다. 종료된 세션을 다시 사용하지 않고 차량의 **새 QR·세션 코드**로 연결한다.
- 정상 차량 루프는 마지막 `/vehicle` 쓰기를 시도한 뒤 종료 이벤트를 보낸다. 폰은 종료 저장 전에 해당 세션의 최신 저장 스냅샷을 한 번 읽어 마지막 신호 콜백이 늦게 도착하는 경우를 보완한다. Fake 읽기는 마지막으로 발행한 값을 반환하며 시간·거리를 진행시키지 않는다.
- 중복 종료와 수동 저장이 겹쳐도 종료 저장 작업을 공유한다. 읽기·도감 저장·진행 저장·페어링 정보 삭제가 실패하면 완료로 표시하지 않고 재시도를 제공한다. 실패 중에는 보관한 진행과 부화 결과를 유지하고 새 연결·새 품기를 막는다. 저장소 API가 `false`를 반환한 경우도 실패로 처리한다.
- 부화 전 진행은 기존 거리 이어하기 기록을 보존한다. 부화 후에는 도감 저장과 소비한 세션 거리의 체크포인트를 보존해 같은 거리를 다시 사용하지 않는다. 새 시간 정책이나 ETA 진행의 영구 복원은 이 변경 범위에 포함하지 않는다.

**#18 기준 차량 송신의 한계 (#27 반영 전):** `sessionEnd`에는 종료 이유·최종 스냅샷·최종 신호 번호가 없다. 마지막 `/vehicle` 쓰기가 실패해도 종료할 수 있고, 종료 이벤트 전송 실패를 재시도하지 않으며 앱 정지 직전 전송도 유실될 수 있다. 폰의 한 번 읽기는 서버에 성공적으로 저장된 값까지만 보완한다. 통신 끊김이나 오래된 신호만으로 종료를 단정하거나 유실된 거리·종료 이벤트를 복원하지 않는다. 차량 송신 보장은 A의 [PR #27](https://github.com/Allo-MJU/allo/pull/27)에서 최종 쓰기·종료 이벤트 재시도와 요청 제한 시간으로 보강한다. #27은 재검토·통합 검증이 필요하며, 반영 후 설명은 #38 확정본을 따른다.

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

> 세션은 **24시간 후 만료**. 실제 제출 전에 TTL 정리 함수 또는 수동 삭제 정책을 README에 명시.

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
