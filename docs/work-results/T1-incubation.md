# T1 시간 모드 반복 품기 결과

- 검토 코드 기준: `19e17b07592a80bf971b21ac22adc7aec6ac08ff (PR #21)`
- 범위: ETA가 경과 시간만큼만 줄어드는 고정 일정의 순수 계산. 앱 연결은 포함하지 않는다.
- `incubationRound(int remainingEtaSec)`는 한 회차를, `incubationSchedule(int initialEtaSec)`는 전체 회차의 변경 불가능한 목록을 반환한다. 입력은 정수 초, 120초 미만은 `RangeError`로 지원하지 않는다.
- `IncubationRound.remainingEtaSec`는 지급 당시 남은 초, `eggGrantedSec`, `hatchEndSec`, `companionEndSec`는 최초 지급부터의 경과 초, `grantsNextEgg`는 동행 종료 시 다음 알 지급 여부다. 한 회차 API의 최초 지급 시각은 0이다.
- 초가 포함된 ETA는 정확한 절반을 **분 단위로 내린다**: 예를 들어 719초는 품기 300초, 동행 419초. 4800초는 최종 회차, 4801초는 반복한다. 이는 현재 [계약](../schema.md#부화이어하기)의 '절반을 분 단위로 내림'과 일치하는 초 단위 해석이다.

## 검증

- 변경 전 `phone/packages/allo_core`에서 `dart pub get`, `dart analyze`, `dart test`: 테스트 28개 통과, 기존 분석 info 2건.
- 구현 전 신규 테스트 실행: 해당 모듈과 함수 부재로 실패 확인.
- 신규 테스트: 요청된 11/80/81/90/150/151/300분과 300분 지급 시각, 4799/4800/4801초, 초 보존, 120초 미만 거부, 결과 목록 불변성을 확인.
- 변경 후 `phone/packages/allo_core`에서 `dart pub get`, `dart analyze`, `dart test`: 테스트 33개 통과, 기존과 동일한 분석 info 2건 (`allo_core.dart` library 이름, `models.dart` 주석).

## 검토 당시 연결 제안과 이후 확정 사항

이 절은 PR #21 기준의 계산 모듈 검토 당시 제안과 미검증 범위를 기록한다. 현재 정책은 [docs/schema.md의 부화·이어하기](../schema.md#부화이어하기)와 병합된 [PR #38](https://github.com/Allo-MJU/allo/pull/38)이 우선한다. 계산기는 [PR #28](https://github.com/Allo-MJU/allo/pull/28)로 dev에 병합됐고, 공용 export·컨트롤러·저장/복구를 포함한 앱 연결은 열린 [PR #36](https://github.com/Allo-MJU/allo/pull/36)에서 진행 중이다(2026-11-05 확인). 계산기 병합을 앱 연결이나 실제 기기 검증 완료로 해석하지 않는다.

- 당시에는 공용 export에 `export 'src/incubation_schedule.dart';` 추가를 제안했다. 기존 `HatchTimer`는 세션 단일 알의 ETA/거리 50%를 계산하므로 자동 반복 상태 전환을 제공하지 않는다.
- 당시에는 컨트롤러가 최초 ETA 초로 일정을 생성하고 각 회차의 상대 시각을 실제 시작 시각에 더해 품기 종료·동행 종료·다음 알 지급 이벤트를 처리하는 연결을 제안했다. 저장/복구 및 스키마 필드 변경은 이 계산 모듈 결과에 포함하지 않았다.
- 당시 결정 대상으로 남긴 ETA 변경·소실, 2분 미만 동작, 중단·복구, 거리 모드, 새 알 종류, 회차별 판정 구간, 경계 이벤트 순서는 현재 계약을 따른다. 각 알의 계획은 지급 시 고정하고 다음 지급 때 ETA를 다시 확인하며, 2분 미만이면 새 알 지급을 보류한다. 계산 함수의 120초 미만 `RangeError`는 호출부가 지급 보류를 처리한다는 전제조건이다. 기존 타이머·컨트롤러·직렬화와의 연결 및 실제 기기 동작은 이 계산 모듈 작업에서 검증하지 않았다.
