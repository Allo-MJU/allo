# SDK 검증 결과

> A 담당 · Day 1~3 (11/3~11/5)
> 결과가 나오는 즉시 이 파일을 갱신하고 전원에게 공유합니다.
> **하나라도 실패하면 설계를 고쳐야 하므로 전원 회의를 엽니다.**

## 환경

| 항목 | 값 |
| --- | --- |
| Pleos Connect Emulator | 2.1.0 (API 34, `crp_avd_arm64`, Vehicle Service 2.3.22) |
| Vehicle SDK | `ai.pleos.playground:Vehicle:2.3.2` |
| NaviHelper SDK | 3.0.5 |
| Android Studio | Homebrew cask, JDK 17 로 Gradle 실행 |
| 검증일 | 2026-11-03 (#1 · #2 · #3 · #4 · #6 · #8 실측, #7 부분) · 2026-11-04 (#5 실측) |

## 결과

| # | 확인 항목 | 결과 | 비고 |
| --- | --- | --- | --- |
| 1 | `Wiper` 값 갱신 | ✅ 됨 | VC Off/Low/High/Auto → SDK OFF/CONTINUOUS_LEVEL_1/CONTINUOUS_LEVEL_3/AUTO. 아래 실측 참조 |
| 2 | `Light`(전조등) 값 갱신 | ⚠️ 조건부 | 하향등 ON/OFF 는 갱신됨. 단 에뮬레이터는 Auto 모드에서 켜지지 않음 (아래 참조) |
| 3 | NaviHelper ETA 주행 중 갱신 | ⚠️ 조건부 | **ETA 읽기 ✅** (초 단위, 화면과 일치). **주행 중 갱신 ❌** — 에뮬레이터 GPS 고정이라 VC 로 달려도 그대로 (선례와 같음) → 시연은 거리 폴백 |
| 4 | `Odometer` 해상도 1km 미만 | ⚠️ 조건부 | SDK 는 km 소수 그대로 전달(13.257 → 13.257). **단 에뮬레이터는 주행해도 Odometer 가 안 늘어난다** → 시연은 속도 적분 폴백 |
| 5 | `INTERNET` 권한 외부 호출 | ✅ 됨 | 앱 → Firebase REST `meta`·`vehicle` 쓰기, `/game`·`/meta` SSE 구독 모두 동작. 세션 생성 순서 버그 수정 (아래 참조) |
| 6 | `CarUxRestrictions` 신호대기 판정 | ✅ 됨 | **기어 D + 0km/h = 제한(DO true)**. 제한 해제는 기어 P 에서만 → 설계(P 기준) 그대로 |
| 7 | Gleo Interface 함수 등록 | ⚠️ 부분 | **TTS 발화 ✅** (`TTS_SERVICE` 권한 필요). Gleo 수신·응답 브로드캐스트 ✅. 실제 음성 호출 → 우리 함수 연결은 미확인 |
| 8 | `Seat` 2열 점유값 반전 | ✅ 반전 확인 | VC `occupied` 와 SDK `getCurrentSeatOccupancy` 가 모든 좌석에서 반대. `SDK_OCCUPIED = false` 유지 |

> 표기: ✅ 됨 / ⚠️ 조건부 / ❌ 안 됨 / ⬜ 미확인

## 실패 시 대응

| 실패 항목 | 영향 | 대응 |
| --- | --- | --- |
| 1, 2 | 속성 시스템 붕괴 | 속성을 주행 품질 + 시간대로 대체 |
| 3 | 부화 타이밍 1안 불가 | 거리 폴백 단독 운영 |
| 4 | 거리 폴백 부정확 | 속도 적분으로 전환 |
| 5 | **폰 연동 전체 붕괴** | 전원 회의. 차 화면 단독 앱으로 축소 검토 |
| 6 | 정차 공유 범위 축소 | 기어 P에서만 동작 |
| 7 | 음성 기능 제외 | 차 화면 텍스트로 대체 |
| 8 | — | 상수로 뒤집어 처리 (`SDK_OCCUPIED = false`) |

## 선례에서 미리 확인된 것 (우리 실측 아님 · 2026-11-02 조사)

| # | 선례 결과 | 출처 |
| --- | --- | --- |
| 3 | 에뮬레이터 내비는 GPS 를 움직여도 위치가 판교에 고정됨 (NMEA 체크섬 오류). ETA 갱신 실측이 어려울 가능성 큼 | SoftRide `docs/demo_script.md`, Roadio README |
| 5 | 차량 앱에서 HTTPS 외부 호출 동작 (Supabase 연동) | 핸들온 |
| 6 | 에뮬레이터는 주행 중 글자 제한을 걸지 않음. 실차와 다를 수 있음 | Roadio |
| 7 | `assets/schema.json` + BroadcastReceiver 로 Gleo 함수 등록·응답 동작. 별도 신청 없음 | 핸들온 `car/app/src/main/assets/schema.json`, `gleo/GleoReceiver.kt` |
| — | 속도는 `PERF_VEHICLE_SPEED`(AAOS) 로 읽힘. Vehicle SDK 에 Gear 없음 | 핸들온 · SoftRide · 샘플앱 README |
| — | Pleos TTS SDK 3.3.1 온디바이스 동작. Android 기본 TTS 엔진은 없음 | Roadio |
| — | Virtual Console: `PUT /vehicle/gear`, `/vehicle/controls`, `/vehicle/seat`, `/vehicle/turn-signal`. 하트비트 필수 | 핸들온 `tools/drive.sh`, SoftRide |

## 추가로 확인된 것

(검증 중 알게 된 제약·버그·우회로를 여기에 기록)

### 2026-11-03 · Pleos Playground 콘솔 SDK 현황 (에뮬레이터 실측 아님)

Vehicle State 11개 항목, NaviHelper 2개 항목 모두 "사용 가능". 별도 신청 불필요.

| 알로 신호 | 콘솔 항목 | 상태 |
| --- | --- | --- |
| 브레이크 · 주행 거리 | 차량 주행 정보 조회 | ✅ |
| 전조등(하향·상향) | 내부/외부 라이트 상태 조회 | ✅ |
| 와이퍼 | **창문 상태 조회** 안에 "와이퍼 모드" | ✅ |
| ETA · 경로 | NaviHelper 경로 정보 조회 | ✅ |
| 목적지 제안 | NaviHelper 경로 탐색 설정 | ✅ |
| 2열 좌석 점유 | 좌석 설정 상태 조회 | ✅ 에뮬레이터 실측 — 아래 참조 (콘솔 설명엔 없지만 API 있음) |
| 조향각 (급조향) | 콘솔 목록에 없음 | ✅ 에뮬레이터 실측 — 아래 참조 (API 있음) |
| 속도 · 기어 | — (AAOS `CarPropertyManager`) | 기존 계획대로 |

### 2026-11-03 · 에뮬레이터 실측 (`VehicleApiExplorer` + Virtual Console)

콘솔 목록과 실제 SDK 는 다르다. **콘솔에 없는 조향각·좌석 점유도 SDK 에는 있고 동작한다.**

**Seat Occupancy (검증 #8)** — `checkSeatOccupancyCapabilities` Supported. area 는 `ROW_1_LEFT` ~ `ROW_3_RIGHT` 9개

| area | VC `seat.occupied` | SDK `getCurrentSeatOccupancy` |
| --- | --- | --- |
| `ROW_1_LEFT` (운전석) | `false` | `true` |
| `ROW_2_RIGHT` | `true` (`PUT /vehicle/seat?area=rear_right&kind=occupied&value=true`) | `false` |
| `ROW_2_LEFT` | `false` | `true` |

→ **세 좌석 모두 반전.** 알려진 SDK 버그와 일치. `SeatPolarity.SDK_OCCUPIED = false` 로 처리한다

**Steering Wheel Angle** — `checkSteeringWheelAngleCapabilities` Supported, range **-470..500**

| VC `steering` | SDK `getCurrentSteeringWheelAngle` |
| --- | --- |
| 0 | 0.0 |
| **120** (`PUT /vehicle/controls?...&steering=120`) | **-120.0** |

→ 값은 읽히지만 **부호가 VC 와 반대**다. `SignalDerivation` 은 조향각 **변화량의 절댓값**만 쓰므로 급조향 판정엔 영향 없음. 좌·우 방향이 필요해지면(예: 생물이 코너 방향으로 기울기) 부호를 확인하고 써야 한다. 실차 부호 규약은 미확인
- 조향각이 읽히므로 `harshSteer` 를 뺄 필요 없음 (C 공유만)
- VC 상한은 ±540 인데 SDK range 는 -470..500. 시나리오 스크립트는 ±470 안에서 쓴다

**Virtual Console 상태 응답에서 본 것** (`PUT /vehicle/controls` 응답 전체 상태)
- `body.wipers.front.mode`, `lights.headlamp_mode`, `odometer.traveled_distance_km`(소수) 키가 있다
- 전체 쓰기 엔드포인트 목록은 `GET /vehicle/catalog` 의 `features[].write_endpoint` 에 있다

### 2026-11-03 · #1 Wiper · #2 전조등 실측

**VC 주입 방법** (하트비트 필수)

```bash
curl -X PUT "http://127.0.0.1:8088/vehicle/body?front_wiper=Low"                       # Off | Auto | Low | High
curl -X PUT "http://127.0.0.1:8088/vehicle/lights?feature=headlamp_mode&value=LowBeam" # Off | Auto | Position | LowBeam
curl -X PUT "http://127.0.0.1:8088/vehicle/lights?feature=high_beam&value=true"
```

**#1 Wiper** — Wiper 도메인에 기능 2개, 둘 다 Supported (area `FRONT_WINDSHIELD`)

| VC `front_wiper` | `getCurrentWiperSwitch` | `getCurrentWiperState` |
| --- | --- | --- |
| Off | `OFF` | — |
| Low | `CONTINUOUS_LEVEL_1` | `ON` |
| High | `CONTINUOUS_LEVEL_3` | — |
| Auto | `AUTO` | — |

- 값이 즉시 갱신된다. 클러스터 화면의 와이퍼 표시(꺼짐/자동/저속/고속)도 같이 바뀜
- Switch 의 enum 은 `OFF · MIST · INTERMITTENT_LEVEL_1~5 · CONTINUOUS_LEVEL_1~5 · AUTO · SERVICE · OTHER` 로 schema 의 `wiperLevel 0~3` 보다 세밀하다
- **제안 (C 합의 필요)**: `rain` 판정은 **`WiperState == ON`**(실제로 닦고 있는가)으로 한다. `AUTO` 는 "우천 감지 대기"라 비가 안 와도 AUTO 일 수 있기 때문. `wiperLevel` 매핑은 OFF·MIST→0, INTERMITTENT_*→1, CONTINUOUS_1~2→2, CONTINUOUS_3~5→3, AUTO→WiperState 로 판단

**#2 전조등** — Light 도메인 22개 기능 중 `Low Beam Light`(`getCurrentLowBeamLightState`) Supported

| VC `headlamp_mode` | `getCurrentLowBeamLightState` |
| --- | --- |
| LowBeam | `ON` |
| Off | `OFF` |
| Position (미등) | `OFF` |
| **Auto** | **`OFF`** |

- LowBeam ↔ Off 전환은 즉시 반영된다 → 수동 조작 시나리오는 OK
- ⚠️ **에뮬레이터는 Auto 모드에서 주변 밝기를 시뮬레이션하지 않아 하향등이 켜지지 않는다.** 실차에선 대부분 Auto 로 두고 터널에서 자동 점등되므로, `tunnel`/`night` 판정은 스위치(`*Switch`)가 아니라 **실제 점등 상태(`getCurrentLowBeamLightState`)** 로 한다. 시연에서는 VC 로 `LowBeam` 을 직접 넣는다
- 상향등(`High Beam Light`), 미등(`Tail Lamp Light`)도 별도 기능으로 있다
- **TextToSpeech 는 콘솔에서 "Coming Soon"** (STT · FusedLocation · Vehicle Control 도 동일). 단 Maven 저장소에는 `ai.pleos.playground:TextToSpeech` 3.3.1 까지 공개돼 있다. 라이브러리는 받을 수 있고 콘솔 신청만 막힌 것으로 추정. 에뮬레이터 발화 여부는 검증 #7 때 함께 확인하고, 안 되면 차 화면 텍스트로 대체
- 빌드 환경: JDK 17 + SDK Platform 35 로 `testDebugUnitTest`(12개 통과) · `assembleDebug` 성공. Pleos Maven 은 인증 없이 의존성 해석됨
- **공식 샘플앱은 그대로 빌드되지 않는다.** `gradle/libs.versions.toml` 이 `vehicleSdk = "2.3.1"` 인데 Pleos Maven 에는 2.0.3 · 2.3.2 만 있다 → `2.3.2` 로 고치면 `assembleDebug` 성공. 또 `gradlew` 에 실행 권한이 없어 `sh ./gradlew ...` 로 실행해야 한다

### 2026-11-03 · #4 Odometer · #5 · #6 · #7 실측

**#4 Odometer** — Odometer 도메인 10개 기능. 누적 거리는 **`Distance Driven`** 의 `registerDistanceDriven` 리스너로 받는다 (`getCurrentDistanceDriven` 은 샘플앱에서 capability 미선언, `Current Distance Driven` 은 read API 없음)

| VC `PUT /vehicle/odometer?traveled_distance_km=` | `onDistanceDrivenUpdated` |
| --- | --- |
| 13.0 | 13.0 |
| 13.257 | **13.257** |
| 13.3 | 13.3 |

- 단위는 **km(Double)**, 소수 그대로 → 해상도는 1km 보다 훨씬 작다 (m 단위까지 표현 가능)
- ⚠️ **에뮬레이터는 주행으로 Odometer 를 올리지 않는다.** `gear=Drive` + 108km/h 로 20초 달려도 `traveled_distance_km` 0.0 그대로 (VC 가 속도를 적분하지 않음)
  - `SignalDerivation` 이 "오도미터가 안 변하면 속도 적분" 폴백을 이미 갖고 있어 에뮬레이터 시연은 그 경로로 간다
  - 또는 시나리오 스크립트가 `PUT /vehicle/odometer` 로 거리를 직접 올린다
- ⚠️ **코드 주의**: SDK 는 km 인데 `SignalDerivation.update(odometerM=)` 는 m 를 받는다. `VehicleSignalReader` 에서 **×1000** 해서 넘긴다

**#5 INTERNET (OS 레벨)**
- 에뮬레이터 기본 네트워크 `VALIDATED`(안드로이드 연결 확인 통과), `ping 8.8.8.8` 성공
- 앱 프로세스에서 `INTERNET` 권한으로 Firebase REST 를 부르는 것은 **DB URL 을 받은 뒤** allo 앱으로 확인한다. 선례(핸들온)는 동작

**#6 CarUxRestrictions** — `adb shell dumpsys car_service --services CarUxRestrictionsManagerService`

| VC 상태 | `DO`(Distraction Optimization 필요) | `UxR` |
| --- | --- | --- |
| P · 0km/h | false | 0 |
| **D · 0km/h (신호대기)** | **true** | 0x50 |
| D · 40km/h | true | 0x50 |
| D → 다시 0km/h | true | 0x50 |
| 다시 P | false | 0 |

- 설정 자체가 `idling`(D + 정지) 과 `moving` 을 같은 제한(0x50 = NO_KEYBOARD | NO_VIDEO)으로 둔다. **신호대기는 주행 중으로 판정된다** → 정차 화면은 기어 P 기준 유지
- 에뮬레이터 제한엔 글자 수 제한(0x4)이 없다. 선례(Roadio)와 일치. 실차와 다를 수 있으니 차 화면 주행 모드는 한 줄 원칙 유지

**#7 Gleo · TTS (시스템 패키지)**
- Gleo: `ai.pleos.gleoai.model.provider` 설치됨
- TTS: `android.intent.action.TTS_SERVICE` 를 `ai.pleos.playground.caas` 의 `SpeechService` 가 처리한다 → 콘솔 "Coming Soon" 과 별개로 **에뮬레이터엔 TTS 서비스가 있다**
- 내비: `ai.pleos.playground.service.navi`, 지도 앱 `ai.umos.maps.android.navigation.app` 설치됨 (#3 용)
- 함수 등록·발화는 allo 앱(`assets/schema.json`, `GleoReceiver`) 설치 후 확인

**확인 못 한 것**
- AAOS 속도·기어(`CarPropertyManager`)를 셸에서 읽는 `cmd car_service get-property-value` 는 user 빌드라 막힘 → allo 앱의 `AaosPropertyReader` 로 확인한다

### 2026-11-03 · 권한 실측 (allo 차량 앱 설치 후)

`adb shell dumpsys package ai.allo.car` · `pm list permissions -g -f` 기준

| 권한 | 에뮬레이터 | 조치 |
| --- | --- | --- |
| `pleos.car.permission.READ_WINDSHIELD_WIPERS` | **정의 없음** → Wiper capability `need Permission` | |
| `pleos.car.permission.CAR_WINDOWS` | normal (읽기) | **Wiper 에 실제로 필요한 권한.** manifest 추가 (`CONTROL_*` 아님) |
| `pleos.car.permission.CAR_MILEAGE` · `READ_CAR_STEERING` | 정의 없음 | 없어도 Odometer · 조향각 동작. 실차 대비 유지 |
| `android.car.permission.CAR_SPEED` | **dangerous** → 설치 시 `granted=false` | **런타임 요청 필요.** 안 받으면 속도 0 → 에뮬레이터 거리(속도 적분)도 0 → 알이 안 자람 |

- ⚠️ AAOS 는 `CAR_SPEED` 를 **위치 권한 그룹**으로 묶는다. 권한 창 문구가 **"알로에서 이 기기의 위치 정보에 액세스하도록 허용하시겠습니까?"** 로 뜬다. 실제로는 속도만 읽고 좌표는 쓰지 않지만, "위치를 수집하지 않는다"는 기획서·심사 메시지와 화면이 어긋나 보일 수 있다 → 권한 요청 전에 "속도만 읽어요" 안내 화면을 두는 것을 검토 (D·A)

### 2026-11-03 · `VehicleSignalReader` 연결 확인

VC 로 신호를 넣고 `SessionManager` 디버그 로그(`adb logcat -s SessionManager`)로 `VehicleSnapshot` 을 확인했다.

| VC 입력 | 스냅샷 |
| --- | --- |
| 2열 오른쪽 점유 | `seatRow2=true` (반전 처리 후) |
| 와이퍼 High | `wiperLevel=3`, `envTags` 에 `rain` |
| 하향등 LowBeam (KST 주간) | `headlightOn=true`, `tunnel` |
| D · 72km/h 1초마다 | `distanceM` 약 20m 씩 증가 (속도 적분 폴백) |
| 조향 0 → 150 | `harshSteer=1` |
| 72 → 40km/h | `harshBrake=1` |
| Odometer 1.5km 주입 | 첫 값은 기준점으로만 잡혀 거리가 튀지 않음 |
| capabilities | `gear, light, wiper, seat, steering, brake, odometer, speed` 전부 |

- `night`/`tunnel` 은 에뮬레이터 시간대(America/Los_Angeles)가 아니라 `EnvTagger` 의 `Asia/Seoul` 기준이다. 시연을 한국 낮에 녹화하면 하향등 = `tunnel`

### 2026-11-03 · #7 Gleo · TTS 실측 (allo 차량 앱)

**TTS (`DriverVoice`, Pleos TextToSpeech 3.3.1 · `Mode.ON_DEVICE`)** — ✅ 발화됨

```
DriverVoice: tts initialized
DriverVoice: tts start      ← speak("뒷자리에서 알을 품고 있어요")
DriverVoice: tts done       ← 약 2.7초 뒤
```

- 권한 **`pleos.car.permission.TTS_SERVICE`**(normal, `ai.pleos.playground.caas` 가 정의)가 없으면 `SecurityException`. manifest 에 추가함
- **`addEventListener` 는 `initialize` 성공 콜백 안에서** 불러야 한다. 먼저 부르면 SDK 내부 `lateinit property tts has not been initialized`
- 콘솔의 "Coming Soon" 과 무관하게 에뮬레이터에선 신청 없이 동작한다. 실차·앱마켓 심사에서 별도 신청이 필요한지는 미확인
- 디버그 빌드 전용 확인 방법:
  `adb shell am broadcast -a ai.allo.car.debug.SPEAK -n ai.allo.car/.debug.DebugSpeakReceiver --es text "안녕"`

**Gleo 함수 (`GleoReceiver` + `assets/schema.json`)** — ⚠️ 부분
- Gleo 를 흉내 낸 브로드캐스트 `REPORT_EGG_STATUS` → 앱이 `ai.pleos.playground.intent.action.APP_ACTION_RESPONSE` 로 응답하는 것을 `dumpsys activity broadcasts` 로 확인
- Gleo 본체는 `ai.umos.ambientai`(ASSIST). 실제로 "알로, …" 라고 말해 Gleo 가 우리 `schema.json` 을 찾아 부르는 경로는 음성 입력이 필요해 확인 못 함. 선례(핸들온)는 같은 방식으로 동작

### 2026-11-03 · #3 NaviHelper ETA 실측 (allo 차량 앱 `NaviEtaReader`)

디버그 브로드캐스트로 목적지를 강릉역으로 설정 (`NaviHelper.requestRoute`):

```
adb shell am broadcast -a ai.allo.car.debug.ROUTE -n ai.allo.car/.debug.DebugRouteReceiver \
  --ef lat 37.7644 --ef lng 128.8996 --es name "Gangneung Station"
```

| 시점 | 로그 | 내비 화면 |
| --- | --- | --- |
| 경로 설정 직후 | `status=ROUTE_DRIVE`, `drivingInfo destination duration=8580 distance=195000` | 2시간 23분 · 195km |
| 10초 뒤 poll | `destination remainTime=8580 remainDistance=195000 → etaSec=8580` | |
| VC D · 100km/h 45초 주행 | `remainTime=8580` **그대로** | 진행바 그대로 |
| 안내 종료 | `route cancelled`, `status=FREE_DRIVE → etaSec=null` | |

- **단위: `remainTime`·`duration` 은 초, `remainDistance`·`distance` 는 m.** 8580초 = 2시간 23분으로 화면과 일치
- `DestinationInfo.remainTime` 과 `DrivingInfo.destination.duration` 이 같은 값. 리더는 `getDestinationInfo()` 를 10초마다 poll + 이벤트로 갱신
- ❌ **에뮬레이터는 주행 중 ETA 가 줄지 않는다.** VC 는 속도만 바꾸고 GPS 는 판교에 고정이라 내비 기준으로는 차가 안 움직인다 (선례 SoftRide · Roadio 와 같음)
- 영향 작음: 폰 `HatchTimer` 는 **세션 시작 시점 ETA 를 고정**하고 경과 시간으로 진행도를 계산하므로, ETA 가 실시간으로 줄지 않아도 ETA 모드 부화는 동작한다. 다만 시연 시간(2~3분)엔 ETA 50% 가 안 오므로 **시연은 거리 폴백**(설계대로)
- 목적지 좌표는 `requestRoute` 로 내비에만 넘기고 Firebase 로 보내지 않는다 (규칙 2)

### 2026-11-04 · #5 앱 → Firebase 실측 · 차 화면 P↔D 전환

**#5 앱에서 Firebase 쓰기** (`firebase/database.rules.json` 이 콘솔에 적용된 상태)

- 처음엔 `meta` PUT 이 **401**. 원인은 앱의 순서 문제다: `publishLoop` 가 `createSession` 보다 먼저 `vehicle` 을 써서, 노드가 생긴 뒤 `meta/createdAt` 이 없는 상태가 된다 → 규칙 `.write` 조건(`now - createdAt < 24h`)이 거짓 → 이후 쓰기가 전부 401
- 수정: `meta` 쓰기가 성공하기 전에는 원격에 쓰지 않는다 (`SessionManager.sessionReady`). `meta` 실패 시 2초 간격 재시도
- 수정 후: `session created` → `vehicle write ok`. REST 로 다시 읽으면 `meta`·`vehicle` 이 그대로 있고 `ts` 가 1초마다 갱신됨. `lat`/`lng` 없음
- `etaSec: null`·빈 `envTags` 는 Firebase 가 키를 저장하지 않는다 → 폰은 **키 없음 = null/빈 배열**로 읽어야 한다
- 401 상태에서 만들어진 고아 세션(`vehicle` 만 있고 `meta` 없음)은 규칙상 REST 로 지울 수 없다 → 콘솔에서 수동 삭제
- 디버그 빌드에만 로그: `adb logcat -s SessionManager` 에 `session created sid=…`, `vehicle write ok/failed`, `screen …`

**차 화면 P↔D 전환** (콘솔에서 `meta.paired=true` 로 바꿔 폰 없이 페어링)

| 동작 | 화면 상태 변경까지 |
| --- | --- |
| `meta.paired` PATCH | 약 1초 (SSE) → Pairing → Parked |
| VC `gear=Drive` | 474 · 386ms → Driving |
| VC `gear=Park` | 386 · 386ms → Parked |

- VC 요청 시각 ~ `screen` 로그 시각 기준 (하트비트 curl 포함, Compose 렌더 제외). PT 에서 체감 지연 없음
- `/game` 에 `stage=incubating, progress=0.42` 를 쓰면 정차 화면에 `알을 품는 중 · 42%` 가 즉시 표시됨
- ⚠️ 수정 전엔 차 화면 글자가 안 보였다: `setContent` 에 테마가 없어 `Text` 가 검정, 창 배경도 검정. `MaterialTheme(darkColorScheme())` + `Surface` 로 감쌈

**`scripts/vc.sh` 추가**: `wiper 0-3|auto` · `light on|off` · `odo <km>`. `wiper 3; light on; odo 20.5` → 스냅샷 `wiperLevel=3, headlightOn=true, distanceM=20500, envTags=[rain, tunnel]` 확인

### 2026-11-04 · Gleo `SUGGEST_DESTINATION` → NaviHelper 목적지 설정

Gleo 를 흉내 낸 브로드캐스트로 2단계 흐름 확인 (실제 음성 호출은 #7 과 같은 이유로 미확인):

```
adb shell am broadcast -a SUGGEST_DESTINATION -n ai.allo.car/.gleo.GleoReceiver                     # 제안
adb shell am broadcast -a SUGGEST_DESTINATION -n ai.allo.car/.gleo.GleoReceiver --es confirm true    # 수락
```

| 순서 | `GleoReceiver` 응답 | 내비 |
| --- | --- | --- |
| 제안 없이 수락 | `fail` 먼저 어디로 갈지 물어봐 주세요. | 변화 없음 |
| 제안 | `success` 바다 쪽에서만 나오는 아이가 있어요. 경포해변까지 안내할까요? | — |
| 수락 | `success` 경포해변까지 안내를 시작할게요. | **경포해변 · 2시간 57분 · 200km** 경로 안내 시작 |

- 미방문 지역은 폰에만 있어 지금은 **현재 지역과 다른 지역** 폴백 (판교 → 바다). 실제 미방문 지역 연동은 이슈 #9
- 폴백에서는 "아직 안 가보셨네요"라고 말하지 않는다 (사실이 아닐 수 있음)
- 수락은 **제안 후 2분 안**, **직전에 제안한 고정 목적지**만 설정된다. `GleoReceiver` 는 보낸 쪽을 확인할 수 없어서 임의 좌표를 받지 않는다
- ⚠️ Gleo 가 파라미터(`confirm`)를 extras 로 넘기는 실제 형식은 미확인. boolean·문자열 `"true"` 둘 다 받는다
- 좌표는 내비로만 가고 Firebase 에는 `destinationSuggest` 이벤트로 지역 태그(`region`)와 `status`(offered/accepted)만 간다


### 2026-11-04 · 지역 판정 · 가까운 목적지 후보 (allo 차량 앱)

**현재 위치**: `NaviHelper.getCurrentLocationInfo()` → `onCurrentLocationInfo` 로 받는다. 별도 위치 권한 없이 내비가 알려준다. 좌표는 메모리에만 두고 로그·Firebase 로 내보내지 않는다 (`GeoPoint.toString()` 도 좌표를 숨김)

**지역 판정 (`RegionTagger.classify`)**: 기준점과의 거리. 우선순위 coast > mountain > city. 해안은 대표 해변·항구 반경 6km, 산은 국립공원 중심 반경 5~18km, 도시는 시청 부근 반경 6~14km (모두 근사)
- 에뮬레이터(판교 고정): `envTags=[city]` 확인

**목적지 제안**: 지역마다 후보 6~7곳, 현재 위치에서 가까운 순, 직선 120km 이내만. 같은 지역(지금 있는 곳)은 제안하지 않는다. 2분 안에 다시 물으면 다음 후보

| 순서 | 응답 (판교) |
| --- | --- |
| 1번째 | 산 쪽에서만 나오는 아이가 있어요. 북한산 국립공원까지 안내할까요? 직선으로 약 30km예요. 같은 산이라면 다른 곳도 괜찮아요. |
| 2번째 | 바다 쪽 을왕리해수욕장도 있어요. 직선으로 약 65km예요. 안내할까요? |
| 3번째 | 바다 쪽 만리포해수욕장도 있어요. 직선으로 약 110km예요. 안내할까요? |
| 수락 | 만리포해수욕장까지 안내를 시작할게요. |

- Firebase `events`: `destinationSuggest` 4건 (`offered` ×3, `accepted`), payload 는 `region`·`status` 만. 좌표 없음
- 후보 좌표가 `RegionTagger` 로도 같은 지역으로 판정되는지 단위 테스트로 확인 (지리산 화엄사가 빠져 노고단 구역 추가)

### 2026-11-04 · Pleos 온디바이스 LLM (`ai.pleos.playground:LLM:2.1.3.2`)

**결과: ❌ 에뮬레이터에서 비활성.** 서비스 바인딩은 되지만 Pleos 쪽이 요청을 무시한다.

- SDK: Pleos Maven `LLM 2.1.3.2`. `LLM(context, Mode.ON_DEVICE).initialize()` → `generateContent(prompt, listener)`. 권한 `pleos.car.permission.LLM_SERVICE`(normal)
- 에뮬레이터 구성: `ai.pleos.playground.caas` 의 `LLMService` 존재, 모델 패키지 `ai.pleos.gleoai.model.provider`(`/system_ext/app/LLMModelProviderSerivce`, **1.4GB**) 존재
- 호출하면 Pleos 서비스 로그: `[GAAS]OnDeviceLLMManagerImpl: startLLM ignored: on-device LLM is disabled` / `initialize(ai.allo.car) ignored`. 앱 쪽 콜백(`onResponse`/`onError`)은 **아무것도 오지 않는다** (40초 대기)
- `getprop`·`settings` 에 켜는 스위치 없음. `Mode.SERVER` 는 `registerApp(key, secret, …)` 자격 정보가 필요해 시도 못 함
- 디버그 전용 확인 코드: `DebugLlmReceiver` (`adb shell am broadcast -a ai.allo.car.debug.LLM -n ai.allo.car/.debug.DebugLlmReceiver --es prompt "…"`). release 빌드엔 안 들어간다
- **영향**: 런타임 대사 생성(설계 8절)은 보류. 공모전·PT 는 사람이 검수한 대사 뱅크로 간다. 실차에서 켜져 있는지, 또는 Pleos 에 활성화 문의가 필요한지는 미확인


### 2026-11-04 · 세션 종료(`sessionEnd`) · 시연용 지역 override (allo 차량 앱)

**종료 기준** (`SessionEndDetector`, 페어링된 세션만)

| 조건 | 종료 |
| --- | --- |
| 목적지 도착 이벤트 뒤 기어 P | 바로 (`arrived`) |
| 경로 안내 없이 기어 P 3분 | `parked` |
| 경로 안내 중 기어 P (휴게소 등) | 30분까지 기다림 |
| 누적 거리 100m 미만 (출발 전) | 끝내지 않음 |

종료하면 `events` 에 `sessionEnd` 를 쓰고 `vehicle` 쓰기를 멈춘다. 차 화면은 마지막 `/game` 을 계속 보여 준다. 기어가 P 를 벗어나면 **새 세션**(새 sessionId·페어링 코드)을 만들고 페어링 화면으로 돌아간다.

| 확인 (에뮬레이터, 폰 없이 콘솔 `meta.paired=true`) | 결과 |
| --- | --- |
| 50kph 20초 주행 → P → 대기 | P 14:07:35 → `session end reason=parked` 14:10:37 (3분) ✅ |
| debug 명령으로 종료 | `events` 에 `sessionEnd` 1건, 이후 `vehicle.ts` 갱신 멈춤 ✅ |
| 종료 뒤 D | `new session` → 페어링 화면 → 새 sid 로 meta 생성 ✅ |
| 도착 이벤트(`onDestinationArrived`) 경로 | ❓ 에뮬레이터 내비 위치가 고정이라 도착을 만들 수 없음. 단위 테스트로만 확인 |

> 폰(B) 참고: `sessionEnd` 는 payload 가 비어 있어 Firebase 에 `payload` 키가 없다. 종료 뒤 차는 새 세션을 만들므로 폰은 다시 페어링해야 한다.

**시연용 지역 override** — 에뮬레이터 내비 위치가 판교로 고정이라 지역 태그가 늘 `city` 다. 디버그 빌드의 `DebugDemoReceiver` 로 태그만 덮어쓴다 (좌표는 만들지 않는다).

```bash
adb shell am broadcast -a ai.allo.car.debug.DEMO -n ai.allo.car/.debug.DebugDemoReceiver --es region coast   # coast|mountain|city|off
adb shell am broadcast -a ai.allo.car.debug.DEMO -n ai.allo.car/.debug.DebugDemoReceiver --es end now
scripts/demo_sea_trip.sh [고속도로 초=90] [--wait]   # 도심 출발 → 고속도로 → 바다 → P → 종료
```

`demo_sea_trip.sh 5` 실행: `envTags` 가 `[city]` 39회 → `[coast]` 22회 → 종료 ✅

### 2026-11-04 · Gleo 수락 경로 수정 (PR #10 리뷰 반영)

Pleos 문서 확인 ([Examples](https://document.pleos.ai/en/docs/pleos-only/app-integration-guide/guide/examples) · [App Capability](https://document.pleos.ai/en/docs/pleos-only/app-integration-guide/guide/app-capability) · [Callback Schema](https://document.pleos.ai/en/docs/pleos-only/app-integration-guide/guide/action_callback)):
- 파라미터는 `confirm` extra 가 아니라 **`ACTION_PARAM` extra 의 JSON 문자열**로 온다 (예시는 따옴표로 한 번 더 감싼 형태) → 이전 코드는 실제 Gleo 의 수락을 못 읽었다
- `component: service` = `sendBroadcast` (지금 구조 맞음)
- 응답 status 는 `success` · `asking`(확인 필요) · `fail`. `mode: "silent"` 면 Gleo 가 말하지 않는다
- **보낸 쪽을 확인하는 방법(권한·서명·토큰)은 문서에 없다** → P1 은 완화만 가능. Pleos 문의 필요

| 확인 (에뮬레이터, adb 브로드캐스트) | 결과 |
| --- | --- |
| 앱을 열기 전 제안 → 수락 (Gleo 가 프로세스를 깨운 경우) | `NaviNotReady` → fail "내비가 아직 준비되지 않았어요…", accepted 이벤트 없음 ✅ |
| 앱 실행 후 제안 없이 수락 (위조) | `NoOffer` → fail, 내비 그대로 ✅ |
| 제안(asking) → 수락 (`ACTION_PARAM` 따옴표 감싼 형식) | `Started` → 내비 경로 설정, 차량 앱이 직접 TTS ✅ |
| 안내 중 제안 / 안내 중 수락 | fail "지금은 길 안내 중이에요…" / `NoOffer`, 경로 그대로 ✅ |
| 앱을 켜기 **전에** 시작된 안내 | `getRouteStateInfo` → `naviMode=ROUTE_GUIDING` 로 안내 중 인식 → 제안 fail ✅. `isRouting` 은 안내 중에도 false 라 쓰지 않는다 |

**PR #24 2차 리뷰 반영 (같은 날)** — 안내 상태를 ETA 와 따로 둔다 (`Guidance`: UNKNOWN / IDLE / GUIDING). 수락은 IDLE 일 때만. 차량 앱 TTS 가 말했을 때만 Gleo 응답을 silent 로 한다. 에뮬레이터 재부팅 후:

| 확인 | 결과 |
| --- | --- |
| 앱을 열기 전 제안 → 수락 (상태 UNKNOWN) | `NaviNotReady`, 내비 그대로 ✅ |
| 앱 실행 2초 뒤 `guidance UNKNOWN → IDLE`, 제안 → 수락 | `Started`, 차량 앱 TTS 발화 → 응답 `success (silent)` ✅ |
| 경로 시작 후 `GUIDING`, 제안 / 위조 수락 | fail "지금은 길 안내 중이에요…" / `NoOffer` ✅ |
| TTS 를 쓸 수 없을 때 Gleo 음성 유지 | ❓ 에뮬레이터에서 TTS 실패를 만들 수 없어 단위 테스트로만 확인 |


### 2026-11-04 · 포그라운드 서비스 크래시 · 좀비 서비스 (allo 차량 앱)

- **크래시**: 에뮬레이터 SystemUI 가 재시작을 반복하는 동안 앱이 `ForegroundServiceStartNotAllowedException` 으로 종료됨 (`SessionService.onCreate` 의 `startForeground`). 앱이 앞에 보이지 않는 순간에 서비스가 만들어진 것으로 보인다. 같은 조건을 다시 만들지는 못했다
- **좀비 서비스**: `am crash` 로 백그라운드에서 앱을 죽이면 `START_STICKY` 때문에 서비스만 되살아나 "실행 중" 알림이 뜨지만 `SessionManager` 는 시작되지 않아 아무것도 수집하지 않았다

수정: 서비스 시작을 `MainActivity.onStart`(화면에 보일 때)로 옮기고, 시작·`startForeground` 실패는 삼켜 서비스만 접는다(다음 onStart 에서 재시도). `START_NOT_STICKY`. Android 15 의 dataSync 6시간 limit 에 대비해 `onTimeout` 에서 서비스를 접는다.

| 확인 | 결과 |
| --- | --- |
| 실행 → 홈으로 나가 20초 | 서비스 `isForeground=true`, `vehicle.ts` 계속 갱신 ✅ |
| 백그라운드에서 `am crash` | 서비스가 되살아나지 않음 (좀비 없음) ✅ |
| 다시 열기 | 새 프로세스에서 `isForeground=true` ✅ |
| `startForeground` 거부 경로 | ❓ 재현 조건을 못 만들어 실기 확인 못 함. 예외를 잡는 코드만 추가 |

## 탐험 화면 — 가로 고정·진입 (2026-11-09, A)

휴대폰 에뮬레이터(Medium Phone API 37, debug, `SCENARIO=scene_tour`, Unity 없음 → 대체 화면).

| 항목 | 결과 |
| --- | --- |
| 앱 시작부터 가로 (`sensorLandscape` + `setPreferredOrientations`) | ✅ 스플래시부터 가로 |
| 알 품기·동행 화면에서 "차 안 둘러보기" → 탐험 화면 | ✅ 전체 화면 차 안 뷰, 왼쪽 위 돌아가기 |
| 홈 버튼으로 나갔다가 돌아오기 | ✅ 화면이 멈추지 않고 장면이 이어짐 (Unity 화면은 Unity 설치 후 다시 확인) |
| 가로에서 기존 화면 버튼 접근 | ✅ 차 안 뷰를 화면 높이 절반으로 줄여 스크롤로 접근. 가로 2단 배치는 5단계에서 |

## 탐험 화면 — Unity 연동 검증 (spike, 2026-11-09, A)

Unity 6.0.85f2 LTS, 공식 "Unity as a Library"(별도 안드로이드 화면) 방식. `flutter_unity_widget` 은 개발 중단·Unity 6 미표기라 쓰지 않았다.
휴대폰 에뮬레이터(Medium Phone API 37, arm64, 코어 1개), debug 빌드, `EXPLORE_UNITY=true`, `SCENARIO=scene_tour`.

| 항목 | 결과 |
| --- | --- |
| Unity 내보내기 (`scripts/export_unity.sh`) | ✅ 35초, `phone/unity/unityLibrary` |
| Unity 없이 빌드 | ✅ (`phone/unity` 를 치워도 `flutter build apk --debug` 성공) |
| 앱 용량 증가 | ✅ debug APK 212MB → 229MB (+17MB, 기준 80MB 이하) |
| 첫 진입 시간 | ✅ 0.94초 (기준 3초 이내) |
| 메시지 왕복 | ✅ Unity `ready` → Flutter `scene`·`cast`·`settings` → Unity 수신(echo) |
| Unity 가 열린 동안 장면 갱신 | ✅ 30초 동안 비 오는 바다→바다→산→터널→밤 도시 실시간 전달 |
| 메모리 | 앱 전체 PSS 약 360~380MB (Flutter+Unity, 기준선 미측정) |
| 여닫기 반복 | ⚠️ 고친 뒤 5회 연속 정상인 회차도 있었으나, 에뮬레이터 부하(loadavg 4~7, 1코어)로 Unity 표시가 수 초 늦는 경우가 있음. 실기기 재확인 필요 |

찾아서 고친 버그 (모두 테스트 추가):
1. 탐험 화면이 없을 때 온 Unity 메시지(지난 회차 close)를 엔진이 보관했다가 새 화면에 넘겨 바로 닫힘 → 처리기를 앱 수명 동안 한 번만 등록 (`unity_channel_test.dart`)
2. Flutter 화면이 다시 보일 때(resume) Unity 를 다시 엶 → resume 으로 열지 않음
3. 뒤로 가기 한 번에 탐험 화면과 동행 화면이 함께 닫힘 → 탐험 화면이 맨 위일 때 한 번만 닫기, Unity 는 키를 뗄 때 close
4. Unity 가 앞에 있으면 Flutter 가 백그라운드로 판단해 알 성장·신호 처리가 멈춤 → Unity 탐험 화면이 열린 동안은 활성으로 (`appActiveFor`)

## 탐험 화면 — 비주얼 다듬기·화면 안 조작 (2026-11-09, A) — #80 #78

Unity 6000.0.85f2, 휴대폰 에뮬레이터(Medium Phone API 37, arm64, 4코어/4GB), debug, `FEED=fake SCENARIO=scene_tour EXPLORE_UNITY=true`.
이 Mac 에는 Blender 가 없어 #80 의 건물·사람은 Blender 모델 대신 Unity 코드(기본 도형)로 만들었다. Blender 가 생기면 `tools/blender/props.py` 로 옮길 수 있다.

| 항목 | 결과 |
| --- | --- |
| 툰 셰이더: 그림자 경계 또렷 (`_RampSoft` 0.12→0.05), 외곽선 거리 비례 (`_OutlineDist`, 10m 기준 1배~6배), 2단 하이라이트 (`_HiSize`, 구름·차·유리) | ✅ `world_*.png` 캡처. 세상 물체(건물·차)에도 외곽선 0.02m |
| 후처리 (`Hidden/Allo/Post`, `AlloPost`): 1/4 해상도 블룸 + 채도·대비·비네트, 장면별 값 (`WorldDirector.Atmosphere`) | ✅ 낮 채도 1.22, 밤·터널 블룸 1.4/0.9. 전체 해상도 패스는 합성 1회 |
| 건물: 층 띠·옥상 난간·물탱크/실외기/계단실·발코니·1층 간판(밤에 빛남)·차양·문·진열창, 창문 칸 크기 일정 (`Kit.Facade`) | ✅ `world_city_*.png`. **창문 판이 처음부터 뒤집혀(법선이 건물 쪽) 안 보이던 버그**도 고침 |
| 사람: 다리·신발·몸통·팔·머리·머리카락·묶은 머리/모자·치마·가방, 아이 (`Kit.Person`) | ✅ 도형 12개 안팎, 인도 안쪽에 선다 |
| 비: 유리창 빗방울·물줄기 (`Allo/Glass`, `_Rain` 0~1), 앞유리 와이퍼 2개 (`Wipers`, 비 단계별 속도) | ✅ `world_highway_rain_front.png` |
| 차 안: 좌석 천 무늬 반복 완화 (256px, 큰 얼룩·올 자국, 타일 6→3.5) | ✅ `unity_*.png`. 천장 디테일은 Blender(cabin.py) 필요 → 미반영 |
| 캐릭터 D 그림 연결 | ✅ 경로 일치 확인: Flutter `assets/${sprite}` ↔ Unity `flutter_assets/assets/{sprite}` (`SpriteLoader`). `phone/assets/species/` 가 비어 있어 실제 그림은 미확인 |
| HUD (`Hud`, uGUI 코드 생성): 돌아가기 / 주행 종료(체험일 때만, `settings.canEndTrip`) / 먹이 주기 / 봤어!(창밖 친구 보일 때) / 안내 글(toast) | ✅ 에뮬레이터: 세 버튼과 한글 글자 표시, 체험 주행이라 "주행 종료" 보임 |
| 탭 (`TapInput`): 캐릭터 → 폴짝+하트+`tap`, 창밖 친구 → 발견+`spotted`, 머리받침·쿠션·인형·물병·손잡이 → 흔들림(`Wobble`), 천장등 → 실내등 켜고 끄기, 유리 → 빗방울 튀기기/반짝 | ✅ 에뮬레이터: 캐릭터 탭 → `{"type":"tap","id":"sea_mist"}` 수신. 물체 흔들림·유리는 에디터 로직만 (기기 미확인) |
| 먹이: 동행 옆에 사과 → 걸어가 세 입에 먹음 → 하트 (`CritterDirector.Feed`) | ✅ 에뮬레이터: 사과·하트, Flutter `feed` 수신 → 안내 글 "바다안개가 맛있게 먹었어요!" 표시 |
| 창밖 친구 (`Passersby`): 모은 친구가 18~36초마다 길가에 서 있음, 앞 3~45m 에 보이면 "봤어!" | ⚠️ 기기 미확인: 도감에 종이 하나(동행)뿐이라 친구가 없어 등장 조건이 안 됨. 두 종 이상 모은 뒤 다시 확인 |
| Unity → Flutter 의도 메시지: `tap`→놀아주기, `feed`→먹이, `endTrip`→체험 종료, `spotted`→`lookOut()` + toast. 주행이 끝나면 Flutter 가 Unity 를 내림 (`ExploreBridge.close`) | ✅ `explore_screen_test.dart` 11개, `explore_messages_test.dart`. 에뮬레이터: "주행 종료" → Unity 내려가고 Flutter "기록을 저장했어요" 화면 |
| 테스트 | ✅ Unity EditMode 34개, `flutter test` 171개, `flutter analyze lib test` 문제 없음 |

기기에서 찾아 고친 것:
1. **물리 모듈이 빌드에서 제거**되어 기본 도형의 충돌체를 못 붙이던 오류(`Can't add component because class 'BoxCollider' doesn't exist`)가 이전 빌드부터 있었다 → `Assets/link.xml` 로 Physics·UI 모듈 보존
2. **Props.fbx 메시가 읽기 불가**라 기기에서 조각 메시 합치기가 실패(`Cannot combine mesh that does not allow access`)해 나무·바위 등이 안 보였다 → 장면 빌드가 `isReadable` 을 켠다
3. 후처리 셰이더 `#pragma` 를 한 줄에 몰아 써 기기에서 검은 화면 → 줄 나눔 + 지원 안 되는 셰이더면 후처리 건너뜀
4. 성능: 에뮬레이터(4코어/4GB) 3.5~4.8fps. 전 빌드도 2~22fps 라 에뮬레이터로는 판단 불가 (#77 실기기)

## 탐험 화면 — 캐릭터 그림·3D 모델 준비·걷는 면 (2026-11-11, A)

Unity 6000.0.85f2, 휴대폰 에뮬레이터(Medium Phone API 37), debug, `FEED=fake SCENARIO=scene_tour EXPLORE_UNITY=true`.

| 항목 | 결과 |
| --- | --- |
| D 캐릭터 그림 6종 × 포즈 4개 (`phone/assets/species/{id}.png`, `{id}_move/happy/sleep.png`). 원본은 #86 `docs/mockups/assets/`, 피그마 "Species sheets — character-production-01" A~F 와 같은 그림 | ✅ 에뮬레이터: 바다안개가 D 그림으로 나옴. 나머지 6종(G~L)은 `species.json` 과 이름이 달라(#53 D12) 임시 얼굴 |
| 행동별 포즈: 걷기·점프 move, 자기·웅크리기 sleep, 탭·먹이 뒤 happy, 그 밖 idle. 그림이 왼쪽을 보므로 오른쪽으로 갈 때 뒤집음. 창밖 친구는 차가 오는 쪽을 보고, 발견되면 happy | ✅ `unity_*.png` |
| `Allo/Sprite` 셰이더: premultiplied alpha + 밉맵(반투명 가장자리 계단·검은 테두리 없음), 장면 빛을 조금 따름 | ✅ |
| D 그림 아래 함께 그려진 연한 회색 바닥판을 Unity 가 읽을 때만 지움 (`SpriteLoader.RemoveFloor`, 원본 파일은 그대로) | ✅ 3D 창턱 위에서 떠 있는 판처럼 보이던 문제 해결 |
| 3D 모델 경로: `scripts/import_characters.sh` → `CharacterImport.Run` → `Resources/Characters/C_{id}.prefab`. 모델이 있으면 차 안·창밖 모두 3D, 없으면 2D 그림 | ✅ 임시 모델(Quaternius 양·퍼그)로 에디터·에뮬레이터 확인 후 지움. 실제 모델은 이미지→3D 서비스로 생성 예정 |
| 걷는 면 가림 검사: 장면 빌드 때 면 위 9곳에 아이 눈·카메라 레일 앞끝에서 광선을 쏴 절반 넘게 가려지면 뺌 (유리·가는 물체 제외) | ✅ 뒷유리 아래 선반(`Walk_RearShelf`)만 빠짐. 아이 눈 0.89m < 등받이 위 1.03m 라 어디서도 안 보였음 |
| 앞·뒷좌석 사이 바닥 (`Walk_Floor`, cabin.py). 방석 바로 앞 0.4m 는 아이 방석에 가려져 앞좌석 쪽만 | ✅ `unity_floor.png`. 뒷좌석·창턱과 점프로 오감 |
| 오른쪽 뒷좌석 인형을 구석으로 옮기고 걷는 면을 그 앞쪽만 | ✅ 캐릭터가 인형을 뚫고 지나가지 않음 |
| 테스트 | ✅ Unity EditMode 53개 (가림·바닥 5개, 3D 모델 3개 추가), `flutter test` 177개 |

기기에서 찾아 고친 것:
1. 새 에셋을 넣은 뒤 빌드한 APK 에 그림이 빠져 있었다. Flutter 빌드 캐시(`.dart_tool/flutter_build`)가 이전 에셋 목록을 그대로 썼다 → 캐시와 `build/app/intermediates/flutter` 를 지우고 다시 빌드. `assets/species/` 에 파일을 추가하면 같은 일이 생길 수 있다

## 탐험 화면 — 주행 중 연결 1차 (Pleos 에뮬 → Firebase → 폰 → Unity, 2026-11-11, A) — #79

Pleos Connect v2.1.0 에뮬레이터(차량 앱 debug) + 휴대폰 에뮬레이터(Medium Phone API 37, `--dart-define-from-file=config/firebase.local.json --dart-define=EXPLORE_UNITY=true`). 한 Mac 에서 두 에뮬레이터 동시 실행. 페어링은 세션 ID + 6자리 코드 수동 입력.

| 항목 | 결과 |
| --- | --- |
| 폰 Firebase 초기화 (Android 앱 `ai.allo.allo_phone` 을 Firebase 프로젝트에 등록) | ✅ 페어링 화면까지 약 30초 (첫 실행) |
| 페어링: 폰 → `meta.paired` → 차 화면 | ✅ 차 화면이 "뒷자리 폰에서 알을 골라 주세요"로 바뀜 |
| 폰 → `/game` → 차 화면 | ✅ 부화 상태가 차 화면에 "깨어났어요! sea_mist" 로 표시 |
| 폰 → Unity 탐험 화면 (D 그림 바다안개) | ✅ |
| 차 지역 태그 → 폰 → Unity scene | ✅ `scripts/demo_sea_trip.sh` 로 도심 → 고속도로 → 바다, Unity 로그 `scene=city → road → coast` |
| 차 속도·기어 → Unity 창밖 움직임 | ❌ 이번 실행에서는 확인 못 함. 아래 1 |
| 급제동 → jolt 한 번, 지연 시간, `turns`·`headingDeg` 수신 | ⏸ 아래 2 때문에 다음에 다시 |

찾은 것:
1. **한 번 차량 앱이 차 신호를 못 받는 것처럼 보였다(재현 안 됨).** 과부하 상태에서 Virtual Console 로 D·30km/h 를 주자 클러스터는 D·30 인데 차량 앱은 새 세션을 만들지 않았고, 앱을 다시 켜자 정상이었다. 그 뒤 차량 에뮬레이터만 콜드 부팅해 (a) 부팅 직후 앱 실행 → D·30, (b) debug 세션 종료 → D 로 다시 확인했으나 둘 다 정상(`gear=D speedKph=30`, `new session (gear=D)`). 과부하로 에뮬레이터가 멈췄던 것으로 보고 코드는 고치지 않았다. 차량 서비스 재시작 상황은 root 권한이 없어 재현하지 못했다. 시연 전에는 차량 앱을 켠 뒤 VC 로 D 를 한 번 줘서 차 화면이 주행으로 바뀌는지 확인한다
2. **두 에뮬레이터 + Unity 를 한 Mac 에서 돌리면 폰 에뮬레이터가 버티지 못한다.** 바다 구간에서 Unity 0.2fps 로 떨어진 뒤 폰 에뮬레이터 시스템 전체가 재시작(`DeadSystemException: The system died`). 앱 문제가 아닌 호스트 부하로 본다(추정). 남은 확인은 폰 실기기 + Pleos 에뮬레이터로 하는 편이 낫다
3. Pleos 에뮬레이터 시계가 폰보다 약 하루 늦다(차 11-10 20:28, 폰 11-11 13:28). 지금 `dev` 는 차가 폰 시각을 비교하지 않아 문제없지만, PR #88(`/game.ts` 생존 신호, 15초 TTL)이 들어오면 이 조합에서 계속 "연결 안 됨"이 된다

## 탐험 화면 — 차 안 놀이 (2026-11-11, A)

휴대폰 에뮬레이터, `SCENARIO=scene_tour EXPLORE_UNITY=true`. 판정은 하지 않고 Flutter 에 의도만 보낸다 (`tap`·`feed`·`drink`·`lookTogether`, `kind` 는 문구용). 돌봄 횟수에 넣을지는 C 결정 대기.

| 놀이 | 조작 | 결과 |
| --- | --- | --- |
| 간식 던지기 | "간식" → 화면 톡/휙. 장면별 간식(바다 조개·산 도토리·도시 붕어빵·그 밖 사과). 빗나가면 굴러가고 주우러 감 | ✅ 에뮬레이터: 조개 → 바닥 → 먹음 → "바다안개가 조개를 맛있게 먹었어요!" |
| 공 던지기 | "공" → 던지면 달려가 아이 쪽으로 굴려 줌 | ✅ 창턱 → "공을 굴려 줬어요!" |
| 쓰다듬기 | 캐릭터 위를 문지름 (시점 고정) | ✅ 하트 + "기분 좋아해요!" |
| 쿠션 / 인형 / 물병 | 탭하면 작은 것이 친구 옆에 → 통통 뛰기 / 안고 쉬기(불 끄면 잠) / 마시기 | ✅ 쿠션 기기 확인. 인형·물병은 같은 경로(GiveToy), 기기 미확인 |
| 실내등 | 천장등 탭 → 끄면 잠듦 | ✅ |
| 담요 | 자는 친구 탭 → 덮어 주면 계속 잠, 다시 탭하면 깸 | ⚠️ 탭 순간 친구가 움직여 기기 확인 못 함. EditMode 테스트로 확인 |
| 김 서린 창 | 유리 꾹(0.45초) → 입김, 그 위를 끌면 지워져 그림. 비 오면 저절로 서림(아래가 짙게), 1분에 걸쳐 걷힘. 친구가 와서 구경 | ✅ 입김·구경 기기 확인. 선 긋기는 짧은 점 간격을 이어 칠하도록 고침 |
| 같이 창밖 보기 | 50~90초마다 창밖에 풍선. 친구가 창을 보고 안내 문구. 아이가 그쪽을 0.4초 보면 반짝 + `lookTogether`(= 창밖 보기 횟수) | ✅ 풍선·안내 확인. 시선 판정은 기기 미확인 |

함께 고친 것:
- 캐릭터가 아이 시야 밖이나 가려진 곳으로 가던 문제: 장면 빌드 때 면마다 9×9 보임 지도를 구워(편한 각도 + 앞좌석·머리받침에 안 가림) 그 칸에만 선다. 창턱은 보이는 0.74m 만, 계기판은 머리받침 뒤를 뺀 0.9m 만 쓴다. 바닥은 정면 화면 밖이라 1/4 확률로만 간다
- 2D 캐릭터 탭 상자가 발밑에 작게 있어 날개·당겨 그린 그림을 눌러도 유리가 눌리던 문제 → 상자가 그림을 따라간다
- 테스트: Unity EditMode 60개 (놀이 5개 추가), `flutter test` 178개

## 탐험 화면 — 알·부화 연출, 차 안 물건 놀이 (2026-11-12, A)

Unity 6000.0.85f2, 휴대폰 에뮬레이터(Medium Phone API 37, `-gpu host`), `FEED=fake SCENARIO=scene_tour EXPLORE_UNITY=true FAKE_TIME_SCALE=2`. debug 와 release 둘 다 확인.

흐름: 체험 시작 → 알을 받으면 **바로 Unity 차 안**(센터 콘솔 위 둥지에 알) → 돌보다가 그 안에서 깨어남 → 둥지에서 동행이 나옴. 탐험을 닫으면 품기 화면, 오른쪽 위 버튼으로 다시 들어감. 탐험 안에서 깨어나는 장면을 봤으면 닫을 때 부화 화면을 건너뛰고 동행 화면으로 간다.

| 항목 | 결과 |
| --- | --- |
| `egg` 메시지(Flutter → Unity): 단계·진행도·알 id·큰 알·태어남 문구. `cast` 보다 먼저 보낸다 | ✅ `explore_messages_test`·`explore_screen_test`, Unity `MessageParserTests`·`EggTrackerTests` |
| 알: 진행도에 따라 더 자주 들썩, 50·80·95% 에 금. 톡톡(탭)·문지르기·노래(버튼·오르골)·담요 → `care{kind}` → `GameController.care()` (같은 종류는 2~5초에 한 번) | ✅ 에뮬레이터: `care tap/rub/sing/blanket` 수신 |
| 깨어나기: 흔들림 → 금 → 빛 → 윗껍데기 날아감 → 둥지에서 동행 등장 + "OO이/가 태어났어요!"(3.5초 동안 다른 안내가 덮지 않음). 다른 곳을 보고 있으면 카메라가 둥지 쪽으로 돈다 | ✅ 에뮬레이터 debug·release 모두 `hatch start` → 약 2.6초 뒤 `hatched` |
| 차 안 물건(Blender `cabin.py`): 흔들 인형(대시보드)·장난감 자동차(바닥)·오르골(오른쪽 자리)·그림책(왼쪽 자리)·비눗방울 병(팔걸이 컵홀더)·휴지 상자(뒷선반), 알이 없을 때 둥지 = 동행 쉼터 | ✅ 오르골·장난감 차·비눗방울 기기 확인. 그림책·휴지·흔들 인형은 같은 경로, 기기 미확인 |
| 알만 있을 때 아래 버튼이 간식·공 대신 노래·담요 | ✅ |

함께 고친 것:
1. **release 빌드에서 Unity ↔ Flutter 연결이 끊김** (`ClassNotFoundException: ai.allo.allo_phone.ExploreBridge`). 코드 축소(R8)가 Unity 가 이름으로 찾는 클래스를 지웠다 → `phone/android/app/proguard-rules.pro`. 이전 release 빌드도 같은 문제였을 것으로 본다(추정, 이전 빌드는 다시 확인하지 않음)
2. 앱 라우터가 컨트롤러가 바뀔 때마다 경로를 다시 계산해 `push` 결과 Future 가 돌아오지 않음 → 탐험이 열려 있는지(`exploreScreenOpen`)로 판단
3. 동행 반응 문구 조사가 늘 "가"(폭풍등가) → 받침에 맞게 (`GameController.subjectOf`)
4. 담요가 알 위에 뜬 납작한 판 → 알을 감싸는 포대기, 알과 같이 흔들림
5. 김 서린 창 그림 선이 너무 굵음(약 19cm) → 텍스처 128 → 320칸, 붓 반지름 0.045 → 0.012 (약 6cm)
6. 끊김 줄이기: 김서림 계산을 0.1초마다(매 프레임 전체 계산 → 10Hz), 텍스처 버퍼 재사용(GC), 효과·장난감 재질을 색·그림마다 하나만 만들어 재사용(이전에는 만들 때마다 새 재질이 쌓였다)
7. 막 깨어난 동행이 터널·밤이면 바로 잠들던 것 → 8초 동안 깨어 있음

성능(에뮬레이터, 참고용): debug 빌드는 3~5fps, 2~25초 멈춤(디버그 JIT + 같은 프로세스). release 빌드는 28~60fps, 가끔 120~380ms 끊김. 에뮬레이터 기본 설정은 GPU 대신 CPU 렌더링(lavapipe·SwiftShader)이라 `-gpu host` 로 띄웠다. 측정 당시 Mac 에서 Spotlight 색인과 다른 가상 머신이 함께 돌았다. **실기기 측정은 #77** — Unity 가 10초마다 `[Perf] fps=… worst=…ms` 를 로그로 남긴다.

테스트: Unity EditMode 71개, `flutter test` 186개, `flutter analyze lib test` 문제 없음.

## 탐험 화면 — 캐릭터는 아이 곁에, 광장(홈) 화면, 시연 종 고정 (2026-11-12, A)

Unity 6000.0.85f2, 휴대폰 에뮬레이터(Medium Phone API 37, `-gpu host`), release,
`FEED=fake SCENARIO=scene_tour EXPLORE_UNITY=true FAKE_TIME_SCALE=2 DEMO_SPECIES=road_sprout`.

팀장 요청: 캐릭터가 물건을 뚫고 다니고 너무 돌아다니며 앞좌석으로 간다 → 천천히 아이 주변에. 주행 중 Flutter 차 안 화면은 없애고
Unity 차 안만. 뒤로 가면 광장 같은 곳으로 가서 화면마다 오갈 수 있게. 시연 캐릭터는 길싹이.

원인: 장면에 구워진 걷는 면이 **센터 콘솔·대시보드·앞문 창턱·앞 발판 5개뿐**이었다. 뒷좌석 옆자리·팔걸이는 "아이가 정면을 볼 때
안 보인다"(정면 60도 밖)는 규칙에 걸려 빠졌고, 창턱은 앞문까지 2.2m 가 통째로 걷는 면이라 B필러·앞좌석을 뚫고 다녔다.

| 항목 | 결과 |
| --- | --- |
| 걷는 면: 옆자리(`Walk_RearSeat_R`)는 정면에서 안 보여도 둔다(`IsHomeSurface`), 앞쪽은 아이 눈에서 `HomeDepth` 0.85m 까지만(창턱 2.23→0.65m, 발판 0.32→0.23m), 콘솔·대시보드는 비중 0 (둥지에서 깨어나면 발판→옆자리로 돌아옴) | ✅ 장면 빌드 로그·`BakedSceneHasFloorAndNoHiddenShelf`. 걷는 면 5 → 6 |
| 행동: 걷기 0.35→0.2m/s, 쉬기 0.8~2.5→2.5~6초, 한 번에 0.3m 안에서만(`RandomPointNear`), 점프 25→15%. 비중 0 면에 있으면 1~2초 뒤 비중 있는 이웃으로 | ✅ `LeavesZeroWeightSurfaceForWeightedNeighbor`·`StrollsStayShortAndSlow` |
| 그림을 카메라 쪽으로 당기는 것은 카메라가 뒤(-z)에 있을 때만 — 옆자리에서 당기면 팔걸이에 파묻힌다 | ✅ 코드. 기기에서 옆자리 확인은 아래 |
| 광장(`/home`): 알·동행 카드 + 차 안으로·도감·주행 종료. 알을 받으면 바로 차 안(알마다 한 번), 차 안 ← → 광장, 광장 → 차 안·도감 → 광장 | ✅ 에뮬레이터: ← 로 광장, 차 안으로 로 다시 Unity(`close` → `ready`), `fullscreen_cabin_test` 6개 |
| 주행 중 Flutter 차 안 화면(알 품기·동행의 `WindowView`)은 광장 흐름에서 안 쓴다. `/incubating`·`/companion` → `/home` 리다이렉트. 마음으로 알 품기·CLASSIC_UI 는 예전 흐름 그대로 | ✅ `plazaFlow()` |
| `DEMO_SPECIES=road_sprout`: 체험 주행에서 늘 길싹이가 깨어난다 (가짜 신호일 때만, 판정은 그대로 돌고 결과만 바꿈) | ✅ 테스트 '광장에서 부화하면 … 길싹이' |

찾아서 고친 버그:
1. **차 안에서 ← 로 나오면 Unity 가 0.2초 뒤 다시 열림 / 도감에서 돌아오면 광장이 사라짐.** 라우터 `refreshListenable` 이 컨트롤러라
   차 신호마다(1초) redirect 를 다시 돌렸고, 화면을 닫는 도중(pop 애니메이션)에 그 시점의 주소로 닫던 화면을 새로 만들었다
   (새 `ExploreScreen` → 새 Unity 열기). 기기 로그(`[UnityLauncher] open` 스택)로 확인. → redirect 가 보는 값(세션 종료·저장, 알 단계,
   마음 품기)이 바뀔 때만 알리는 `_RedirectSignal`. 이전 알 품기 화면 흐름에서도 타이밍에 따라 같은 문제가 날 수 있었다(추정)
2. 광장이 알마다 한 번만 부화 화면으로 보내도록(`_hatchShownEggId`). 안 그러면 "같이 가자" 뒤 광장이 또 부화 화면으로 보낸다

에뮬레이터(길싹이 고정): 체험 시작 → 바로 Unity 둥지의 알 → ← 광장(알 카드, 성장 8%) → 차 안으로 → 같은 Unity 로 복귀 →
2분 40초쯤 터널에서 부화 → 약 40초 뒤 둥지를 떠남 → 약 1분 뒤 아이 옆 오른쪽 창턱에 앉아 창밖을 봄. fps 46~57.
3. 터널·밤에 깨어나면 둥지(콘솔, 비중 0)에서 바로 웅크리거나 잠들어 아이 곁으로 안 옴 → "아이 곁으로 돌아오기"를 밤·터널 판단보다
   먼저 (`ComesHomeFromNestEvenAtNightOrInTunnel`)

4. 창턱에 앉으면 그림 가운데가 6cm 창턱 위에 놓여 절반이 문·유리 속으로 들어가 발과 잎이 잘려 보임(팀장이 캡처로 지적) →
   몸보다 좁은 면에 앉으면 그림을 차 안쪽으로 당겨 바깥 가장자리가 창턱 안쪽 가장자리에 오게(`CritterView.LedgeOverhang`, 0.3초에 걸쳐)
5. 비중 있는 이웃이 없으면 점프하지 않고 지금 면 안에서만 거닌다 (발판에서 콘솔로 되돌아가던 것)

에뮬레이터(최종 빌드): 부화 뒤 둥지를 떠나 아이 옆자리로 → 밤이라 옆자리에서 잠("길싹이가 포근하게 자요") → 아침에 옆자리에서 걷기.

### 알 깨어나는 연출 다시 (팀장: "너무 대충")

전: 1.4초 흔들림 → 금 한꺼번에 → 0.45초 부풀기 → 윗껍데기만 날아가고 동행이 그 자리에 서 있음 (약 2.4초, 멀리서 작게 보임).
후(약 7초, 움직임 줄이기면 약 4초):
1. "앗, 알이 움직여요!" + 카메라가 둥지 쪽을 보며 레일을 45% 앞으로 (`CameraRig.Ride`), 친구들이 쳐다봄
2. 세 번 들썩(작게 → 중간 → 크게 콩콩), 들썩일 때 찌그러졌다 펴지고, 멈출 때마다 가루와 금 하나
3. 남은 금이 하나씩 쫙쫙 (금마다 톡 튀는 크기 변화)
4. 알 속 빛이 새어 나오며 부푼다 (둥지 위 빛 번짐 `Fx.Glow` + 점광, 점점 빠른 떨림)
5. 번쩍(`Hud.Flash`) → 윗껍데기 날아가고 껍데기 조각 8개가 튀어 둥지에 떨어져 한 번 튕김(`Toys.Kind.EggBit`), 별 18개
6. 동행이 웅크린 채 작게 나왔다가 폴짝 튀어나오며 조금 넘치게 커졌다 제 크기로 (`CritterView.Born`), 0.35초 뒤 "OO이/가 태어났어요!" 4초, 하트
7. 두 번 더 폴짝 인사 → 카메라 제자리로 (`CameraRig.RideBack`), 아래 껍데기는 6초 뒤 사라짐
아이가 손가락으로 둘러보기 시작하면 카메라 이동은 바로 멈춘다.

테스트: Unity EditMode 78개(+7), `flutter test` 314개, `flutter analyze lib test` 문제 없음.

## 탐험 화면 — 말풍선 대사, 담요 입체화, 창밖 손님 6종, 발 잘림 (2026-11-12, A)

팀장 지적: 탭하면 발이 비어 보이고 발밑에 바닥 같은 게 남는다 / 담요가 평면이라 잘린다 / 캐릭터가 말을 하면 좋겠다(속성·상황, 영어 자연스럽게, "공 던져 줘" 같은 부탁) / 풍선처럼 창밖 요소를 여러 가지로.

| 항목 | 결과 |
| --- | --- |
| 발 비어 보임: 그림은 멀쩡했다(팀장 확인). 그림 아래 바닥 자국을 지우는 `SpriteLoader.RemoveFloor` 가 "밝기 70 이상·채도 낮음"을 바닥으로 쳐서 길싹이의 어두운 올리브색 발(밝기 40~120, 아래 띠 픽셀의 46%)까지 지웠다 → 밝기 150 이상만 바닥(맨 아래 5% 줄은 색조 상관없이). "발밑 바닥 같은 것"은 발 사이에 끼인 **그림자 판의 흰 테두리**(투명 영역과 안 이어져 1차 지우기로는 안 빠짐) → 아래 10% 안의 아주 밝고 채도 낮은 픽셀은 이어짐과 상관없이 지운다(2차). 셰이더도 그림 아래 16% 를 바닥 그늘처럼 어둡게(`_GroundShade` 0.5, 효과 그림 제외). 묻기는 1.6cm. 그림자 판 없는 흰 종(바다안개·등불나방)은 원래대로 건너뜀 | ✅ 에디터 캡처 `unity_seat_idle_bubble.png` |
| 담요: 평면 4장 → 아랫몸을 감싸는 낮은 돔 + 둘레 주름 단 + 크림 점 (`Toys.Kind.Blanket`), 발 자리에 놓고 카메라 쪽을 보게. 머리와 등 잎은 담요 위로 | ✅ 에디터 캡처 `unity_seat_blanket*.png` (1차는 돔이 머리까지 덮어 낮춤) |
| 말풍선 (`SpeechBubble`): 캐릭터 머리 위 월드 캔버스, 톡 커지며 나타나고 사라짐. 대사 뱅크 `phone/assets/data/cabin_dialogue.json` (상황\|대상\|문맥, 종 → @속성 → * / 문맥 → *), 규칙 검사 `cabin_dialogue_test.dart` | ✅ Unity `DialogueTests` 5개, Flutter 4개 |
| 말하는 때: 태어날 때 첫마디 · 장면 바뀔 때(도로·바다·산·도시·고속도로·터널·밤·비) · 간식·공·쓰다듬기·담요·깨우기·둥지·급제동 · 물건 6종 · 창밖 손님 등장/같이 봄 · 35~65초 혼잣말(1/3 은 부탁: 공·간식·쓰다듬기·창밖) | ✅ 코드. 기기 확인은 아래 |
| 영어: 창밖·놀이 사물 이름을 한 문장에 하나, 한글 뜻과 같이 ("바다는 영어로 sea"). 되묻기·무서운 말 없음. 길싹이는 풀 속성(잎·나무·햇빛) 말투 | ✅ 테스트가 검사 |
| 창밖 손님: 풍선 하나 → 장면별 풍선·연·새 떼·비행기·별똥별(밤)·고래(바다). 32~57초마다, 같이 보면 25~45초 뒤 다음 손님. 비·터널엔 없음 | ✅ 코드 `PickSky`/`SkyTick`. 기기 확인은 아래 |
| 부화 뒤 인사 동안 둥지에 머문다(`Hold`), 옆자리는 아이 코앞 0.42m 안은 안 쓴다(`ClipNear`) — 태어나자마자 화면 구석에 크게 걸리던 것 | ✅ |

레퍼런스(아이용 대화 설계): 짧고 쉬운 말·뚜렷한 성격·따뜻하되 "제일 친한 친구"가 아닌 "친절한 사서" 거리(uglabs, astrosafe), 대화 갈래를 설계가 통제(invision), 아이는 캐릭터를 시험·도발하며 논다(arXiv 2604.02629). 차 안 놀이 레퍼런스: 창밖 I-spy·알파벳 찾기·사물 이름 말하기(education.com, twinkl) → "창밖 손님 + 영어 단어 하나"로 옮김.

테스트: Unity EditMode 83개(+5), `flutter test` 318개(+4).

추가(2026-11-13): 시트 위에서 그림이 찌부해 보임(팀장) → 아이 눈이 시트보다 45cm 위라 30~45도로 내려다봐 수직 그림의 세로가 눌려 보이던 것.
그림을 발을 축으로 카메라 쪽으로 눕힘(내려다보는 각도의 80%, `CritterView.LeanRatio`). 묻기·창턱 당김·카메라 쪽 당김은 발 자리 기준으로 다시 계산.
에디터 캡처 `unity_seat_idle_bubble.png` 에서 몸이 또렷이 서 보임. 근본 해결은 길싹이 3D 모델(Tripo) — 엔진은 `Resources/Characters/C_road_sprout.prefab` 만 있으면 자동으로 3D 사용.
