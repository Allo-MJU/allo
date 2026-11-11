# Pleos 화면 흐름 (#92)

2026-11-11 — 화면 구현, 실기 통합 검증 대기.

## 실제 차량 앱에 연결된 범위

- 기존 로고와 6종 캐릭터 에셋, 먹색 공통 프레임, 넓은 창/좁은 창 배치.
- 시작 → 권한 안내(나중에 포함) → 실제 세션 생성 후 QR 연결.
- 주행/UX 제한이 모든 주차 조작보다 우선. #92 시안 기준 주행은 정지 달리기 포즈이며 기존 run 프레임은 보존.
- 주차 홈과 거점/여행/공유 상세를 탭으로 분리. 동행이 없어도 탭과 독립적인 알 품기 정보 유지.
- 폰 동행 없음, 연결 끊김과 재연결, 세션 종료 및 주차에서 다음 연결 준비.
- 기존 v2 이동 요청/receipt에 연결된 대기·확인 중·거절·완료 화면. 원 요청 개체/revision과 일치하는 결과만 표시. 확정 후 기존 달리기 프레임으로 퇴장.
- 폰 이동 요청/재시도 및 다음 세션 생성은 호출 시점의 신선한 주차 허용을 다시 확인.
- 쉬는 시간은 기존 잠자기 애니메이션이며 보상을 만들지 않음.

## 아직 실제 폰과 연결되지 않은 범위

기존 /game v2에는 낚시 capability·진행·저장 receipt·선택 변경 대기/오류 계약이 없다. 이번 변경은 공용 wire 스키마를 확장하지 않는다.

- 낚시 진행/저장 중/획득/실패 및 선택 변경 중/실패의 UI는 `PleosStatusScreen`으로 구현했고 미리보기에서만 fixture로 검증한다.
- 실제 주차 홈의 낚시 시작은 비활성화한다. 클라이언트 타이머로 보상·진행·성공을 만들지 않는다.
- 실제 선택 결과는 기존 companion 갱신으로 표시한다. 선택 중/실패를 임의 추정하지 않는다.
- 계약 합의 후 폰 단일 작성자의 원자 저장·중복 방지·진행 시간 판정과 차량 어댑터 연결이 필요하다.
- 폰 화면 공유는 기존 debug 시제품만 연결한다. 주간 테마·자동 주야간 전환은 후속이다.

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
