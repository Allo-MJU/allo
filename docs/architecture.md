# 알로 아키텍처 · 기술 스택 결정

작성 2026-11-02. 결정 근거는 공개 선례(핸들온·Roadio·SoftRide)와 Pleos 공식 샘플앱 조사.

## 스택

| 영역 | 선택 | 근거 |
| --- | --- | --- |
| 차량 앱 | Kotlin + Jetpack Compose + Pleos Vehicle 2.3.2 / NaviHelper 3.0.5 / TextToSpeech 3.3.1 | Pleos SDK 가 Kotlin 라이브러리라 사실상 유일. 선례 전부 동일 |
| 속도·기어 | AAOS `CarPropertyManager` (`android.car.permission.CAR_SPEED`, `CAR_POWERTRAIN`) | Vehicle SDK 2.3.2 에서 속도 리스너 삭제, Gear 미제공. 핸들온·SoftRide 확인 |
| 차 ↔ 폰 중계 | **Firebase Realtime Database** | 서버 코드 0줄, 1초 스트리밍에 적합 |
| 차량 앱 → Firebase | **REST + SSE (OkHttp)** | Pleos 에뮬레이터의 Google Play services 유무가 문서에 없음. REST 는 그 리스크가 0 이고 google-services.json 도 불필요. 핸들온이 같은 방식(HTTPS)으로 Supabase 연동 확인 |
| 폰 앱 | **Flutter** + FlutterFire | 부화 연출·애니메이션에 강함. iOS/Android 동시. 핸들온 선례 |
| 게임 로직 | 순수 Dart 패키지 `allo_core` | C 가 Flutter 없이 `dart test` 로 개발. 판정이 한 곳에만 존재 |
| 운전자 음성 | Pleos TTS (온디바이스) + Gleo 함수 (`schema.json` + BroadcastReceiver) | Roadio 가 TTS 에뮬레이터 동작 확인. 핸들온이 Gleo 함수 등록 신청 없이 사용 |
| 주행 재현 | Virtual Console HTTP (`localhost:8088`) | 기어·속도·브레이크·조향·좌석 주입 가능. 선례 스크립트 그대로 |

## 데이터 흐름

```
Pleos Vehicle SDK ─┐
AAOS CarProperty ──┼─► SignalDerivation ─► EnvTagger ─► VehicleSnapshot ─PUT 1Hz─► /sessions/{sid}/vehicle
NaviHelper ETA ────┘        (급제동·거리)     (rain/tunnel/…)                              │
                                                                                          ▼ onValue
                                                                              폰 GameController
                                                                                allo_core: RarityEngine · HatchTimer
                                                                                          │ set
차 화면 (Parked) ◄─SSE─ /sessions/{sid}/game ◄──────────────────────────────────────────┘
Gleo / TTS      ◄─SSE─ /sessions/{sid}/events (hatched)
```

- 좌표는 `RegionTagger` 안에서 태그로 바뀌고 밖으로 나가지 않는다
- 도감은 폰 `shared_preferences` 에만 있다

## 선례에서 확인된 제약 (우리 검증 항목에 미치는 영향)

| 발견 | 출처 | 영향 |
| --- | --- | --- |
| 에뮬레이터 내비는 `adb emu geo fix` 로 위치가 안 움직인다 (NMEA 체크섬 오류, 판교 고정) | SoftRide · Roadio | **검증 #3(ETA 갱신) 은 에뮬레이터에서 실패 가능성 높음.** 거리 폴백을 메인 데모 경로로. ETA 모드는 단위 테스트로 증명 |
| 에뮬레이터는 주행 중에도 CarUxRestrictions 글자 제한을 안 건다 | Roadio | 검증 #6 은 에뮬레이터 결과를 그대로 믿지 말고 기어 P 기준 유지 |
| Pleos Connect 에 Android 기본 TTS 엔진 없음 | Roadio | 음성은 반드시 Pleos TTS SDK |
| Gleo 는 `schema.json` 의 `actionCalls[].function.name` 을 action 으로 브로드캐스트, 응답은 `ai.pleos.playground.intent.action.APP_ACTION_RESPONSE` | 핸들온 | `GleoReceiver` 구현 기준. 검증 #7 은 포맷 확인만 |
| 공식 샘플 manifest 는 `CONTROL_CAR_*` 를 전부 선언한다 | 샘플앱 | **복사 금지.** 우리는 읽기 권한만 |
| JDK 17 필요. Android Studio 번들 JBR 25 는 Gradle 8.10.2 를 못 돌린다 | Roadio | Gradle JDK 를 17 로 지정 |
| Virtual Console 은 1초 하트비트(`POST /browser/session`) 없으면 차를 안 움직인다 | 핸들온 · SoftRide | `scripts/vc.sh` 가 처리 |

## 버리지 않은 대안

- **Supabase** — 통계 쿼리가 필요해지면(확장 단계) 검토. 공모전 범위엔 과함
- **폰 웹앱(PWA)** — "QR 찍으면 설치 없이 바로 플레이" 는 부모 폰 빌려쓰기 시나리오에 매력적. Flutter web 빌드로 나중에 시도 가능
