# 알로 ALLO

> 차가 달린 만큼 알이 자라고, 여행 중간에 깨어나 도착까지 함께 가는 뒷자리 아이용 수집 게임.

현대자동차그룹 차량용 앱 개발 공모전 출품작 · Pleos Connect

포켓몬GO는 속도 제한 때문에 차를 타면 알이 부화하지 않습니다. 알로는 그 규칙을 뒤집어 **차가 달린 거리**로 부화하고, 비 오는 날·터널·고속도로에서만 나오는 종이 있습니다. 아이는 자기 폰으로 플레이하고, 차량 앱은 실제 주행 신호를 게임에 흘려보냅니다.

## 구성

```
[차량 앱 · Pleos]  --vehicle-->  Firebase RTDB  --game-->  [폰 앱 · Flutter]
   센서 · 차 화면 · Gleo 음성                              품기 · 부화 · 동행 · 도감
```

| 디렉터리 | 내용 | 스택 |
| --- | --- | --- |
| [`car/`](./car) | 차량 앱. Vehicle SDK 신호 수집 → Firebase 전송, 정차 시 가족 화면, Gleo 음성 | Kotlin · Compose · Pleos Vehicle SDK 2.3.2 |
| [`phone/`](./phone) | 아이 폰 앱. 품기 → 부화 → 동행 → 도감 | Flutter |
| [`phone/packages/allo_core/`](./phone/packages/allo_core) | 게임 로직. 희귀도 판정, 부화 타이밍. Flutter 비의존 | 순수 Dart + 단위 테스트 |
| [`data/`](./data) | 생물 12종 정의 | JSON |
| [`firebase/`](./firebase) | Realtime Database 보안 규칙 | |
| [`scripts/`](./scripts) | 주행 재현 시나리오, 테스트 데이터 주입 | shell |
| [`art/`](./art) | 도트 원본과 export | |
| [`docs/`](./docs) | 기획서, 개발 계획, 스키마(계약), 검증 기록 | |

## 설계 원칙

- **판정은 폰에서만.** 차량 앱은 신호를 raw로 올리고, 희귀도·부화 계산은 폰이 합니다. 차 화면은 결과를 읽어 표시만 합니다.
- **위치 원본은 차 밖으로 나가지 않습니다.** 차량 앱이 좌표를 `rain`, `tunnel`, `coast` 같은 환경 태그로 바꿔서 보냅니다.
- **아이 계정을 만들지 않습니다.** QR 또는 6자리 코드로 세션만 연결합니다. 도감은 폰 로컬에 저장합니다.
- **읽기 권한만 씁니다.** `CONTROL_CAR_*` 권한은 선언하지 않습니다.
- **확률형 요소 없음.** 희귀도는 돈이 아니라 주행으로만 결정됩니다.

## 시작하기

### 차량 앱

```bash
cd car
# Firebase 콘솔에서 받은 google-services.json 을 car/app/ 에 둡니다 (git 미추적)
JAVA_HOME=/path/to/jdk-17 ./gradlew installDebug
```

Android Studio, SDK Platform 35, JDK 17, Pleos Connect Emulator가 필요합니다. 자세한 내용은 [`car/README.md`](./car/README.md).

### 폰 앱

```bash
cd phone
flutter create . --platforms=android,ios   # 플랫폼 폴더 생성 (최초 1회)
flutter pub get
flutter run --dart-define=FEED=fake        # 차 없이 가짜 신호로 실행
```

### 게임 로직 테스트

```bash
cd phone/packages/allo_core
dart pub get && dart test
```

### 시나리오 주입 (차량 앱 없이 Firebase에 직접)

```bash
export ALLO_DB_URL=https://<project>-default-rtdb.firebaseio.com
scripts/seed_firebase.sh                     # 세션 1건 생성, sessionId 출력
scripts/scenario_rainy_highway.sh <sessionId>
```

## 문서

처음 보는 사람은 [`docs/proposal.md`](./docs/proposal.md) → [`docs/schema.md`](./docs/schema.md) → 자기 파트의 [`docs/roadmap.md`](./docs/roadmap.md) 순서로 읽습니다. `schema.md`는 팀 전체의 계약서입니다.

## 데이터와 개인정보

서버(Firebase)에는 주행 1회 동안의 임시 상태만 남고 24시간 후 만료됩니다. 위도·경도, 아이 이름·생년월일·연락처, 주행 경로, 도감은 서버에 저장하지 않습니다.

## 에셋 출처

(사용한 도트 에셋 팩과 라이선스를 여기에 표기)

## 라이선스

TBD
