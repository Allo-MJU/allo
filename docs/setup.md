# 개발 환경 초기 세팅 — 차량 앱 (A)

macOS(Apple Silicon) 기준. 2026-11-03 에 처음부터 따라 해서 확인한 순서다.
끝나면 Pleos 에뮬레이터 위에서 공식 샘플앱이 뜨고, `car/` 단위 테스트가 통과한다.

## 0. 요약

| 단계 | 결과 |
| --- | --- |
| 1. JDK 17 | `/opt/homebrew/opt/openjdk@17` |
| 2. Android Studio + SDK Platform 35 | `~/Library/Android/sdk` |
| 3. `car/` 빌드 · 테스트 | `testDebugUnitTest` · `assembleDebug` 통과 |
| 4. Pleos Playground 프로젝트 | Vehicle State · NaviHelper "사용 가능" |
| 5. Pleos Connect Emulator 2.1.0 | `emulator-5554` (API 34, `crp_avd_arm64`) |
| 6. 공식 샘플앱 | 에뮬레이터에 설치 · `VehicleApiExplorer` 사용 가능 |

## 1. JDK 17

```bash
brew install openjdk@17
```

- 다른 JDK(예: 21)가 이미 있으면 "not linked" 경고가 뜬다. **링크하지 않아도 된다.** 빌드할 때만 `JAVA_HOME` 으로 17 을 지정한다
- Android Studio 번들 JBR(25)은 Gradle 8.10.2 를 못 돌린다. Android Studio 에서 빌드하려면 Settings → Build, Execution, Deployment → Build Tools → Gradle → **Gradle JDK** 를 17 경로로 바꾼다
- `car/gradle.properties` 에 `org.gradle.java.home` 을 넣지 않는다 (git 추적 파일, 사람마다 경로가 다름)

```
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

## 2. Android Studio + SDK

```bash
brew install --cask android-studio
```

1. Android Studio 첫 실행 → Setup Wizard **Standard** → `~/Library/Android/sdk` 생성
2. SDK Manager → SDK Platforms → **Android 15.0 · API 35** (Android SDK Platform 35) 체크

> API 35 는 **빌드용**(`compileSdk = 35`), 에뮬레이터는 **실행용** API 34 다. 둘은 다른 것이고 둘 다 필요하다. Android 15 아래의 System Image 들은 받지 않는다.

## 3. `car/` 빌드 · 테스트

```bash
cd car
cp local.properties.example local.properties
# sdk.dir=/Users/<you>/Library/Android/sdk 로 고치고, ALLO_DB_URL 은 C 에게 받는다 (테스트엔 불필요)

JAVA_HOME=<jdk17> ./gradlew testDebugUnitTest assembleDebug
```

- `SDK location not found` → `local.properties` 의 `sdk.dir` 누락
- Pleos Maven(`nexus-playground.pleos.ai`)은 **인증 없이** 받아진다
- `AaosPropertyReader` 의 deprecated 경고 3건은 무시해도 된다

## 4. Pleos Playground 프로젝트

[pleos.ai/playground](https://pleos.ai/playground) → 프로젝트 생성

| 항목 | 값 |
| --- | --- |
| 프로젝트명 | `allo` |
| 개발사명 | `team allo` (⚠️ 실명·소속 금지) |
| 카테고리 | 키즈 |

- Vehicle State 11개 · NaviHelper 2개는 생성 직후 이미 "사용 가능". 별도 신청 없음
- TextToSpeech · SpeechToText 는 "Coming Soon" (자세한 건 `verification.md`)

## 5. Pleos Connect Emulator 2.1.0

공식 문서: [Setting up the development environment](https://document.pleos.ai/en/docs/connect/guide/getting-started/application-development/setup-connect-sdk-emulator)

### 5-1. 시스템 이미지

1. SDK Manager → **SDK Update Sites** 탭 → **+**
   - Name: `Pleos Connect System Image`
   - URL (macOS): `https://nexus-playground.pleos.ai/repository/raw-releases/connect-avd/2.x/crp-arm64-sys-img.xml`
   - Use Authentication: **끔**
2. ⚠️ 작은 창의 OK 다음에 **바깥 Settings 창의 Apply 를 반드시 누른다.** 안 누르면 저장되지 않고(`~/.android/repositories.cfg` 가 안 생김) 이미지가 목록에 나오지 않는다
3. **SDK Platforms** 탭 → **Show Package Details** 켬 → Android 14.0 맨 아래 **`Pleos Connect v2.1.0 APIs arm64 System Image`** 하나만 체크
4. 42dot SDK 라이선스 → Accept. (개인 자격으로 동의)
5. Android Studio 재시작 — 하드웨어 프로필이 재시작 후에 나타난다

### 5-2. AVD

1. Device Manager → **Create device**
2. Form Factor **Automotive** → **Pleos Connect v2.1.0** (OEM 42dot) → Next
3. ⚠️ 시스템 이미지 기본 선택이 **API 35 · Android Automotive with Google APIs** 로 잡힌다. **이걸로 만들지 않는다** (Vehicle 서비스 없음, 1.3GB 추가 다운로드)
   - API 드롭다운 → **API 34**
   - Services 필터를 전체로 (안 보이면 **Show unsupported system images** 켬)
   - **Pleos Connect v2.1.0 APIs** 선택 — 다운로드 아이콘이 없어야 정상
4. Additional settings → Default boot **Cold**, RAM **4 GB** → Finish

### 5-3. 확인

```bash
~/Library/Android/sdk/platform-tools/adb devices -l
# emulator-5554  device product:crp_avd_arm64 model:Car_on_arm64_emulator
```

일반 폰 에뮬레이터를 같이 켜 두면 Gradle 이 그쪽에 설치할 수 있으니 Pleos 에뮬레이터만 띄운다.

## 6. 공식 샘플앱 (`VehicleApiExplorer`)

검증 8개에 쓰는 도구. allo 레포 **밖**에 clone 한다.

```bash
git clone https://github.com/Pleos-Playground/pleos-sample-vehicle-app.git
cd pleos-sample-vehicle-app
printf 'sdk.dir=%s/Library/Android/sdk\n' "$HOME" > local.properties
```

샘플앱은 **그대로는 빌드되지 않는다.** 두 군데를 손본다.

| 증상 | 원인 | 조치 |
| --- | --- | --- |
| `permission denied: ./gradlew` | 실행 권한 없이 커밋돼 있음 | `sh ./gradlew ...` 로 실행 |
| `Could not find ai.pleos.playground:Vehicle:2.3.1` | Maven 에 2.3.1 없음 (2.0.3 · 2.3.2 만) | `gradle/libs.versions.toml` 의 `vehicleSdk` 를 `"2.3.2"` 로 |

```bash
JAVA_HOME=<jdk17> sh ./gradlew installDebug      # 에뮬레이터가 켜져 있어야 함
```

- `SDK XML version 4` 경고는 무시
- ⚠️ 샘플 manifest 는 `CONTROL_CAR_*` 를 전부 선언한다. **allo 로 복사하지 않는다**

## 다음

`docs/verification.md` 의 검증 8개. 순서는 #5 INTERNET → #1·#2 Wiper·Light → #8·#4 → #7·#6 → #3.
