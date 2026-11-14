# 책 UI와 최신 로컬 동행 작업 병합

2026-11-14 사용자 요청으로 `feat/dex-inventory-book`에 최신 로컬 기능을 병합했다.

## 포함한 작업

- 책 도감·가방: `32111d8`.
- `feat/trip-egg-companion-interaction`의 `bfbb867`, `4d1374b`: 여행당 알 지급, 서버 소유 대화, 마을 캐릭터 상세·동행 선택.
- 위 작업본의 미커밋 변경: QR 연결·직접 대화, 알/친구 독립 돌봄, 원형 아이템 선택·방향 던지기·더블 탭 이동, 관련 테스트와 기록.

원래 작업본의 HEAD·실제 index·파일은 수정하지 않았다. 임시 index로 당시 상태를 `0a05dd67f8a10bdeecc02da714f00b1fddff49d7`에 저장했고, `integration/companion-local-snapshot-20261114`로 보존했다. 스냅샷 뒤 원본 작업본의 HEAD·상태 및 포함 파일들의 Git blob hash가 같은지 재확인했다.

다른 오래된 C 작업·지역 기능 계열·문서 제안 브랜치는 이 기능 통합에 넣지 않았다. 원격 push나 dev 브랜치 변경은 하지 않았다.

## 충돌 해결

`AppUiViews.cs`의 동행 버튼 한 곳이 충돌했다. 책 UI의 왼쪽 상세와 `BookButton`을 유지하고, 최신 동행 흐름의 `차 안으로 데리고 오기` 문구를 채택했다. 소유 개체 ID와 `selectCarCompanion` 액션은 유지한다.

최신 작업에서 앱의 StoryOverlay를 제거했으므로 책 캡처 도구는 해당 컴포넌트가 있을 때만 Apply하도록 조정했다. 책 테스트의 버튼 문구도 최신 흐름에 맞췄다. 독립 읽기 전용 병합 리뷰에서 추가 P1/P2 통합 문제는 발견되지 않았다.

## 병합 결과 검증

| 검증 | 결과 |
| --- | --- |
| Unity EditMode 전체 | 245/245 통과 |
| Unity PlayMode 전체 | 3/3 통과 |
| Flutter 전체 | 500/500 통과 |
| 공유 Dart core | 93/93 통과 |
| Python API 서버 | 53/53 통과 |
| 로컬 실행기 | 2/2 통과 |
| 책 UI PlayMode 캡처 | 15개 생성, 스크롤 표시 검증 통과 |

테스트는 모두 병합된 작업본에서 다시 실행했다. API 서버 검증은 테스트 provider를 사용하며 실제 AI 모델 품질 검증이 아니다. 기존 Python 환경에는 Pillow가 없어 원래 작업본의 가상환경 인터프리터를 읽기 전용으로 재사용했다.

증거 로그: `/tmp/allo-merged-edit.xml`, `/tmp/allo-merged-play.xml`, `/tmp/allo-merged-flutter.log`, `/tmp/allo-merged-core.log`, `/tmp/allo-merged-server.log`, `/tmp/allo-merged-book-capture.log`. 화면은 `docs/work-results/unity-phone/book-ui/`에 반영했다.

이번 병합 결과를 APK로 새로 빌드·설치하거나 실제 차량에서 실행하지는 않았다. 기존 작업 문서의 Android 관찰 결과를 이번 통합 빌드의 실기기 검증으로 세지 않는다.
