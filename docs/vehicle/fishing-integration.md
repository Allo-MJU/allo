# 차량 주차 낚시와 폰 저장 계약 v1

2026-11-11. #92 설계 구현용 계약. 로컬 구현/자동 검증과 실제 기기 검증을 구분한다. 60초·물고기 관찰 3종 순환은 이번 시제품의 ruleVersion 1이며 콘텐츠/밸런스 확정 또는 팀 전체 승인으로 간주하지 않는다.

## 기존 기반 조사

현재 dev의 폰에는 legacy 도감과 품기 저장만 있으며 동행 선택/이동 receipt/낚시 저장은 없다. #54/#60은 제안 계약이다. 열린 #93은 호감도 부화만 다루고 영속 동행 구현은 포함하지 않는다. 기존 DexStore는 변경하지 않고 별도 단일 낚시/동행 프로필에 기존 도감 레코드와의 안정적인 매핑을 유지한다. 같은 종의 다른 획득 기록을 종 ID만으로 합치지 않는다. 기존 도감에서 완전히 동일한 레코드는 원래도 중복 제거되므로 별도 개체로 복원할 수 없다.

## 소유권과 전체 상태 발행

폰은 유일한 `/game` 작성자다. 기존 GameController의 전체 snapshot 큐에 품기·지역 정보와 동행·낚시 요약을 합친다. 낚시 모듈이 Firebase에 별도로 game을 patch/overwrite하지 않는다. 폰과 차량은 종 이름·그림을 기존 카탈로그로 표시하고 로컬 도감 레코드/획득 위치/원문을 원격으로 보내지 않는다.

동행은 기존 v2의 `companion {displayId, displayRevision, speciesId, location}`와 `transferResult`를 사용한다. 낚시는 별도 `fishing.version == 1` capability로 구분한다. `contractVersion == 2`만으로 낚시를 켜지 않는다. 누락·미지원·잘못된 블록은 동작을 비활성화한다. 전체 game 발행마다 gameRevision이 증가해야 하며 앱 재시작에서도 역행하지 않도록 폰에서 영속 revision 구간을 예약한다.

## 추가 wire 필드

정확한 입력 예시는 [fishing-v1.json](../../data/fixtures/fishing-v1.json)에 있다.

`game.fishing`: version, leaseId, displayId, displayRevision, activityId, cycle, state, elapsedMs, targetMs, totalRecords, 선택적 rewardName/requestId. state는 ready/running/paused/saving/reward/saveFailed. targetMs=60000, elapsedMs=0..targetMs. 표시 개체/revision과 맞는 요약만 표시한다. activityId는 시작 전 빈 문자열, 시작 저장 성공 후 비어 있지 않은 opaque ID다. 최초 시작의 saving/saveFailed는 아직 저장 확정 전이므로 빈 activityId를 허용한다. rewardName과 totalRecords는 성공 저장 뒤에만 증가한다.

`vehicle.fishingPresence`: version=1, leaseId(폰이 발행한 값의 echo), epoch(차량 프로세스/세션), sequence, active, parkedAllowed. 차량 화면 resumed와 신선한 P/UX gate를 모두 확인한다. 기존 raw gear의 기본 P나 속도 0으로 허용하지 않는다. 게임 상태가 오래됐거나 단절이면 유효 lease를 보내지 않는다.

`events`의 `fishingRequested`, by=car, payload: requestId, leaseId, displayId, displayRevision, action(start/pause/resume/retry), activityId, cycle. 숫자는 문자열로 바꾸지 않는다. 차량은 하나의 요청만 대기하고 timeout 뒤 같은 ID로 수동 재확인한다. 세션·lease·개체 변경 시 오래된 요청을 폐기한다. 폰은 current lease/개체/활동/회차와 요청 receipt를 확인해 중복 실행을 막는다. 수신 식별자나 by 값은 인증 수단이 아니다. 기존 Firebase 개발용 접근 규칙을 제품 수준 인증으로 확대 해석하지 않는다.

## 시간·연결·라이프사이클

폰은 local monotonic 시계로 서로 인접한 자격 있는 presence 수신 구간만 인정한다. 같은 epoch, sequence +1, 간격 2초 이하, 화면 활성·주차 허용·현재 lease가 양끝에서 맞아야 한다. 최초 신호는 기준점이며 누락/역순/중복/다른 lease는 시간을 늘리지 않는다. 3초 이상 신호가 없으면 watchdog이 정지하고 lease를 교체한다. 폰이 백그라운드에 가거나 화면을 닫으면 정지·체크포인트 저장·lease 무효화. 돌아와도 수동 이어하기가 필요하다. 벽시계·오프라인 시간으로 보상을 보충하지 않는다.

