# 알로(ALLO) 문서

차가 달린 만큼 알이 자라고, 여행 중간에 깨어나 도착까지 함께 가는 뒷자리 아이용 수집 게임.

현대자동차그룹 차량용 앱 개발 공모전 출품작 · Pleos Connect

## 문서

| 문서 | 내용 | 주로 보는 사람 |
| --- | --- | --- |
| [base-camp.md](./base-camp.md) | 역할별 거점·재료·오프라인 작업·음식 보너스·훈련의 확정 규칙과 C 연결 | A·B·C·D |
| [affinity-hatching.md](./affinity-hatching.md) | 사용자 확정 호감도 부화 규칙과 C API·사진 퀘스트·데모 서버 연결 | A·B·C |
| [color-and-app-references.md](./color-and-app-references.md) | 알로 색상값과 참고 앱 | 전원 |
| [proposal.md](./proposal.md) | 기획서. 문제 정의, 서비스 상세, 차량특화성, 기술 활용성, 사업성, 경쟁 분석 | 전원 |
| [dev-plan.md](./dev-plan.md) | 개발 계획. 일정, 역할, 마일스톤 게이트, 리스크 | 전원 |
| [roadmap.md](./roadmap.md) | 파트별 상세 로드맵. 각자 할 일 | 각 파트 |
| [schema.md](./schema.md) | 레포 구조 + Firebase 데이터 스키마 | 전원 (**계약서**) |
| [setup.md](./setup.md) | 차량 앱 개발 환경 초기 세팅 (JDK · Android Studio · Pleos 에뮬레이터 · 샘플앱) | A · 차량 앱 빌드할 사람 |
| [verification.md](./verification.md) | SDK 검증 8개 결과 기록 | A |
| [architecture.md](./architecture.md) | 기술 스택 결정과 근거, 선례에서 확인된 제약 | 전원 |
| [demo-scenario.md](./demo-scenario.md) | 시연 9단계와 Virtual Console 명령 | A·B·D |
| [ai-character-dialogue.md](./ai-character-dialogue.md) | 캐릭터 대화·AI 통합 기획. 상황 대사(한국어 뱅크)와 영어 대화, 캐릭터 12종 기준표, 팀 결정 사항 | 전원 |
| [character-personas.md](./character-personas.md) | 캐릭터 12종 영어 페르소나 v1 확정본. 원문·한국어 뜻·고치는 절차 | 전원 · 영어 대화 담당 |

## 도감·거점·Pleos 통합

- [모바일 도감](vehicle/dex-experience.md) · [거점 규칙](base-camp.md)
- [질문 버튼 이야기](vehicle/companion-dialogue.md) · [주행 자동 낚시](vehicle/driving-auto-fishing.md)
- [차량 UI 재설계](vehicle/car-ui-redesign.md) · [로컬 Firebase 실행](vehicle/local-firebase.md)
- [통합 검증](vehicle/integrated-camp-verification.md) · [화면 캡처](vehicle/screenshots/integration/README.md)

## 읽는 순서

처음 보는 사람 → `proposal.md` → `schema.md` → 자기 파트의 `roadmap.md`

## 규칙

- **`schema.md`는 계약서입니다.** 변경은 C 승인 + 전원 공지
- 검증 결과가 나오면 `verification.md`에 바로 기록
- 설계가 바뀌면 해당 문서를 먼저 고치고 코드를 고칩니다

## 일정

| 날짜 | 내용 |
| --- | --- |
| 11/15 23:59 | 접수 마감 |
| 11/23 | 1차 결과 발표 |
| 12/3~4 | 최종 PT |
| 12/18 | 최종 선정 |
