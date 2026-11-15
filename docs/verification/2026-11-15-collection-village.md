# 미수집 친구·여행 간식·마을 표시 선택 검증

2026-11-15. `fix/live-service-integration-20261115`의 `78bf749` 위 로컬 변경이다. 기존 차량 연결 복구, 별도 차량 코너링/카메라 작업과 작업 폴더를 공유한다. 관련 변경만 검토했으며 기존 작업을 되돌리거나 함께 커밋하지 않았다.

## 구현

- 새 부화 결과는 도감에 없는 종만 선택한다. 환경/판정 후보 우선, 소진 시 미수집 종 fallback이다. 기존 중복 기록과 frozen pendingEntry는 보존한다.
- 실제 12종 ID를 모두 모은 뒤의 새 여행마다 기존 `berry_snack` 3개를 거점 음식 재고에 지급한다. 영수증과 재고는 같은 저장으로 확정한다. 마지막 12번째 부화 여행에는 추가 간식을 주지 않는다.
- 실제/체험 여행 재연결·컨트롤러 재생성·저장 실패 재시도와 Unity 테스트 연결 중복을 회귀 검증했다. 완료 도감을 가진 기존 미완료 알은 해당 여행의 종료 상태로 저장해 다음 여행의 간식 지급을 영구 차단하지 않게 했다.
- 마을의 `마을 친구 선택`에서 소유 개체 0~4마리를 선택·저장·복원한다. 기본 첫4는 설정 전만 적용하며 명시적 빈 선택을 유지한다. 같은 종의 서로 다른 소유 개체를 구분하고 역할/작업/차량 동행 선택은 바꾸지 않는다.
- 선택 저장은 성공 snapshot의 요청 ID 확인 후 닫으며, 저장 실패는 이전 표시와 작성 중 선택을 유지한다. Android 뒤로 가기는 선택창을 먼저 닫는다.
- 저장된 간식 보상은 차 안에서 안내하고 기존 가방의 음식 탭으로 연결한다. 알 실패 후 화면 개선은 [별도 제안](../superpowers/specs/2026-11-15-end-of-care-ux-proposal.md)으로 남겼다.

## 실행 결과

| 검사 | 결과 |
| --- | --- |
| 변경 전 Flutter 전체 | 516 통과 |
| 변경 전 공용 core 전체 | 93 통과 |
| 최종 요청 범위 Flutter 회귀 9개 파일 | 99 통과 |
| 최종 공용 core 전체 | 99 통과 |
| 최종 Unity EditMode 전체 | 299 통과 |
| 변경 Dart 6개 파일 분석 | No issues found |
| git diff --check | 통과 |
| 전체 Flutter 통합 | 533 통과, 1 실패 — 아래 동시 작업 항목 |

전체 Flutter의 실패는 `test/fake_route_test.dart`의 `route 메시지`다. 별도 동시 작업이 `explore_messages.dart`의 JSON에 `cornering:null`을 추가했으나 해당 테스트는 이전 JSON 문자열을 기대한다. 이번 수집/선택 변경 파일이 아니므로 임의 수정하지 않았다. 요청 범위의 마지막 재검증은 위9개 파일99개 모두 통과했다.

실행 로그:

- `/tmp/allo-collection-scoped-final.log`
- `/tmp/allo-collection-final-core.log`
- `/tmp/allo-collection-final-flutter.log`
- `/tmp/allo-collection-final-unity.xml`, `/tmp/allo-collection-final-unity.log`
- `/tmp/allo-collection-analyze.log`

## TDD와 독립 검토

미수집/영수증/실패 재시도 회귀와 Flutter 선택 회귀를 먼저 실패 확인 후 구현했다. Unity 선택 UI는 새 테스트3개 실패를 확인한 뒤 구현했다(`/tmp/allo-collection-village-red.xml`). 간식 안내는 패널 누락 실패를 확인했고(`/tmp/allo-collection-reward-red.xml`), 뒤로 가기는 선택창이 남는 실패를 확인한 뒤 수정했다(`/tmp/allo-collection-back-red.xml`). 최종 Unity 전체에서 모두 통과했다.

독립 검토에서 찾은 체험 보상 중복, 기존 알 교착, 보상 여행의 캠프 주행 누락과 실행되지 않던 테스트를 수정하고 재검토했다. 도감 읽기 실패가 차량의 unknown 요약 발행을 막던 전체 테스트 회귀도 원래 실패를 확인한 뒤 고쳤다.

## 화면 확인과 범위

[실제 Unity PlayMode 캡처](../work-results/unity-phone/village-selection-2026-11-15/README.md)를 1600×720/1024×576에서 검토했다. 6개체 synthetic AppState 입력이며 설치 APK나 실제 소유 데이터 촬영은 아니다. 임시 캡처 Editor 스크립트는 제거했다.

APK/Unity export 재빌드, 설치, 배포, 커밋·푸시는 하지 않았다. 짧은 여행 시간 제한, 사진 업로드 시간 유예, 작업 전 시간·효과 안내는 이 요청에서 변경하지 않았다.