현재 회차 중지 시 마지막 인정 진행을 보존한다. 정상 진행 중 최대 5초 간격으로 체크포인트한다. 60초 완료 시 회차 완료 키와 관찰 기록을 같은 JSON 저장 단위로 확정한 뒤에만 보상 상태를 발행한다. 저장 실패 시 saveFailed로 정지하며 동일 저장 내용으로 재시도한다. 성공 receipt가 있는 회차는 재요청/재시작으로 다시 보상하지 않는다. 연결이 계속 유효하면 저장된 보상을 표시한 다음 다음 회차로 진행한다.

## 선택·이동·저장 경계

폰의 도감에 실제 있는 획득 기록만 차량 동행으로 선택할 수 있다. A→B는 A 진행 정지와 B 선택을 같은 프로필 저장으로 확정한다. B의 저장된 진행은 정지 상태이며 자동 실행하지 않는다. 폰 이동도 진행 정지·location=phone·이동 receipt를 함께 저장한 다음 성공을 알린다. 실패 중에는 선택/이동 성공을 알리지 않는다. 기존 품기 상태는 이 변경으로 초기화하지 않는다.

단일 SharedPreferences JSON 쓰기의 성공 여부를 확인한다. 이는 OS 강제 종료·전원 단절까지 완전한 파일시스템 트랜잭션을 보장한다는 뜻이 아니다. 손상/미지원 프로필을 빈 정상 프로필로 덮어쓰지 않고 오류로 남긴다. 강제 종료 시 마지막 성공 체크포인트 이후 진행은 유실될 수 있으며, 실제 기기의 저장 내구성은 별도 확인한다.

## 검증 경계 및 이후 병합

공용 fixture를 폰 serializer/차량 reader 테스트에 사용한다. 정상 60초→보상, 중복 요청, 저장 실패 후 재시도, 끊긴 시간 미가산, 앱 비활성/세션 종료, 선택/이동 경합, 재시작 복원과 legacy 품기 회귀를 검증한다. 실제 Firebase·폰·Pleos 왕복, P/D/UX 반영 지연, 잠금/강제 종료, 실제 저장 내구성·애니메이션 성능은 로컬 tasks/todo.md에 남긴다.

#93 병합 시 GameState/컨트롤러의 호감도 필드와 이번 vehicleFeatures를 같은 전체 snapshot에 합쳐야 한다. gameRevision 소유자를 둘로 만들거나 한쪽의 affinity/companion 블록을 덮어쓰지 않는다. 이번 구현은 다른 미병합 PR을 자동 병합하지 않는다.


## 로컬 검증 결과 (2026-11-11)

- 폰 전체 Flutter 테스트 207개, 공용 core 테스트 54개, 차량 JVM 단위 테스트 202개 통과.
- 폰 Android debug APK, 차량 debug/release APK, preview debug APK 빌드 성공.
- 공용 fixture의 폰 serializer/차량 reader/event JSON 일치와 실제 GameController/feed 인터페이스를 통과한 선택→시작→유효 60초→보상 저장→재시작 복원 검증.
- 저장 지연 중 도착 신호 폐기, 초기 선택/세션 종료 저장 실패 재시도, 같은 세션 재시작의 이전 미처리 이동 요청 거절, 확정 receipt 재생을 회귀 검증.
- 정적 분석에는 기존 core의 스타일 info 3건이 남으며 오류/경고는 없다. SDK/plugin 업그레이드는 이 변경 범위에 포함하지 않는다.
- 실제 Firebase/기기 왕복은 미수행. 현재 결과는 자동 테스트와 빌드에 대한 검증이며 실기 동작 완료를 뜻하지 않는다.

## 실제 기기 실행 순서

[폰 실행 안내](../../phone/README.md)에 따라 `FEED=firebase`를 포함한 로컬 Firebase 설정을 주입한다. 기본 빌드는 fake 모드다. 차량 QR 페어링 후 폰 도감의 보유 획득 기록에서 차량 동행을 선택하고, 차량의 실제 P/UX 허용 상태에서 낚시를 시작한다. 양쪽 앱이 활성·연결 상태일 때 인정된 60초 후 관찰 기록 저장을 확인한다. 폰 비활성이나 연결 단절 중 시간은 적립하지 않으며 복귀 후 수동 재개한다.
