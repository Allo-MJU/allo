# #101 리뷰 및 #91 최신 dev 통합

기준: PR #91 `01caffb`에 dev `fe7a589`(#99 포함)를 통합. PR을 dev에 머지하는 작업은 하지 않는다.

## 수정한 문제

- `main.dart` 충돌: fake feed의 시연 배속과 `configuredEggApi()`를 모두 보존했다. 별도 dart-define을 넣어 두 설정의 동시 적용을 검사했다.
- 호감도 모드에서도 자동 탐험이 열리면 사진·말 걸기·구역 입력이 가려졌다. 호감도 모드는 전용 입력 화면에 머물고 기존 시간/거리 모드는 자동 탐험을 유지한다. 수동 탐험 버튼은 유지했다.
- Unity에 hatched 상태를 보낸 것만으로 연출을 봤다고 기록하여, 준비 전이나 연출 도중 닫으면 Flutter 부화 화면까지 건너뛰었다. 이제 같은 알의 실제 Unity 완료 ack를 확인한다. 구 export는 ack가 없으므로 Flutter 부화 화면으로 돌아간다. 계약: [hatch-ack.md](hatch-ack.md).
- #99의 egg→cast 발행 순서, care 수신, 탐험 중 라우팅, Android release ExploreBridge keep 규칙을 보존했다.

## #101에서 아직 결정·검증할 항목

- tap/rub/sing/blanket의 인정 횟수·가중치는 C의 정책 결정이 필요하다. 현재 모두 기존 care()로 연결하며 호감도에서는 petEgg()의 공통 쿨다운을 따른다. Unity의 시각 반응 쿨다운과 점수 승인 주기는 다르다.
- 수동 호감도 탐험의 egg.progress는 호감도 점수가 아닌 기존 진행률이다. 사진 잠금/결과 대기/입력 거절 상태를 Unity 계약에 확장할지는 후속 결정이다. 실제 부화 판정은 컨트롤러의 hatched 상태를 따른다.
- Unity 열린 상태에서 홈/잠금/복귀 시 실제 foreground 판별은 기기 검증이 필요하다. 기존 appActiveFor는 Unity가 열려 있으면 paused/hidden을 활성으로 취급한다.
- Unity Editor가 설치되지 않아 C# 컴파일·EditMode·Android 재export·실기 연출은 미검증이다. Flutter bridge 테스트는 메시지를 모의 주입한다. APK 빌드는 Unity export 없는 기본 Flutter 경로다.

## 검증

- 폰 Flutter 전체 311개, 공용 allo_core 70개, 차량 JUnit 257개 통과.
- 자동 탐험 회귀와 부화 ack 회귀의 실패를 먼저 재현한 뒤 수정했다.
- 시연 배속 2 + API URL/token의 동시 설정 시작 테스트 통과(네트워크 호출 없음).
- Flutter analyze: 오류/경고 없음, 기존 core info 3건으로 종료 코드 1.
- 기본 폰 ARM64 release APK 빌드 통과. Unity 포함 빌드/에뮬레이터 녹화는 수행하지 않았다.

#88의 8개 커밋은 이미 #91에 포함되어 있다. 현재 #88은 유지하고, #91을 실제 머지한 뒤 대체된 PR로 닫는 처리를 권장한다. #101은 남은 정책·실기 항목 때문에 완료 처리하지 않는다.
