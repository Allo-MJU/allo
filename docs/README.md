# 알로(ALLO) 문서

차가 달린 만큼 알이 자라고, 여행 중간에 깨어나 도착까지 함께 가는 뒷자리 아이용 수집 게임.

현대자동차그룹 차량용 앱 개발 공모전 출품작 · Pleos Connect

## 문서

| 문서 | 내용 | 주로 보는 사람 |
| --- | --- | --- |
| [proposal.md](./proposal.md) | 기획서. 문제 정의, 서비스 상세, 차량특화성, 기술 활용성, 사업성, 경쟁 분석 | 전원 |
| [dev-plan.md](./dev-plan.md) | 개발 계획. 일정, 역할, 마일스톤 게이트, 리스크 | 전원 |
| [roadmap.md](./roadmap.md) | 파트별 상세 로드맵. 각자 할 일 | 각 파트 |
| [schema.md](./schema.md) | 레포 구조 + Firebase 데이터 스키마 | 전원 (**계약서**) |
| [setup.md](./setup.md) | 차량 앱 개발 환경 초기 세팅 (JDK · Android Studio · Pleos 에뮬레이터 · 샘플앱) | A · 차량 앱 빌드할 사람 |
| [verification.md](./verification.md) | SDK 검증 8개 결과 기록 | A |
| [architecture.md](./architecture.md) | 기술 스택 결정과 근거, 선례에서 확인된 제약 | 전원 |
| [demo-scenario.md](./demo-scenario.md) | 시연 9단계와 Virtual Console 명령 | A·B·D |
| [design-system.md](./design-system.md) | 색, 글자, 컴포넌트, 캐릭터 12종 표현 규칙 | B·D |

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
