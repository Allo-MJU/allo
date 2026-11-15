# 바다 탐험 파일럿 구현·검증

2026-11-15 · 구현 소스 `6c4a79e` · 브랜치 `feat/sea-learning-pilot`

## 구현

바다 이야기 `coast_sail` v2를 폰 Unity 앱의 수동 `탐험 노트`에서 실행한다. 예상과 첫 조작을 각각 기록하고, 두 조건 비교와 이유 설명을 거쳐 개인 발견 카드를 저장한다. 재실험은 카드 수를 늘리지 않고 마지막으로 저장에 성공한 기록을 바꾼다.

다른 이야기의 기존 카드는 열람하고, 미완료 세션은 명시적인 새 바다 탐험 시작 전까지 보존한다. 자동 초대·다른 팩 실행·기존 직접 대화 대체는 추가하지 않았다. 초기화 오류는 재시도 상태이며 손상된 저장값을 덮어쓰지 않는다.

## 자동 검증

| 구분 | 결과 |
| --- | --- |
| Flutter 전체 | 555/555 통과 |
| 최종 저장·호스트 집중 테스트 | 55/55 통과 |
| 공통 Dart 코어 | 93/93 통과 |
| Unity EditMode | 294/294 통과 |
| 변경 Dart 분석 | 새 문제 없음 |
| 런처 | `bash -n`, `--help`, 실제 설치·실행 통과 |

전체 분석에는 기존 `app.dart:213`의 불필요한 null-aware 연산자 경고와 공통 코어의 library 관련 안내 두 건이 남아 있다. 이번 변경과 무관한 코드는 수정하지 않았다.

두 예상 × 두 첫 조작, 필수 설명, 저장 실패와 재시도, 이전 카드 호환, 다른 팩 미완료 세션, 지연 쓰기 중 소유자 교체, 손상된 v1 재시도, 과거 화면의 지연 요청, 네이티브 음성·AI 응답·사진 우선권을 검증했다. 주요 새 회귀는 구현 전 실패를 확인했다.

Android 쓰기가 메모리를 먼저 바꾸고 디스크 쓰기에 실패하는 경로도 가짜 플랫폼 저장소로 재현했다. 저장 큐는 실패한 값 대신 마지막으로 확인한 성공 기록을 보관하여 같은 프로세스에서 컨트롤러가 교체돼도 성공하지 않은 카드를 복원하지 않는다. 실제 디스크를 채우는 실패 실험은 수행하지 않았다.

## Android 화면 관찰

AVD `ALLO_API_36`, Android API36/arm64, 앱 `ai.allo.allo_phone`에 `adb install -r`로 설치했다. 앱 데이터 삭제와 제거 없이 업데이트했다.

실제 Unity 화면에서 차량 테스트 연결 → 탐험 노트 → 바다 시작 → **돛 접은 배 예상 / 돛 펼치기 첫 조작** → 반대 조건 → 비교 → 이유 → 카드 저장을 진행했다. 최종 APK 업데이트와 재시작 후 카드에서 예상과 첫 조작이 서로 다르게 보존되는 것을 확인했다. 카드의 재실험으로 새 예상 화면 진입도 확인했다.

| 화면 | 증거 |
| --- | --- |
| 예상 선택, 2400×1080 | [예상](../work-results/sea-learning-pilot/07-prediction.png) |
| 같은 조건의 두 결과 비교 | [비교](../work-results/sea-learning-pilot/10-comparison.png) |
| 최종 APK 재시작 후 개인 카드 | [복원 카드](../work-results/sea-learning-pilot/15-restored-card.png) |
| 800×360, 글자 크기1.3·야간 모드 | [작은 카드](../work-results/sea-learning-pilot/16-small-card.png), [작은 예상](../work-results/sea-learning-pilot/17-small-prediction.png) |

작은 화면에서도 카드의 다섯 항목과 하단 버튼이 잘리지 않았다. Android 뒤로 가기로 실험 입력을 반환했다. 설정 변경 뒤 해상도는 물리 기본값1080×2400, 글자 크기는1.0, 야간 모드는 `no`로 복원했다. Unity는 기존 게임 색상과 글꼴 체계를 사용한다.

최종 앱 프로세스의 AndroidRuntime/Unity/Flutter 오류 수준 로그는 확인 시점에 비어 있었다. 에뮬레이터 창을 앞으로 가져오고 [예상 선택 화면](../work-results/sea-learning-pilot/18-ready-to-try.png)을 직접 누를 수 있는 상태로 남겼다.

큰 화면의 예상·비교 캡처는 저장 실패 대응의 최종 Dart 보완 전 빌드에서 촬영했다. 마지막 보완은 저장 큐에만 적용되며 Unity 화면·콘텐츠·브리지 내보내기는 동일하다. 복원 카드와 작은 화면은 최종 APK에서 확인했다.

## APK와 실행

- 경로: `phone/build/app/outputs/flutter-apk/app-debug.apk` (생성물, Git 제외).
- SHA256: `97608a80cb276ce3c13866c1378cebfa00997b8a143280ca4d23f762186894c5`.
- 정의: `EXPLORE_UNITY=true`, `UNITY_APP=true`, `FEED=fake`, `FAKE_TIME_SCALE=1`, `SCENARIO=clear`, `UNITY_DEMO_CREATURES=true`.
- APK 안의 `coast_sail` 버전2와 `prediction` 노드를 직접 확인했다.
- [실행 안내](../sea-learning-demo.md), `scripts/demo_sea_learning.sh`로 다시 열 수 있다.

Unity 내보내기는 `AlloBuild.CreateExploreScene`으로 장면을 재생성했다. 생성 과정의 무작위 prefab/scene ID 변경은 소스 변경에 넣지 않았다. 긴 임시 경로에서 발생한 macOS 도메인 소켓 길이 오류는 `/tmp/allo-sea-build` 임시 경로로 해소했다.

## 검토와 한계

독립 코드 검토의 Android foreground 진입, 쓰기 실패 캐시, 지연된 화면 요청, 손상된 저장값, AI 응답 취소 경쟁 문제를 수정했고, 각 재검토에서 해결 판정을 받았다.

별도 화면 검토자는 위 다섯 캡처와 기존 디자인·관련 소스를 확인하고 시각적 완료 범위에 `ship` 판정을 내렸다. 작은 화면의 안내 글자는 물리 기기·아이 대상 확인이 남는다. 글자 크기·야간 모드 변경 때의 배치 확인은 Unity의 시스템 글자 확대나 동적 테마 지원을 입증하지 않는다.

검증은 로컬 가상 주행과 에뮬레이터 범위다. 실차·물리 기기·실제 AI 교육 품질·음성 발음·아이 대상 학습 효과는 이번 검증에 포함하지 않는다. 새 문장에 기존의 다른 음성을 재사용하지 않으며 자막으로 완주할 수 있다. 원격 배포·차량 앱 수정·PR 병합은 수행하지 않았다.
