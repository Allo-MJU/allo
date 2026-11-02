# 알로 폰 앱 (Flutter)

아이가 보는 화면. 품기 → 부화 → 동행 → 도감. 판정은 `packages/allo_core` 가 한다.

## 시작

```bash
flutter create . --platforms=android,ios --org ai.allo   # 최초 1회. 플랫폼 폴더 생성
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

`timeScale` 기본 20 이라 10km 알이 약 25초 만에 부화한다.

## 개인정보

이름·생년월일·연락처 입력란 없음. 도감은 `shared_preferences` 로컬 저장. 서버엔 세션 동안의 게임 상태만.
