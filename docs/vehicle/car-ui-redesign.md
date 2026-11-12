# Pleos 차량 UI 재설계

## 목표와 유지할 계약
로고·캐릭터 원본과 폰 소유 데이터 계약을 유지하면서 차량에서 읽기 쉬운 공통 프레임, 메뉴, 상태 카드를 적용한다. 전체 디스플레이 대신 실제 앱 윈도의 가용 폭·높이에 적응한다.

## 구성
- 공통: ALLO 로고, 화면 제목, 연결 상태를 헤더에 정리. 큰 터치 영역과 일관된 글자 위계, 시스템 주야간 테마.
- 주차: 넓은 창은 메뉴 rail와 본문 분리. 좁은 창은 큰 탭과 세로 스크롤. 홈 요약, 친구 이미지 도감, 시설 상태 카드, 이야기 질문, 여행, 폰 공유 모두 유지.
- 연결/오류/완료: QR 또는 캐릭터를 별도 면에 배치하고 핵심 상태와 주동작부터 표시.
- 주행: 사용자 확정 흐름인 자동 낚시와 짧은 재료 수집 안내를 표시. 원본 캐릭터와 연결·신호 freshness·시스템 모션 설정 gate를 유지한다. 달리기/넘어짐으로 바꾸지 않는다.
- 가로/세로 전환 시 선택 상태 보존. 스크롤 가능한 본문과 내비게이션을 분리.

## 공식 근거
- [UI Design Guide](https://document.pleos.ai/docs/connect/guide/docs-design/Introduction/intro): 짧은 확인 시간, 높은 대비, 단순 조작.
- [Display Layout](https://document.pleos.ai/docs/connect/guide/docs-design/getting-started/layout) / [Window Policy](https://document.pleos.ai/docs/connect/guide/docs-design/getting-started/window): 앱 창 가로·세로 대응, 시스템 UI 영역 존중.
- [Typography](https://document.pleos.ai/docs/connect/guide/docs-design/foundations/typography): 중립적인 서체와 정보 위계.
- [주행 안전 설계](https://document.pleos.ai/docs/pleos-only/vehicle-app-planning-guide/driver-distraction-guideline): 반복 장식 모션 축소. 이번 작업은 플랫폼 심사나 모든 카테고리의 주행 허가를 인증하지 않는다.

## 완료 조건
단위검사 및 debug/preview 빌드 통과, 실제 Pleos 설치 후 넓은/분할 창의 라이트/다크 화면을 확인하고 로컬 캡처를 남긴다. 기존 로컬 Firebase 상태를 사용하며 실서비스 배포는 하지 않는다.

## 검증 메모
- 실제 앱 창 1682×1210과 841×1210에서 rail/상단탭 전환 및 카드 배치 확인.
- 420×720 작은 창에서 이야기 4개 질문까지 스크롤 접근 확인.
- 시스템 night yes/no로 라이트·다크 테마 전환 확인.
- 로컬 Firebase에 저장된 동행·재료·시설 상태를 새 디자인으로 표시, 실제 가상 차량 D/P 신호로 주행/주차 전환 확인.
- 테스트와 화면 증거는 artifacts/redesign 아래 로컬 캡처 및 /tmp/allo-redesign-build.log에 기록.
- 주행 제한 전체 연동은 이번 범위 밖이다. 기존 CarUxRestrictions 확인은 화면공유 gate에서 사용하며 일반 화면 분기는 기존 기어 정책을 유지한다.

- 최종 차량 단위테스트284개 통과, debug/preview 빌드 성공, diff 검사 통과. 테마 전환 후 거점 선택 유지 확인. 최종 에뮬레이터는 주차·라이트 홈 상태로 복원.

## 낚시 장면 확대
- 기존 자동 낚시 캐릭터와 모션 gate 유지. 실제 획득량/활동 계약은 변경하지 않는다.
- 고정 220dp 크기 대신 창 폭·높이와 텍스트 예약 공간에 따라 최대720dp로 확대한다.
- 넓은 창은 장면/상태 좌우 배치, 세로 분할 창은 장면 위·상태 아래 배치.
- 정적인 Canvas 물가(수면·먼 산·갈대·선착장)는 창 크기에 비례하고 주야간 팔레트를 사용한다. 현재 위치/날씨를 주장하는 지도나 실시간 풍경이 아니다.
- 배경은 추가 애니메이션 없이 낚시 캐릭터를 받쳐준다. 본문은 별도 테마 Surface에서 읽는다.

- 낚시확대 최종검증: 차량286테스트 통과, 앱/preview debug빌드 성공. Pleos 넓은창/1:1크기/420×720에서 캐릭터·낚싯대·상태문구 표시 확인, 주야간 전환 확인. 캡처 artifacts/fishing-scene.
