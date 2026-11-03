# SDK 검증 결과

> A 담당 · Day 1~3 (11/3~11/5)
> 결과가 나오는 즉시 이 파일을 갱신하고 전원에게 공유합니다.
> **하나라도 실패하면 설계를 고쳐야 하므로 전원 회의를 엽니다.**

## 환경

| 항목 | 값 |
| --- | --- |
| Pleos Connect Emulator | (버전 기입) |
| Vehicle SDK | `ai.pleos.playground:Vehicle:2.3.2` |
| NaviHelper SDK | 3.0.5 |
| Android Studio | |
| 검증일 | |

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
| 8 | `Seat` 2열 점유값 반전 | ⬜ 미확인 | 반전이면 상수 처리 |

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
| 2열 좌석 점유 | 좌석 설정 상태 조회 | ⚠️ 설명에 점유 없음 (포지션·열선·안전벨트·머리 받침대) |
| 조향각 (급조향) | **목록에 없음** | ⚠️ |
| 속도 · 기어 | — (AAOS `CarPropertyManager`) | 기존 계획대로 |

- ⚠️ 두 항목은 에뮬레이터 `VehicleApiExplorer` 로 메서드 존재 여부를 확인한다. 샘플앱 README 에는 Steering wheel 도메인이 있어 콘솔 목록에서만 빠졌을 가능성도 있다
  - 조향각 불가 → `harshSteer` 를 빼고 급제동만으로 tier 판정 (**C 합의 필요**)
  - 좌석 점유 불가 → 2열 **안전벨트 착용** 으로 대체 검토
- **TextToSpeech 는 콘솔에서 "Coming Soon"** (STT · FusedLocation · Vehicle Control 도 동일). 단 Maven 저장소에는 `ai.pleos.playground:TextToSpeech` 3.3.1 까지 공개돼 있다. 라이브러리는 받을 수 있고 콘솔 신청만 막힌 것으로 추정. 에뮬레이터 발화 여부는 검증 #7 때 함께 확인하고, 안 되면 차 화면 텍스트로 대체
- 빌드 환경: JDK 17 + SDK Platform 35 로 `testDebugUnitTest`(12개 통과) · `assembleDebug` 성공. Pleos Maven 은 인증 없이 의존성 해석됨
