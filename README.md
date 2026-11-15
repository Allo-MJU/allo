![ALLO — 초록 언덕과 여행길 위의 알로 친구](docs/assets/allo-readme-banner.png)

# 알로 ALLO

**차 안의 시간을, 친구와 함께하는 모험으로.**

알로는 뒷자리 아이가 자기 폰으로 알을 돌보고, 여행에서 만난 친구를 모으는 차량 연동 게임입니다. Pleos 앱이 주행 신호를 전달하면 폰에서는 알이 자라고, 깨어난 친구와 대화하거나 마을을 가꿀 수 있습니다.

현대자동차그룹 차량용 앱 개발 공모전 출품작 · Pleos Connect

[APK 다운로드](https://github.com/Pleos-Allo/allo/releases/tag/v0.1.0-contest-20261115) · [실행 방법](#실행-방법) · [개발 환경](#개발-환경) · [상세 문서](#상세-문서)

## APK 다운로드

설치할 기기에 맞는 APK를 [GitHub Release](https://github.com/Pleos-Allo/allo/releases/tag/v0.1.0-contest-20261115)에서 내려받습니다.

| 앱 | 다운로드 | 설치 환경 |
| --- | --- | --- |
| 아이 폰 | [team-allo_ALLO-Phone_release.apk](https://github.com/Pleos-Allo/allo/releases/download/v0.1.0-contest-20261115/team-allo_ALLO-Phone_release.apk) | Android ARM64 · API 24 이상 |
| Pleos 차량 | [team-allo_ALLO-Pleos_release.apk](https://github.com/Pleos-Allo/allo/releases/download/v0.1.0-contest-20261115/team-allo_ALLO-Pleos_release.apk) | Pleos Connect · API 28 이상 |
| 전체 묶음 | [APK 두 개와 설치 안내 ZIP](https://github.com/Pleos-Allo/allo/releases/download/v0.1.0-contest-20261115/team-allo_APK_release_20261115.zip) | 설치 안내·빌드 기록·SHA-256 포함 |

배포 버전은 **0.1.0(1)**이며, APK의 소스 기준은 [`8596105`](https://github.com/Pleos-Allo/allo/commit/85961059c61cd58de3164580fa9be519b15b54d2)입니다. 이후 README·배너 변경과 구분할 수 있도록 릴리스 태그에 빌드 기준을 고정했습니다.

## 여행에서 하는 일

- **알 돌보기** — 주행에 맞춰 알을 키우고, 차 안에서 쓰다듬거나 자리를 옮기며 돌봅니다.
- **친구와 동행하기** — 깨어난 친구와 대화하고, 함께할 친구를 선택합니다.
- **우리 마을 가꾸기** — 모은 친구를 마을에 배치하고 작업장·주방·훈련장을 이용합니다.
- **도감과 가방 채우기** — 만난 친구와 모은 아이템을 펼친 책 형태의 화면에서 살펴봅니다.
- **이야기와 상상 탐험** — 창밖 이야기를 듣고 바다 탐험·탐험 노트·친구 부탁을 이어갑니다.

폰의 차 안 화면은 Unity 3D, 마을은 2D로 구성했습니다. AI 대화·학습 등 서버를 사용하는 기능은 해당 API와 실행 설정이 필요합니다.

## 실행 방법

### APK 설치

```bash
adb -s <폰_기기_ID> install -r team-allo_ALLO-Phone_release.apk
adb -s <Pleos_기기_ID> install -r team-allo_ALLO-Pleos_release.apk
```

1. Pleos에서 ALLO를 실행해 연결 QR을 띄웁니다.
2. 폰에서 ALLO의 **연결하기**를 누르고 QR을 스캔합니다. 직접 입력할 때는 차량 화면의 **세션 ID와 연결 코드**를 함께 사용합니다.
3. 연결 후 폰에서 알과 친구를 만나봅니다. 인터넷 연결이 필요합니다.

배포 APK에는 기존 Firebase·AI 서버 연결 설정을 포함했습니다. 차량 cloud TTS gateway는 미구성이며 기존 패키지·Pleos 음성 경로를 사용합니다.

### 확인한 환경

| 항목 | 환경·결과 |
| --- | --- |
| 폰 | Android API 36 ARM64 에뮬레이터 · 업데이트 설치, cold launch, Unity 마을 화면 확인 |
| 차량 | Pleos Connect Emulator **v2.1.0** · Android 14/API 34 · ARM64 |
| Pleos 화면 | **2560 × 1440**, 12.8인치, 160dpi(mdpi) |
| 차량 실행 | 설치, cold launch, 연결 QR 화면 확인 |
| 배포 전 테스트 | Flutter 622개 · 공통 core 109개 · Unity EditMode 377개 · 차량 release 403개 통과 |
| 빌드·서명 | 두 앱 모두 release · 기존 Android Debug 키 서명 · `debuggable=false` |

위 결과는 2026-11-15 배포 APK의 검증 기록입니다. 실물 폰·실차, 두 앱의 실제 페어링과 주행 왕복, 모든 대응 서버 기능의 배포 상태까지 검증한 결과는 아닙니다. 상세 기록은 릴리스의 `BUILD_INFO.json`을 참고하세요.

## 구성

```text
Pleos 차량 앱 ── 주행 신호 ──▶ Firebase RTDB ◀── 게임 상태 ── 폰 앱
                                │                     Flutter + Unity
                         세션 인증·참여 권한

폰 앱 ── 돌봄·대화·학습 요청 ──▶ AI API 서버
```

| 경로 | 역할 | 기술 |
| --- | --- | --- |
| [`car/`](car/) | 차량 신호 수집, 차량 화면, 내비·음성 연동 | Kotlin · Jetpack Compose · Pleos SDK · AAOS |
| [`phone/`](phone/) | 연결, 게임 진행, 로컬 저장, Unity 연결 | Flutter · Dart · Firebase |
| [`unity/allo_explore/`](unity/allo_explore/) | 3D 차 안, 2D 마을, 도감·가방과 상호작용 | Unity · C# |
| [`phone/packages/allo_core/`](phone/packages/allo_core/) | 알 성장·부화·수집 판정 | 순수 Dart |
| [`firebase/`](firebase/) | 세션 함수와 Realtime Database 권한 규칙 | Firebase Auth · Functions · RTDB |
| [`server/`](server/) | 돌봄·대화·학습 API, 음성 서비스 | Python |
| [`data/`](data/) | 캐릭터·여행·학습 콘텐츠 | JSON |

게임 판정과 진행 저장은 폰이 담당하고, 차량 앱은 주행 신호를 전달하고 게임 상태를 표시합니다. 실제 연결에는 Firebase 익명 인증과 세션 참여 권한을 사용합니다. 데이터 처리 범위와 서버 설정은 [Firebase 안내](firebase/README.md)와 [AI API 안내](server/affinity/README.md)를 참고하세요.

## 개발 환경

### 폰 앱 · 차 없이 실행

Flutter와 Android SDK, **Unity 6000.0.85f2 및 Android Build Support**가 필요합니다. 배포 폰 APK 빌드에 사용한 Flutter는 **3.47.9**입니다.

```bash
git clone https://github.com/Pleos-Allo/allo.git
cd allo
bash scripts/export_unity.sh
cd phone
flutter pub get
flutter run --dart-define=FEED=fake --dart-define=EXPLORE_UNITY=true --dart-define=UNITY_APP=true
```

`FEED=fake`는 실제 차량 신호를 대신하는 체험용 주행입니다. Unity 내보내기를 먼저 실행해야 현재 Unity 화면을 빌드에 포함할 수 있습니다.

실제 Firebase 연결은 `phone/config/firebase.example.json`을 `firebase.local.json`으로 복사해 값을 채우고 `--dart-define-from-file=config/firebase.local.json`으로 주입합니다. 같은 프로젝트의 익명 인증·서버 함수·DB 규칙도 준비해야 합니다. 세부 설정은 [폰 앱 안내](phone/README.md)와 [Firebase 안내](firebase/README.md)에 있습니다.

### 차량 앱

Android SDK Platform 35, **JDK 17**, Pleos Connect 개발 환경이 필요합니다.

```bash
cd car
cp local.properties.example local.properties
# local.properties에 Android SDK 경로와 Firebase 설정을 채웁니다.
JAVA_HOME=/path/to/jdk-17 ./gradlew assembleRelease
```

결과는 `car/app/build/outputs/apk/release/app-release.apk`입니다. 설정값과 키는 Git에 올리지 않습니다. 자세한 설정은 [차량 앱 안내](car/README.md)를 참고하세요.

### 테스트

```bash
(cd phone && flutter test)
(cd phone/packages/allo_core && dart pub get && dart test)
bash scripts/unity_test.sh
(cd car && JAVA_HOME=/path/to/jdk-17 ./gradlew testReleaseUnitTest)
```

## 상세 문서

| 문서 | 내용 |
| --- | --- |
| [서비스 기획](docs/proposal.md) | 문제, 사용자 경험, 서비스 방향 |
| [개발 환경 설정](docs/setup.md) | Pleos SDK와 에뮬레이터 준비 |
| [데이터 계약](docs/schema.md) | 차량·폰 데이터와 세션 구조 |
| [호감도와 부화](docs/affinity-hatching.md) | 알 돌봄과 부화 규칙 |
| [거점 마을](docs/base-camp.md) | 시설과 친구 마을 |
| [바다 탐험 데모](docs/sea-learning-demo.md) | 상상 탐험과 학습 흐름 |
| [검증 기록](docs/verification/) | 기능별 확인 결과와 검증 범위 |

공모전 제출 방법은 [공식 안내](https://appdevchallenge.auto-hmg.io/guide/submission)를 참고하세요. APK와 소스는 위 릴리스에서 함께 확인할 수 있습니다.
