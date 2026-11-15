# 고정 스토리 교육 동행 구현 확인

2026-11-14 · `feat/unity-phone-app` 작업 트리

## 구현 범위

- 알/소유 캐릭터 대상별 7종 공통 돌봄 의도와 Unity 연출.
- 소유 캐릭터 선택, 고정 장면의 다시 듣기·다음 이야기, 텍스트/음성 질문, 음소거.
- 개체·실제/데모 프로필별 로컬 진도. 대화는 현재 세션 메모리만 사용.
- 별도 인증 교육 API와 서버 카탈로그 기반 페르소나·학습 자료 구성.
- 대표 콘텐츠: 길싹이의 작은 정원 3장면. 콘텐츠는 `implementation-sample-awaiting-human-review`이며 전체 캐릭터 스토리 제작 완료를 뜻하지 않음.

## 확인한 범위

- 서버: `/tmp/allo-learning-venv/bin/python -m unittest discover -s server/affinity/tests -q` — 35개 통과.
- Android: `phone/android`에서 Gradle `:app:compileDebugKotlin --offline` — BUILD SUCCESSFUL.
- Flutter: `flutter test` — 최종 425개 통과.
- Flutter 변경 범위 targeted analyze — 문제 없음. 전체 analyze는 기존 `app.dart:191` 경고 1개와 core 정보 2개가 남아 exit 1. 이 기능과 무관한 기존 항목은 수정하지 않음.
- Unity: `scripts/unity_test.sh` — 최종 EditMode 135개 통과.
- `git diff --check` — 공백 오류 없음.
- 독립 검토에서 발견한 음성 대화 문맥 유실과 음성 인식 이후 응답 대기 중 백그라운드 취소 문제를 수정하고 회귀 테스트 통과.
- 테스트의 초기화 대기는 ready 이벤트와 제한시간을 사용하고, widget 테스트 간 추가 카탈로그 asset 캐시를 비워 비동기 테스트 경계를 분리함.

## 실제 기기·모델 확인이 남은 부분

- 이번 교육 대화 API의 실제 모델 응답 품질·사실 준수·페르소나 일관성을 실제 제공자 호출로 확인하지 않음. 기존 알 감정 판정의 과거 실호출 결과와 구분함.
- Android TTS의 한국어/혼합 영어 발음, 외부 음성 인식 Activity 동작은 실제 기기 확인 필요.
- 기존 외부 RecognizerIntent는 인식 화면과 Home 이동을 Activity 정지 신호만으로 구분할 수 없음. 대상·화면·프로필·종료 검증과 입력 시간 제한은 적용하지만, 음성 인식 도중 Home에 갔다가 돌아오는 경우의 취소는 보장하지 않음.
- Unity 소스 테스트·Editor 화면 확인과 Android 내보내기/APK 설치는 별개. 이번 작업에서 새 APK 배포나 원격 서버 배포를 수행하지 않음.

## 화면 확인 자료

Unity Editor의 작성된 상태 스냅샷으로 Camera+UGUI를 렌더했다. 1600×720과 1024×720에서 알, 선택한 친구의 이야기, 대화창 아래쪽, 부화 후 친구 선택창을 확인했다. 실제 모델 응답·Android 키보드/TTS·실행 중 캐릭터 cast/연출을 촬영한 증거는 아니다.

- [알 돌봄 1024](../work-results/unity-phone/companion-learning/egg-1024.png)
- [이야기 1024](../work-results/unity-phone/companion-learning/companion-1024.png)
- [대화 입력 아래쪽 1024](../work-results/unity-phone/companion-learning/companion-chat-1024.png)
- [부화 후 친구 선택 1024](../work-results/unity-phone/companion-learning/picker-1024.png)
- 같은 디렉터리에 1600 버전 포함.
