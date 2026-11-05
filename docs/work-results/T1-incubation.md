# T1 시간 모드 반복 품기 결과

- 검토 코드 기준: `19e17b07592a80bf971b21ac22adc7aec6ac08ff (PR #21)`
- 범위: ETA가 경과 시간만큼만 줄어드는 고정 일정의 순수 계산. 앱 연결은 포함하지 않는다.
- `incubationRound(int remainingEtaSec)`는 한 회차를, `incubationSchedule(int initialEtaSec)`는 전체 회차의 변경 불가능한 목록을 반환한다. 입력은 정수 초, 120초 미만은 `RangeError`로 지원하지 않는다.
- `IncubationRound.remainingEtaSec`는 지급 당시 남은 초, `eggGrantedSec`, `hatchEndSec`, `companionEndSec`는 최초 지급부터의 경과 초, `grantsNextEgg`는 동행 종료 시 다음 알 지급 여부다. 한 회차 API의 최초 지급 시각은 0이다.
- 초가 포함된 ETA는 정확한 절반을 **분 단위로 내린다**: 예를 들어 719초는 품기 300초, 동행 419초. 4800초는 최종 회차, 4801초는 반복한다. 이는 명시된 '절반을 분 단위로 내림'의 초 단위 해석으로, 팀이 다른 초 반올림 규칙을 의도했다면 확인이 필요하다.

## 검증

- 변경 전 `phone/packages/allo_core`에서 `dart pub get`, `dart analyze`, `dart test`: 테스트 28개 통과, 기존 분석 info 2건.
- 구현 전 신규 테스트 실행: 해당 모듈과 함수 부재로 실패 확인.
- 신규 테스트: 요청된 11/80/81/90/150/151/300분과 300분 지급 시각, 4799/4800/4801초, 초 보존, 120초 미만 거부, 결과 목록 불변성을 확인.
- 변경 후 `phone/packages/allo_core`에서 `dart pub get`, `dart analyze`, `dart test`: 테스트 33개 통과, 기존과 동일한 분석 info 2건 (`allo_core.dart` library 이름, `models.dart` 주석).

## 조정 담당 연결 제안과 결정 필요 사항

- 공용 export에 `export 'src/incubation_schedule.dart';` 추가를 제안한다. 기존 `HatchTimer`는 세션 단일 알의 ETA/거리 50%를 계산하므로 자동 반복 상태 전환을 제공하지 않는다.
- 컨트롤러는 정책 결정 후 최초 ETA 초로 일정을 생성하고, 각 회차의 상대 시각을 실제 시작 시각에 더해 품기 종료·동행 종료·다음 알 지급 이벤트를 처리할 수 있다. 저장/복구 및 스키마 필드 변경은 이번 결과에 포함하지 않는다.
- ETA 변경·소실 시 재계산/유지와 스냅샷 시점, 2분 미만 동작, 중단·복구, 거리 모드 반복, 새 알 종류, 회차별 판정 구간, 경계에서의 이벤트 순서 및 화면/상태 반영을 결정해야 한다. 기존 타이머·컨트롤러·직렬화와의 연결 및 실제 기기 동작은 검증하지 않았다.
