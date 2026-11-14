# 차량 연결·직접 대화·행동 메뉴 검증

2026-11-14. `feat/trip-egg-companion-interaction`의 `4d1374b` 기준에 기존 여행 알 기능과 승인된 마을 UI를 통합했다. 이전 이야기/말 걸기 선택 방식은 이번 직접 대화 흐름으로 대체한다.

## 변경 동작

- 미연결 차량은 빈 차량과 `차량 연결하기`에서 시작한다. 실제 Flutter QR 스캐너 또는 직접 입력으로 페어링한다. 취소하면 알을 지급하지 않는다.
- 여행당 한 알, 미부화 알 이어 키우기와 기존 부화·친밀도 규칙을 유지한다. 친구는 도감에서 정확한 소유 개체를 선택해 데리고 온다.
- 단일 `행동` 버튼에서 알 돌보기/친구와 놀기를 구분하고, 선택 또는 바깥 터치로 닫는다. 새 버튼과 메뉴에 매끄러운 둥근 모서리와 은은한 그림자를 적용했다.
- 캐릭터를 누르면 서버 greet/chat에 연결하는 대화창이 열린다. 서버가 페르소나·고정 배경·교육 지식을 소유한다. 앱은 입력·표시·음성을 담당한다.
- 완료 대화 여섯 쌍을 같은 세션에서 유지하고 UI 중단 시 진행 중 응답만 폐기한다. 대상·프로필·연결 변경은 기록을 초기화한다.
- 정식 스토리12종 외 실제 부화 가능 기존6종에도 대화 프로필을 연결했다. 알려지지 않은 출신·사건은 만들지 않았다. 신규 콘텐츠의 사람 검토는 남아 있다.

## 실행 검증

| 검증 | 결과 |
| --- | --- |
| Flutter 전체 | 500/500 |
| 공유 Dart core | 93/93 |
| Unity EditMode 전체 | 220/220 |
| 마을 EventSystem PlayMode | 2/2 |
| Python 서버 전체 | 53/53 |
| QR host 집중 검증 (Flutter 전체에 포함) | 9/9 |
| 로컬 실행기 | 2/2 |
| Dart→로컬 Python HTTP | 프로필18, 작성형48턴, 직접대화36턴, 부화/사진 복구 통과 |

HTTP의 생성 답변은 명시적인 synthetic test provider다. 실제 AI 모델 검증으로 보지 않는다. 변경 파일 Dart 분석은 정상이며 전체 분석의 기존 경고1개·안내2개는 그대로다.

Unity export 및 debug APK 빌드 성공(최종 APK 빌드79.8초). APK SHA256: `45e99ca25f52a03023de8e072f8b93017548a536497978204b2a577e8928a11f`. APK의 대화 manifest는18개 ID 메타데이터이며 페르소나·스토리 본문·지식·API 키를 담지 않는다.

## Android API36 실행 관찰

데이터 삭제 없이 설치했다. 빈 차량 → 연결 화면 → Flutter 카메라 진입 → 취소 → Unity 복귀를 관찰했다. 직접 입력은 가상 세션/코드와 fake feed를 사용했으며 실제 차량 인증 성공을 의미하지 않는다.

알과 친구를 함께 표시한 상태에서 `알 쓰다듬기`로 친밀도3을 확인했다. 친구 쓰다듬기 후에도 알 친밀도는3이었다. 최종 행동 버튼/선택창의 매끄러운 모서리를 캡처로 확인했다. 실제 캐릭터 탭으로 대화 입력창과 키 미설정 오류 안내가 열렸다.

[실행 캡처](../work-results/unity-phone/cabin-direct-conversation/)의01~09 이미지와 runtime-checks.json 참고.

## 미검증 범위

실제 OpenAI 키가 없어 생성 대화의 교육 품질·페르소나 일관성·음성 발음은 미검증이다. 키가 없으면 정적 이야기로 대체하지 않고 연결 오류를 표시한다. 실제 차량 광학 QR, Firebase 운영 환경, 물리 기기 카메라·마이크와 원격 배포는 미검증이다. 키 입력 순서는 [로컬 실행 안내](../companion-learning-local-setup.md)를 따른다.

## 로컬 증거

- /tmp/allo-cabin-actions-flutter-final.log
- /tmp/allo-cabin-direct-chat-core.log
- $TMPDIR/allo_unity_editmode.xml
- /tmp/allo-cabin-village-playmode.xml
- /tmp/allo-cabin-direct-chat-http.log
- /tmp/allo-cabin-actions-smooth-export.log
- /tmp/allo-cabin-actions-smooth-apk.log

생성 APK/Unity 라이브러리와 로컬 인증 설정은 소스 변경에 포함하지 않는다.
