# 호감도 부화와 차량 화면 연결

기준: 차량 PR #91 `c7b9fe9`, 호감도 PR #93 `487cb7b949a87604c9b8b020c7fed3910b554252`. PR 병합 없이 필요한 폰 로직과 차량 계약을 로컬 작업에 통합한다. Firebase 배포·실기 통합은 별도 대기다.

## 확인한 계약 차이

| 항목 | #91 | #93 | 통합 원칙 |
| --- | --- | --- | --- |
| 호감도 | score/target/ready 기반 차량 파서 | 소수 score/target/phase/photoCompleted | 새 단계 해석 추가, 기존 ready 형식 호환 |
| 상태 순서 | contractVersion 2 + gameRevision 필수 | contractVersion만 발행 | 폰의 단일 발행 경로에서 전체 snapshot revision 증가 |
| 게임 발행 | 낚시·동행·이동 결과 함께 발행 | 알/호감도 중심 | 기존 fishing/companion/transferResult 보존 |
| 부화 준비 | ready와 성공 구분 | 50점 사진 잠금, 완료 뒤 100점 즉시 부화 | 사진·저장 대기와 저장된 성공을 구분 |

## 화면과 판정 책임

폰이 점수·사진 완료·마감·부화 결과와 도감 저장을 판정한다. 차량은 받은 요약만 표시하며 점수 적립, 사진 완료, 성공을 자체 추정하지 않는다.

| affinity.phase | 차량 의미 |
| --- | --- |
| incubating | 호감도 쌓는 중. 시간/거리 진행률과 별개 |
| photoRequired | 폰에서 사진 퀘스트 확인 |
| resultPending | 폰의 부화 결과 저장 대기. 성공 연출 금지 |
| hatched | 저장된 부화 결과 |
| failed | 부화 실패 |
| discarded | 이번 알 종료 |

부화한 새 알의 speciesId와 이미 선택한 동행 개체는 서로 다른 정보다. 낚시 중에도 호감도 상태를 함께 받을 수 있고, 알의 성공·실패가 기존 동행 선택이나 낚시 보상을 초기화하지 않는다. 사진·발화 원문·사진 ID·API 토큰은 차량 snapshot에 포함하지 않는다.

## 실행 범위

새 호감도는 `startIncubating(tier, useAffinity: true)` 명시 호출로 활성화한다. 기존 일반 입력 화면은 기본 시간 기반 모드를 유지한다. 실제 카메라·STT·3D 입력 및 사진 서버 배포를 추가한 작업은 아니다. #93의 기존 호감도 규칙을 사용하며 이번 연결을 위해 규칙을 바꾸지 않는다.

로컬 검증은 합성 API 결과와 제어된 시간으로 폰 컨트롤러가 발행한 상태를 차량 파서·표현에 연결하는 방식이다. 실제 모델 품질·카메라·Firebase 왕복·Pleos 주행 허용 여부를 검증한 것으로 보지 않는다.

원래 규칙: [PR #93 기준 문서](https://github.com/Allo-MJU/allo/blob/487cb7b949a87604c9b8b020c7fed3910b554252/docs/affinity-hatching.md).

## 공유 검증 데이터

`data/fixtures/affinity-fishing-v2.json`은 실제 폰 `GameController` 시나리오가 발행한 JSON을 기준으로 한다. 생성 ID·전송 시각·revision만 비교 가능한 값으로 정규화한다. 낚시 관찰 기록 1건을 먼저 저장한 뒤 사진 퀘스트, 사진 완료, 부화 저장 실패/재시도, 다음 알, 버리기, 실패의 8개 상태에서 기존 선택 개체와 낚시 기록을 유지하는지 검증한다.

폰 `affinity_fishing_contract_test.dart`는 실제 serializer 출력과 공유 데이터를 비교하고 차량 테스트는 같은 파일을 읽어 파싱·표시 의미를 검증한다. fixture 갱신은 `UPDATE_AFFINITY_FIXTURE=1`을 명시한 폰 테스트 실행에서만 수행한다.

통합 검토에서 알 실패/버리기 후 전체 game heartbeat가 중단되는 문제를 발견했다. 알이 종료되어도 비최종 차량 신호에 대한 heartbeat를 유지하도록 수정했으며, 6초 후 revision이 계속 증가하는 회귀 검증을 추가했다.

## 로컬 검증 결과 (2026-11-12)

- 폰 전체 287개, 공용 코어 70개, 차량 223개 테스트 통과.
- 일반 폰 main.dart ARM64 debug APK 및 차량 app/preview debug 빌드 성공.
- Flutter analyze는 신규 오류·경고 없이 기존 core 정보성 지적 3건 유지.
- 독립 검토에서 발견한 실패/버리기 이후 heartbeat 문제는 실패 재현 후 수정·회귀 검증 완료.
- 실제 카메라/STT/AI 서버, Firebase, Pleos 차량 신호는 미검증. 일반 폰 UI의 호감도 입력 화면은 별도 연결 작업이며 이번 변경은 명시적 API 호출 경로를 검증한다.
