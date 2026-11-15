# 실서비스 작업본과 바다 탐험 통합 검증

2026-11-15 · PR 대상 `dev`

## 통합 기준

- 바다 탐험·일러스트 작업: `feat/sea-learning-pilot`의 `7315f6f`.
- 실서비스 작업: `fix/live-service-integration-20261115`의 기준 커밋 `78bf749` 및 해당 작업 폴더의 미커밋 구현.
- 커밋 기준은 이미 공통 조상이므로, 미커밋 변경125개 파일을 별도 스냅샷 `770555820b08f25aa303550145d425cb8076e9bd`로 보존한 뒤 Git merge했다. 캡처 전후 파일 내용·모드·목록·HEAD 일치를 확인했다. 원본 작업 폴더와 인덱스는 수정하지 않았다.
- 생성된 iOS xcconfig 두 개와 Podfile, 테스트 중 변경된 것으로 보이는 glow 재질3개와 Sky 재질은 스냅샷에서 제외했다. 비공개 설정·키·APK·Unity export·의존성 생성물도 포함하지 않았다.

## 병합과 보완

차량 연결 복구와 실제/테스트 모드 전환, 미수집 종 우선 획득·수집 완료 여행 간식, 마을 표시0~4개체 선택, 친구별48시간 부탁과 실제 도착 여행 이력, 조향·상대 자이로 시선을 기존 바다 탐험과 합쳤다.

충돌은 Dart 제어 코드와 Unity의 AppState/AppUiViews에서 발생했다. 양쪽 상태 필드·액션·초기화·콜백을 유지하고 아래 경계를 회귀 검증했다.

- 화면 해제 시 바다 진행을 보관하고 노트 요청 세대를 무효화하며, 퀘스트를 비활성화하고 이전 호스트의 늦은 메시지를 거절한다.
- 실제로 열린 퀘스트/마을 선택 UI와 바다 실험의 입력 소유권을 상호 배제한다. 본문 캐시의 `opened` 값만으로 영구 차단하지 않는다.
- 실제 퀘스트 응답 대기 중에는 노트 진입을 막고, 실험 중에는 퀘스트 액션을 거절한다.
- 연결 모드 준비가 기존 탐험 저장 소유권을 빼앗지 않도록 새 `test-connection` 프로필만 별도 저장 키를 사용한다. `default`, `unity-demo-examples` 등 기존 프로필은 `unityApp.story.v1`을 그대로 사용하고 기존 카드를 옮기거나 삭제하지 않는다.
- 저장 큐는 대기 중인 쓰기만 보관하고 완료한 Future를 제거한다. 이전 widget-test async zone의 완료 Future를 재사용해 다음 모드 초기화가 멈추던 경로를 재현 후 수정했다. 실패한 네이티브 쓰기의 마지막 성공 기록과 기존 소유자 쓰기 대기는 유지한다.
- Unity 재렌더 정리는 실행 모드에서 지연 삭제, EditMode에서 즉시 삭제한다. 기존 스크롤·pan 테스트의 알려진 Destroy 오류 기대를 제거하고 실제 동작 검증은 유지했다.

## 통합 소스에서 다시 실행한 결과

| 검사 | 결과 |
| --- | --- |
| Flutter 전체 | **613/613 통과** |
| 공통 Dart core | **109/109 통과** |
| Unity EditMode | **355/355 통과** |
| Unity PlayMode | **5/5 통과** |
| Python API 서버 | **57/57 통과** |
| Firebase Auth/DB/Functions 로컬 에뮬레이터 | **21/21 통과** |
| 차량 debug JVM | **366/366 통과** |
| 차량 release JVM | **366/366 통과** |
| Flutter 분석 | 오류0·경고0, 기존/유입 코드 style info23개 |
| diff 공백 검사 | 통과 |

주요 로그는 `/tmp/allo-live-sea-{flutter-final,core,server,car,firebase,analyze}.log`, Unity 결과는 `artifacts/live-service-merge/{editmode-green,playmode}.xml`이다. 단일 변경 검증과 전체 통합 검증 결과를 혼동하지 않았다.

서버는 기존 `/tmp/allo-learning-venv`로, 차량은 JDK17로 실행했다. Firebase는 Android Studio Java와 캐시된 CLI15.36.0으로 `demo-allo-auth` 프로젝트만 사용했다. Functions 의존성은 기존 로컬 설치를 재사용했고 검증 후 임시 연결은 제거했다. Node26 테스트 호스트와 프로젝트 Node22 runtime 차이는 운영 적용 전 확인 대상이다.

## 운영 적용 경계

이번 작업은 소스 통합과 PR이다. 전체 통합본의 새 Android export/APK·기기 왕복과 운영 배포는 실행하지 않았다. 기존 바다 예시의 실제 Android 검증은 별도 기록이며 이번 전체 통합본의 기기 검증으로 확대 해석하지 않는다.

새 친구 부탁 기능의 운영 적용에는 서버 API·Firebase Functions/rules 배포와 새 앱 검증이 필요하다. 실차 조향 부호·센서 축·NaviHelper 도착 콜백, 실제 AI 품질·음성·아이 대상 가독성은 기존 기능별 검증 한계를 따른다.
