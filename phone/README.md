# 알로 폰 앱 (Flutter)

아이가 보는 화면. 품기 → 부화 → 동행 → 도감. 판정은 `packages/allo_core` 가 한다.

## 시작

```bash
flutter pub get
flutter run --dart-define=FEED=fake --dart-define=SCENARIO=rainy_highway   # 차 없이
```

Firebase 연결은 아래 로컬 설정을 주입한다. 초기화가 성공한 뒤에만 차량 연결 화면을 연다.

```bash
cp config/firebase.example.json config/firebase.local.json
# Firebase 콘솔에 등록한 해당 Android/iOS 앱의 설정값과 Realtime Database URL을 채운다.
flutter run --dart-define-from-file=config/firebase.local.json
```

`firebase.local.json`은 Git에서 제외한다. 실제 값은 커밋·로그·채팅에 넣지 않는다.
Android/iOS의 앱 ID는 서로 다르므로 기기 플랫폼에 맞는 등록 앱의 값을 사용한다.
설정 누락·초기화 실패 시 안내 화면에서 체험 모드로 전환할 수 있다.

차량 화면의 QR(`allo://pair?sid=<UUID>&code=<6자리>`)을 스캔하거나 세션 ID와 코드를 직접 입력한다.
카메라 권한이 없으면 설정에서 허용하거나 직접 입력으로 돌아갈 수 있다. QR 이미지·카메라 프레임은 저장하지 않는다.
서버의 세션 생성 시각(24시간 이내)과 코드를 확인하고 페어링 상태·이벤트를 한 번에 기록한 뒤 연결을 완료한다.
연결 성공 시 세션 ID와 코드를 폰 로컬에 저장하고 앱 시작 시 서버에 다시 확인해 재연결한다.
이전 주행의 세션이 만료됐거나 새 세션으로 바뀌면 차량의 새 QR을 스캔해야 한다.
네트워크 오류 때는 저장된 정보를 유지하며, 연결 성공 전에는 품기를 시작할 수 없다.

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

Firebase 초기화·QR·로컬 세션 재연결 코드는 구현했지만 실제 프로젝트 설정으로 차량과 통합 검증하지 않았다.
카메라 실기·권한 거부·앱 재실행과 iOS 실행도 현장 검증이 필요하다.
6자리 코드만으로 세션 찾기는 아직 미구현이다.
6자리 코드 조회는 현재 스키마에 조회 경로가 없어 C와 계약 협의가 필요하다.
[이슈 #9](https://github.com/Allo-MJU/allo/issues/9)의 추천 기준은 현재 기기의 도감에서
지역별 수집 기록이 없는지로 확정됐다(11/4 C 댓글). 실제 방문 여부를 뜻하지 않는다.
`regionCollectionKnown`·`uncollectedRegions`와 부화 전 지역 체류 시간 집계는 조정안이다.
확인 완료 조건, 신호 단절·동률 처리, `destinationSuggest` 성공 의미를 합의하고
`schema.md`에 반영한 뒤 구현한다. 현재는 신규 필드를 보내지 않는다.
좌표·도감 원문은 전송하지 않는다.

도감은 전체 12종과 미획득 힌트, 획득 날짜·환경·지역 상세를 보여준다.
지역이 없는 기존 기록은 미확정으로 표시하며 방문 여부를 추정하지 않는다.
먹이·놀아주기는 동행 중 폰 화면의 반응과 횟수만 변경한다. 등급이나 서버 필드는 바꾸지 않는다.
창밖 문구는 현재 수신한 환경 태그를 따르고, 정보가 없으면 특정 풍경을 단정하지 않는다.
생물 이미지는 `assets/{species.sprite}`에서 읽는다. D 아트 미제공 시 임시 아이콘을 표시한다.

### 실제 연결 검증 (설정·기기 준비 후)

1. 플랫폼에 맞는 `config/firebase.local.json`을 준비하고 Firebase 모드로 실행한다.
2. 차량에서 새 세션을 생성하고 QR 또는 세션 ID+코드를 입력한다.
3. 잘못된 코드·만료 세션은 품기 진입을 막고, 정상 연결은 `meta/paired`와 paired 이벤트를 기록하는지 확인한다.
4. 차량 주행 신호가 품기 진행률에 반영되고 `/game`이 차 화면에 반영되는지 확인한다.
5. 부화·동행·도착 후 앱을 재실행해 도감 유지와 유효 세션 자동 재연결을 확인한다.
6. 카메라 권한 거부 시 직접 입력, 만료 시 새 QR 안내, 오프라인 실패 후 재시도를 확인한다.
   Firebase timeout은 쓰기를 취소하지 않으므로 네트워크 복구 후 늦게 도착하는 paired 이벤트도 확인한다.

실제 Firebase 설정과 차량 연결이 없어 위 통합 항목은 미검증이다.
Android API 36 에뮬레이터에서 Fake 체험 시작→부화→동행 먹이/놀이→도감 상세는 직접 확인했다.

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

## 생물 데이터 패키징

원본은 저장소 루트 `data/species.json`이다. Flutter 에셋에 `../` 경로를 쓰면
Android APK 밖으로 파일이 배치되므로 앱은 `assets/data/species.json` 사본을 읽는다.
원본 변경 후 저장소 루트에서 `cp data/species.json phone/assets/data/species.json`으로 동기화한다.
`species_asset_test.dart`가 원본과 사본의 일치를 검사한다.
Android debug 빌드 후 `python3 tool/verify_apk_assets.py`로 APK 안의 실제 데이터도 검사한다.

## 종료된 차량 세션

연결 전에 차량의 `sessionEnd` 이벤트를 확인해 종료된 세션은 연결하지 않는다.
자동 재연결 시 종료가 확인되면 이전 연결 정보를 지우고 새 QR을 안내한다.
연결 중 종료 이벤트를 받으면 새 품기와 후속 주행 반영을 막고 진행·도감을 저장한다.
저장과 연결 정보 삭제가 성공하면 연결 화면으로 돌아간다. 저장 실패 시 현재 기록을
유지하므로 품기 화면의 저장 버튼 또는 동행의 도착 버튼으로 다시 시도할 수 있다.
`sessionEnd`의 payload가 없는 Firebase 데이터도 처리한다.
일반적인 품기 저장 실패에서는 신호 구독을 재개해 알이 계속 자라도록 한다.
