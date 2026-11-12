# Pleos 앱 윈도 크기와 분할화면 대응

2026-11-12 · #92 화면 디자인과 원본 로고를 유지한다. 차량 전체 디스플레이 크기를 앱 콘텐츠 크기로 간주하지 않는다.

## 공식 기준

- [Display Layout](https://document.pleos.ai/docs/connect/guide/docs-design/getting-started/layout): Application window에는 앱이 1개 또는 2개 표시된다. 앱은 Landscape/Portrait 두 레이아웃에 적응해야 한다. Status bar, Driving view, GNB는 시스템 영역이며 시스템 패널·키보드는 앱보다 위에 표시될 수 있다.
- [Window Policy](https://document.pleos.ai/docs/connect/guide/docs-design/getting-started/window): Connect-S의 1:1/2:0, Connect-W의 2:1/1:2 윈도 배치를 고려한다. 앱 윈도 버튼과 구분 바를 통한 전환 중에도 현재 화면을 유지한다.

## 구현

- `ScreenFrame`은 실제 앱 윈도 제약과 safe-drawing inset을 사용한다. 낮은 창에서 헤더 로고·여백만 줄이며 제목/상태는 제한된 줄 수로 유지한다. 시스템 바나 차량 Driving view를 그리거나 덮지 않는다.
- `ScreenColumns`는 가용 폭·높이로 캐릭터/QR 크기를 제한한다. 좁은 창은 세로 스크롤, 넓은 창은 그림과 스크롤 가능한 상세 영역으로 나눈다. 주차 탭은 상세 스크롤 밖에 유지한다.
- 주행 화면은 가용 높이가 작으면 좌우로 배치한다. 제목·상태의 읽기 공간을 먼저 확보하고 캐릭터 크기를 조절한다. 속도 연동·넘어짐 프레임은 그대로 사용한다.
- 주차 탭과 쉬는 시간 선택은 `rememberSaveable`로 보존한다. 크기 조절/재생성으로 홈 탭에 되돌아가지 않는다.
- preview 앱의 landscape 고정을 제거해 세로/분할 창에서 실제 화면을 검증할 수 있게 했다.

## 검증

- 단위 테스트 **252개 통과**, failure/error/skip 0. 신규 4개는 낮은 창 가로 배치, 좁은 창의 글자 공간 확보, 확대 글자와 그림 공간 조정, 크기 조절 중 0 bounds를 검증한다.
- app/preview debug APK 및 마지막 UI 변경 기준 app release APK 빌드 성공. release는 lintVital/R8 포함 `:app:assembleRelease`가 통과했다.
- 실제 Pleos 기본 density의 **1:1 앱 윈도 841×1210dp**에서 6개 상태를 확인했다. 이것은 창 전체 크기이며 헤더·inset을 제외한 내부 콘텐츠 크기와 다르다.
- 실제 앱 task bounds를 **420×720dp**로 줄여 주차 홈의 원본 로고·본문 배치, 스크롤 후 하단 ‘폰으로 친구 부르기’ 접근을 확인했다.
- 좁은 창에서 여행 탭을 선택하고 841×1210dp로 복원한 뒤 선택 유지가 확인됐다.
- density 320으로 수행한 보조 실험은 시스템 레이어까지 확대하므로 실제 분할창 적합성의 최종 근거에서 제외했다.
- 캡처는 로컬 `tasks/screenshots/layout/`에 보관한다. 실제 폰/Firebase 연결, 모든 Connect-W 하드웨어 및 키보드/시스템 패널 조합의 통합 검증을 완료했다는 의미는 아니다.
