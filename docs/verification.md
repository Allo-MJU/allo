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
| 검증일 | 2026-11-03 (#8) |

## 결과

| # | 확인 항목 | 결과 | 비고 |
| --- | --- | --- | --- |
| 1 | `Wiper` 값 갱신 | ⬜ 미확인 | |
| 2 | `Light`(전조등) 값 갱신 | ⬜ 미확인 | |
| 3 | NaviHelper ETA 주행 중 갱신 | ⬜ 미확인 | 갱신 주기도 함께 기록 |
| 4 | `Odometer` 해상도 1km 미만 | ⬜ 미확인 | 최소 변화 단위 기록 |
| 5 | `INTERNET` 권한 외부 호출 | ⬜ 미확인 | **실패 시 설계 전면 재검토** |
| 6 | `CarUxRestrictions` 신호대기 판정 | ⬜ 미확인 | 기어 D + 속도 0일 때 상태값 |
| 7 | Gleo Interface 함수 등록 | ⬜ 미확인 | 신청 필요 여부 |
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
- `body.wipers.front.mode`, `lights.headlamp_mode`, `odometer.traveled_distance_km`(소수) 키가 있다 → #1·#2·#4 를 VC 로 주입할 수 있을 것 (엔드포인트는 미확인)
- **TextToSpeech 는 콘솔에서 "Coming Soon"** (STT · FusedLocation · Vehicle Control 도 동일). 단 Maven 저장소에는 `ai.pleos.playground:TextToSpeech` 3.3.1 까지 공개돼 있다. 라이브러리는 받을 수 있고 콘솔 신청만 막힌 것으로 추정. 에뮬레이터 발화 여부는 검증 #7 때 함께 확인하고, 안 되면 차 화면 텍스트로 대체
- 빌드 환경: JDK 17 + SDK Platform 35 로 `testDebugUnitTest`(12개 통과) · `assembleDebug` 성공. Pleos Maven 은 인증 없이 의존성 해석됨
- **공식 샘플앱은 그대로 빌드되지 않는다.** `gradle/libs.versions.toml` 이 `vehicleSdk = "2.3.1"` 인데 Pleos Maven 에는 2.0.3 · 2.3.2 만 있다 → `2.3.2` 로 고치면 `assembleDebug` 성공. 또 `gradlew` 에 실행 권한이 없어 `sh ./gradlew ...` 로 실행해야 한다
