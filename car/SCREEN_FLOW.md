# Pleos 화면 흐름 (#92)

2026-11-11 — 화면 구현, 실기 통합 검증 대기.

## 실제 차량 앱에 연결된 범위

- 기존 로고와 6종 캐릭터 에셋, 먹색 공통 프레임, 넓은 창/좁은 창 배치.
- 시작 → 권한 안내(나중에 포함) → 실제 세션 생성 후 QR 연결.
- 주행/UX 제한이 모든 주차 조작보다 우선. 실제 Pleos와 미리보기 주행 화면 모두 기존 6종 run 프레임으로 달리기 애니메이션을 표시. 연결 끊김·백그라운드·시스템 애니메이션 비활성화 시 정지.
- 주차 홈과 거점/여행/공유 상세를 탭으로 분리. 동행이 없어도 탭과 독립적인 알 품기 정보 유지.
- 폰 동행 없음, 연결 끊김과 재연결, 세션 종료 및 주차에서 다음 연결 준비.
- 기존 v2 이동 요청/receipt에 연결된 대기·확인 중·거절·완료 화면. 원 요청 개체/revision과 일치하는 결과만 표시. 확정 후 기존 달리기 프레임으로 퇴장.
- 폰 이동 요청/재시도 및 다음 세션 생성은 호출 시점의 신선한 주차 허용을 다시 확인.
- 쉬는 시간은 기존 잠자기 애니메이션이며 보상을 만들지 않음.

## 폰 낚시 연결 구현

- 별도 `fishing.version=1` capability 및 현재 동행 표시 ID/revision이 맞을 때 낚시 시작/정지/이어하기/저장 재시도를 활성화한다. 구버전 폰에서는 비활성화한다.
- 낚시 진행·저장 중·보상 획득·휴식·저장 실패 화면을 실제 `/game.fishing`에 연결한다. 차량은 보상이나 시간 진행을 계산하지 않는다.
- 차량 화면 RESUMED 및 신선한 P/UX 허용 신호, 폰 lease echo를 1초 presence로 전달한다. 신선함은 gameRevision 상승과 로컬 monotonic 시간으로 확인한다.
- 폰의 도감 획득 기록을 선택하고, 개체별 진행·보상·이동 결과를 단일 로컬 프로필에 저장한다. 처음 선택·낚시·이동은 저장 성공 후에만 결과를 발행한다.
- 요청은 lease/표시 개체/활동/회차로 묶고 같은 ID 재시도를 지원한다. 단절·앱 비활성·세션 종료·선택 변경은 진행을 정지하며 오프라인 시간을 더하지 않는다.
- 계약과 저장 경계: `docs/vehicle/fishing-integration.md`. 실제 Firebase/폰/Pleos 실기 왕복 검증은 대기한다.

## 남은 범위

- 선택 변경 중/실패의 차량 전용 화면은 여전히 preview fixture다. 실제 성공 선택은 companion 갱신으로 반영하고 선택 저장 오류는 폰에서 안내한다.
- 폰 화면 공유는 기존 debug 시제품만 연결한다. 주간 테마·자동 주야간 전환은 후속이다.
- 물고기 관찰 기록 3종 순환·유효 진행 60초는 ruleVersion 1 시제품 값이다. 실제 콘텐츠와 밸런스는 별도 검토한다.

## 미리보기와 검증

```
cd car
./gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleRelease :preview:assembleDebug -PincludePreview=true
adb install -r preview/build/outputs/apk/debug/preview-debug.apk
adb shell am start -S -n ai.allo.preview/ai.allo.preview.PreviewActivity --es screen Home
```

`screen`은 `PleosRoute` enum 이름. `species`는 기존 6종 speciesId. `--ez controls false`로 상태 선택 도구만 숨길 수 있다. 테스트 데이터 배너는 항상 남는다. 미리보기는 실제 Firebase/차량/폰을 조작하지 않는다.

라우터 테스트는 주행/종료/단절 우선순위, 잘못된 동행 데이터, 이전 개체의 늦은 이동 결과, 동일 종/다른 개체 전환 등을 검사한다. 단위 테스트·빌드는 실기 판정 정확도나 폰 저장 내구성 검증을 대신하지 않는다.

실제 기기 검증 항목과 캡처는 Git 제외 로컬 `tasks/`에 기록한다.
