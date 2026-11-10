# 알로 차량 앱 (Pleos Connect)

센서 + 가족 화면 + 음성 + 목적지 제안. **판정은 하지 않고** 신호를 Firebase에 올리고, 폰이 계산한 `/game`을 읽어 표시한다.

## 환경

| 항목 | 값 |
| --- | --- |
| 에뮬레이터 | Pleos Connect Emulator 2.1.0 (Android 14, API 34, x86_64 / arm64 이미지 별도) |
| Pleos SDK | Vehicle 2.3.2 · NaviHelper 3.0.5 · TextToSpeech 3.3.1 |
| 빌드 | JDK **17** (Android Studio 번들 JBR 25는 Gradle 8.10.2를 못 돌림) · AGP 8.8.2 · Kotlin 2.0.0 · compileSdk 35 / minSdk 28 |

```bash
cp local.properties.example local.properties   # ALLO_DB_URL, sdk.dir 채우기
JAVA_HOME=/path/to/jdk-17 ./gradlew testDebugUnitTest   # 순수 Kotlin 단위 테스트 (SDK 없이 돌아감)
JAVA_HOME=/path/to/jdk-17 ./gradlew installDebug        # 에뮬레이터 설치
```

## 구조

```
app/src/main/java/ai/allo/car/
├── AlloApp.kt / MainActivity.kt
├── model/Models.kt              # schema.md 3장과 1:1. ⚠️ 위도·경도 필드 금지
├── vehicle/
│   ├── VehicleSignalReader.kt   # Pleos Vehicle SDK 구독 (TODO: 도메인별 메서드명 채우기)
│   ├── AaosPropertyReader.kt    # 속도·기어 (CarPropertyManager)
│   ├── CapabilityChecker.kt     # 차종별 지원 신호
│   ├── SignalDerivation.kt      # 급제동·급조향 카운트, 거리 적분   ← 테스트 있음
│   ├── EnvTagger.kt             # rain / tunnel / night / highway  ← 테스트 있음
│   ├── RegionTagger.kt          # 좌표 → coast/mountain/city. 좌표는 여기서 끝
│   └── SeatPolarity.kt          # 좌석 반전 상수 한 곳
├── sync/
│   ├── FirebaseRest.kt          # REST(PUT/PATCH/POST) + SSE 스트림. Firebase SDK 불필요
│   ├── SessionManager.kt        # 세션 생성·1초 발행·/game 구독
│   └── SessionService.kt        # 포그라운드 서비스
├── ui/                          # Pairing(QR) / Driving(한 줄) / Parked(게임 상태 렌더)
└── gleo/                        # schema.json 함수 ↔ BroadcastReceiver   ← 테스트 있음
```

## 왜 Firebase SDK가 아니라 REST인가

Pleos 에뮬레이터에 Google Play services가 있는지 문서에 없다. REST + SSE는 OkHttp만 있으면 되고, 선례(핸들온)가 같은 방식으로 Supabase에 붙여 동작을 확인했다. `google-services.json`도 필요 없다. 1초에 PUT 1회, SSE 연결 1개라 CPU 5% 기준에도 여유가 있다.

## 권한

읽기 권한만. `CONTROL_CAR_*`, `PRIVATE_*` 는 **절대 선언하지 않는다.** manifest 주석에 각 권한이 어떤 신호를 위한 것인지 적혀 있다.

## 검증 결과 반영 위치

| 검증 # | 코드 |
| --- | --- |
| 1, 2 Wiper·Light | `VehicleSignalReader.start()` TODO |
| 3 NaviHelper ETA | `SessionManager.etaSec` 채우는 리더 추가 |
| 4 Odometer 해상도 | `SignalDerivation` 이 자동 폴백. 해상도만 `docs/verification.md` 에 기록 |
| 6 CarUxRestrictions | `SessionManager.screen` 의 기어 P 판정을 교체 |
| 7 Gleo | `GleoReceiver.RESPONSE_ACTION` 포맷 확인 |
| 8 Seat 반전 | `SeatPolarity.SDK_OCCUPIED` |

## Virtual Console 로 신호 주입

```bash
adb forward tcp:8088 tcp:8088
curl -X POST "http://127.0.0.1:8088/browser/session?client=dev"        # 하트비트 (1초마다, 없으면 emulator_inactive)
curl -X PUT  "http://127.0.0.1:8088/vehicle/gear?gear=Drive"
curl -X PUT  "http://127.0.0.1:8088/vehicle/controls?speed=80&accelerator=30&brake=0&steering=0"
curl -X PUT  "http://127.0.0.1:8088/vehicle/seat?area=rear_right&kind=occupied&value=true"
```

`scripts/` 의 시나리오가 이걸 자동으로 한다. 와이퍼·전조등 엔드포인트는 브라우저 `http://127.0.0.1:8088/` 에서 조작하며 Network 탭으로 확인해 `scripts/vc.sh` 에 추가한다.
