# 낚시 로컬 모의 연동

Firebase 설정이 없는 환경에서 두 Android 에뮬레이터를 연결한다. 전송과 P/UX 신호만 모의하며 폰의 GameController/FishingController와 별도 SharedPreferences 저장을 사용한다. 기존 도감/낚시/페어링 키는 변경하지 않는다.

1. 저장소 루트에서 `python3 scripts/local_fishing_bridge.py` (로컬 8765 포트)
2. 폰: phone 폴더에서 `flutter build apk --debug -t lib/main_local_fishing.dart --target-platform android-arm64` 후 emulator-5556에 설치. `ai.allo.allo_phone/.MainActivity` 실행
3. 차량: car 폴더에서 `./gradlew :preview:assembleDebug -PincludePreview=true` 후 emulator-5554에 설치. `adb -s emulator-5554 shell am start -n ai.allo.preview/.PreviewActivity --ez localDemo true`
4. 폰 도감에서 친구 선택 → 상세를 아래로 스크롤 → ‘이 친구와 차량에서 함께하기’
5. 차량의 ‘낚시 시작’ → 두 앱을 활성 상태로 두고 유효 시간 60초 대기 → 폰/차량의 저장된 관찰 기록 확인
6. 다른 친구도 같은 방법으로 선택. 개체별 진행과 보상 보존. 앱 재실행 시 선택 개체와 저장 결과 복원, 진행은 수동 재개.

샘플 친구와 데모 보상만 별도 로컬 키에 보관한다. 실제 Firebase, Pleos SDK/P·UX 신호, 실차 성능 검증은 아니다. 폰의 원래 main.dart는 이 모드를 선택하지 않는다.

## 검증 결과 (2026-11-11)

일반 Android 에뮬레이터 두 대에서 길싹이 선택 → 차량 낚시 시작 → 실제 시간 60초 → 관찰 기록 1건 저장 → 폰 강제 종료·재실행 후 1건과 다음 회차 진행 10.812초를 paused 상태로 복원했다. 폰과 차량 표시가 일치했다. 저장 격리 테스트 1개 및 양쪽 debug 빌드가 통과했다. 샘플 6종 전체 왕복이나 실제 Firebase/Pleos를 검증한 결과는 아니다.

HTTP 서버는 Content-Length가 있는 JSON 객체 요청을 받는다. 폰은 UTF-8 바이트 길이를 명시하며 차량은 필수 version 기본값까지 직렬화한다. 서버는 메모리 전송만 담당하고 재시작 시 전송 상태는 초기화된다. 관찰 기록은 폰 앱의 별도 로컬 프로필에 남는다. 앱 데이터 삭제/제거 시 해당 기록도 지워진다.

## 실기 통합 검증 대기

- 실제 Firebase 설정·보안 규칙 및 폰↔차량 왕복/재연결
- Pleos P/D·UX 제한 전환 지연, 앱 비활성·잠금·프로세스 종료
- 저장 실패/재시도·전원 단절 내구성, 중복·지연 요청, 개체 선택/폰 이동/보상 경합
- 실제 화면 크기·내비 공존·시인성·애니메이션 성능과 허용 여부

상세 기기 체크리스트와 캡처는 로컬 TODO에 유지하며 Git에 포함하지 않는다.
