# 로컬 Firebase 폰·Pleos 검증

실제 프로젝트의 요금제/설정을 변경하지 않고 `demo-allo-auth`의 Auth, callable Functions, RTDB 및 보안 규칙을 사용한다. 샘플 획득 기록은 격리된 폰 저장소에 보존하며 Firebase 응답을 합성하지 않는다.

## 서버

`firebase/functions`에서 `npm ci`, JDK21과 Firebase CLI를 준비한다. `scripts/firebase_local.sh`는 Auth 9099, Functions 5001, DB 9000을 실행하고 `firebase/.emulator-data/`에 인증·DB 상태를 보존한다. 해당 디렉터리는 Git에서 제외한다. 서버 재시작 시 이 상태를 유지해야 앱의 저장된 로컬 인증과 일치한다. 테스트는 `firebase/`에서 `firebase emulators:exec --only auth,database,functions --project demo-allo-auth 'node --test tests/session-auth.test.mjs'`로 실행한다.

## 차량

ignored `car/local.properties`에 `ALLO_FIREBASE_EMULATOR=true`를 설정한다. debug에서만 고정 demo 프로젝트와 Android 에뮬레이터 호스트 `10.0.2.2`를 사용하며 실제 프로젝트/API key를 사용하지 않는다. release는 이 플래그가 false다. Auth refresh token과 Keystore alias는 운영용과 구분한다.

설정 변경 후에는 반드시 `./car/gradlew -p car clean :app:assembleDebug --no-build-cache`로 전체 빌드한다. Kotlin 증분 캐시에 이전 BuildConfig 상수가 남아 이전 서버를 바라보는 현상을 실기에서 확인했다. 단순 assembleDebug만으로 확인하지 않는다.

## 폰

`phone/`에서 `flutter run -t lib/main_local_firebase.dart -d <phone-emulator>`를 실행한다. debug 전용이며 별도 named FirebaseApp과 고정 demo 프로젝트를 사용한다. 기본 Firebase 인증·도감·페어링 저장소는 건드리지 않는다. 도감·낚시·페어링은 일반 저장소 구현을 사용하되 `local.firebase.` 키로 격리해 재실행 후에도 유지한다. 최초 3종의 샘플 획득 기록을 한 번만 저장하며 실제 여행 기록이 아님을 표시한다. named 로컬 Auth는 재실행에 유지된다. Android callable SDK의 IID 초기화 의존성을 피하기 위해 이 debug 진입점만 고정 에뮬레이터 URL에 callable 프로토콜로 요청하며, 동일 Auth SDK의 ID token을 전달한다. 서버의 인증·권한 검사는 그대로 실행된다. 운영 진입점은 기존 callable SDK를 유지한다.

차량 QR의 세션 ID/코드를 폰의 기존 입력 화면에 입력하여 연결한다. 도감 → 보유 친구 상세 → 획득 기록의 ‘이 친구와 차량에서 함께하기’를 선택하면 실제 GameController가 RTDB에 game을 발행하고 차량 앱이 구독한다. 차량 주차 홈의 이야기 탭에서 해당 친구의 질문 답변을 확인한다.

## 한계

이 경로는 로컬 전송/인증/권한/상태 동기화 검증이다. 실제 Firebase 프로젝트·배포·요금제·실차와 모델 생성 품질 검증은 포함하지 않는다. emulator 데이터를 삭제한 경우 앱 전체 데이터를 지우지 말고 로컬 인증 상태와 서버 스냅샷을 함께 복구한다.

## 확인 결과 (2026-11-12)

- origin/dev `8a094f3` 최신 상태 확인 후 모바일 재빌드/재설치.
- 폰 Auth → joinVehicleSession 인증 성공 → RTDB paired 및 companion 발행 → Pleos 선택 친구 표시 확인.
- 차량 단위 테스트 272개, 폰 테스트 311개 통과. 로컬 진입점 분석 오류 없음.
- Firebase Auth/Functions/RTDB 권한 계약 테스트 20개 통과.
