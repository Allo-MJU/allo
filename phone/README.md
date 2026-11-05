# 알로 폰 앱 (Flutter)

아이가 보는 화면. 품기 → 부화 → 동행 → 도감. 판정은 `packages/allo_core` 가 한다.

## 시작

```bash
flutter pub get
flutter run --dart-define=FEED=fake --dart-define=SCENARIO=rainy_highway   # 차 없이
```

Firebase 연결은 `flutterfire configure` 로 `lib/firebase_options.dart` 를 만들고(git 미추적) `main.dart` 의 `Firebase.initializeApp` 주석을 푼다.

## 구조

```
lib/
├── main.dart                 # FEED=fake|firebase 선택
├── app.dart                  # 라우팅 (go_router)
├── feed/
│   ├── vehicle_feed.dart     # 추상 인터페이스 — 화면은 이것만 본다
│   ├── fake_feed.dart        # ⭐ 시나리오 4종. Day 1 부터 이걸로
│   └── firebase_feed.dart    # RTDB 구현
├── game/game_controller.dart # 세션 상태 머신. allo_core 호출, /game 발행
├── screens/                  # pairing / incubating / hatching(연출 집중) / companion / dex
└── storage/dex_store.dart    # 도감·이어하기 거리. 로컬 전용
```

## 시나리오 (fake)

| 이름 | 태그 | 운전 | 기대 결과 |
| --- | --- | --- | --- |
| `rainy_highway` | rain, highway | 부드러움 | water tier 3 (Tide Keeper) |
| `tunnel_rough` | tunnel | 급제동 반복 | dark tier 1 |
| `clear` | 없음, ETA 600초 | 부드러움 | normal tier 3, ETA 모드 |
| `rough` | 없음 | 급제동 반복 | normal tier 1 |

기본 실행은 Fake 모드다. `체험 시작`으로 품기 → 부화 → 동행 → 도감을 확인한다.
`timeScale` 기본 20에서 작은 알은 rainy_highway 약 10초, clear(ETA) 약 16초에 부화한다.
감싸기는 탭, 노래는 길게 누르기로 돌봄 횟수를 올린다. `품기 저장하고 나가기`는 거리를 기기에 저장한다.
Android/iOS 플랫폼 폴더는 저장소에 포함되어 있다. APK 검증은 `flutter build apk --debug --dart-define=FEED=fake`로 실행한다.

## 연동 시 주의

[PR #8](https://github.com/Allo-MJU/allo/pull/8)에 따라 Firebase에서 `etaSec`와 `envTags` 키가 빠질 수 있다.
기존 `VehicleState.fromJson`의 null/빈 목록 기본값을 유지하고 회귀 테스트로 확인한다.
`/game`의 `hatchAtM`과 `hatchAtSec` 중 하나만 채운다.

Firebase 실연결, QR 스캔, 6자리 코드만으로 세션 찾기, 자동 재연결은 아직 미완료다.
Firebase 모드는 초기화 설정 후 실행하며, 연결 완료 후에만 품기를 시작할 수 있다.
6자리 코드 조회는 현재 스키마에 조회 경로가 없어 C와 계약 협의가 필요하다.
[이슈 #9](https://github.com/Allo-MJU/allo/issues/9)의 `unvisitedRegions`와
`destinationSuggest` payload는 C 승인 대기 중이다. 승인 전 필드는 보내지 않는다.
누락(모름)과 전 지역 방문 완료의 표현을 확정한 후, 로컬 도감에서 지역 태그만 계산해
전송하고 `offered`/`accepted`를 폰 화면에 표시한다. 좌표·도감 원문은 전송하지 않는다.
아트는 임시 아이콘이며, 도감 상세와 동행의 먹이/놀이 동작은 후속 작업이다.

## 검증

```bash
(cd packages/allo_core && dart pub get && dart test)
flutter test
flutter analyze
```

## 개인정보

이름·생년월일·연락처 입력란 없음. 도감은 `shared_preferences` 로컬 저장. 서버엔 세션 동안의 게임 상태만.

## 이어하기 거리와 재개 검증

같은 차량 세션을 재개하면 로컬 기록의 세션 ID와 반영한 누적 거리까지 복원해
새로 늘어난 거리만 더한다. 앱을 재실행해도 같은 기준을 유지한다.
부화할 때도 사용한 거리 위치를 남겨 같은 세션에서 새 알이 즉시 부화하지 않게 한다.
Fake는 구독마다 새 가상 주행이므로 이전 품기 거리와 새 주행 거리를 합산한다.
구버전 저장에는 세션 정보가 없어 저장 거리는 보존하되 첫 신호를 기준점으로 잡는다.
이 경우 저장 후 첫 연결 전까지 달린 거리는 정확히 복원할 수 없다.
서버 스키마와 코어 부화 판정은 바꾸지 않고 폰 로컬 기록만 확장한다.
