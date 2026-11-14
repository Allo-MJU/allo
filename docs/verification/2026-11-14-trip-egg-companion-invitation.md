# 여행당 한 알 · 캐릭터 탭 · 서버 대화 검증

2026-11-14 · 작업 시작 기준 dev `99309e9` · branch `feat/trip-egg-companion-interaction`

## 반영한 사용자 요구

- 페어링/복구 시 작은 알 하나 자동 준비. 차 안 알 크기·시작·친구 선택 창 제거.
- 여행별 영속 claim으로 같은 여행의 재연결·코드 재발급·재실행·tier 변경·부화/실패/버리기 뒤 재지급 차단. 40/30분·부화+30분 반복 지급 제거.
- 미부화 알은 다음 여행에 동일 ID·진도·호감도·사진 완료 상태로 승계하고 그 여행에 추가 알 지급 없음. 기존 ETA/거리 부화 계산 유지.
- 친구 상세의 ‘차 안으로 불러오기’로 정확한 소유 개체를 조용히 연결. 새로 관찰한 현재 알의 부화는 같은 sourceEggId의 새 개체만 무음 연결하며 기존 선택은 유지.
- 캐릭터 탭 → 머리 위 서버 초대 → ‘이야기 듣기 / 말 걸기’. 기본 큰 설명 패널 제거. 일반 앱 모드의 기존 로컬 캐릭터 자동 발화도 차단.
- 초대·고정 이야기·다음 장면·페르소나 적용·AI 답변·부모 제안 빈도는 서버 `/v1/companion/turn`에서 처리. 앱은 입력·취소·표시·TTS와 서버가 승인한 장면 참조 저장만 수행.
- APK의 개인 학습 manifest는 ID 메타데이터뿐. 페르소나·본문·지식·다음 장면 링크는 포함하지 않음. 서버 미연결 시 앱이 성공 초대나 이야기를 만들어내지 않음.

## 최종 검증

| 범위 | 결과 |
| --- | --- |
| 전체 Flutter | 479개 통과, `/tmp/allo-trip-invitation-flutter-release.log` |
| 순수 Dart core | 93개 통과 (incubation 계산 포함) |
| Unity EditMode | 189개 통과 (머리 UI, 음성 focus, 오류/대기, legacy 발화 차단) |
| 서버 | 48개 통과, 개체별 병렬성·동일 개체 빈도·128 활성 상태 용량 포함 |
| Dart → 실제 Python HTTP | 12종·48개 서버 작성 turn과 기존 사진/호감도/부화 확인. 모델 생성만 합성 응답 |
| 로컬 실행기 | 2개 통과, 키 없는 작성 콘텐츠 모드와 키 비출력/비저장 확인 |
| 차량 Kotlin 계약 소비 | JDK17 `AffinityFishingFixtureTest` 2개, 실패/오류/누락0 |
| 정적 분석 | 변경 범위 clean. 전체 phone analyze는 기존 app.dart 경고1·core 정보2만 남음 |
| diff | 이번 변경 파일 공백 오류 없음 |

전체 Flutter의 처음 실행은 새 계약과 충돌하는 수동 시작·반복 지급 및 비동기 widget fixture 때문에 실패/대기했다. 관련 기대를 새 계약으로 바꾸되 종료·낚시·부화·거리 모드 검증은 유지했다. 최종 전체 실행은 위 479개 모두 통과했다.

## 저장 안전과 수명 회귀

- A→B→A, 재시작·tier 우회, terminal·discard·동일 QR, 앱 중단, fake identity 분리 확인.
- 과거 데모→실제 유입, 여러 tier의 소비 기록 누락, 미저장 부화 결과 처리 후 다른 미부화 알 고립을 재현 후 수정.
- SharedPreferences가 실패한 set의 값을 캐시에 먼저 넣는 경우에도 실제 데모 복사 저장을 다시 시도하며, reload 이후 진행 보존 검증.
- 늦은 친구 소환·대상 변경·노트/실험·STT 반환, native 모달 focus와 실제 background, 콘텐츠 변경의 listen 경로 검증.
- 서버의 전역 provider 잠금을 개체별 잠금으로 분리. 원문·음성·요약은 빈도 상태에 저장하지 않음.

## APK와 실제 에뮬레이터 확인

- 마지막 Unity export 성공. debug APK 빌드76.9초.
- 경로: `phone/build/app/outputs/flutter-apk/app-debug.apk` (Git 제외).
- SHA-256: `e3155fdd37450dcf8805f6b266dd68ce126c0a9e720f24fac8802e8de9e1424f`.
- API36 에뮬레이터에 데이터 유지 install-r 및 cold launch 성공. 기존 도감·재료를 지우지 않음.
- 이전 terminal 여행에는 새 알이 생기지 않는 상태를 확인하고, 명시적으로 체험 여행을 끝낸 뒤 새 여행에서 알 자동 준비·claim 증가를 확인.
- 재시작 후 같은 egg ID와 claim 수 유지 확인. 미부화 알의 다음 여행 승계 전체 조합은 Flutter 저장 회귀 테스트로 확인했으며, 에뮬레이터의 빠른 연속 여행 종료 UI 자동화는 완료 증거로 사용하지 않음.
- 친구 상세의 불러오기 → 차 안 캐릭터 실제 hit → 서버 초대와 두 선택지 → 서버의 현재 이야기·다음 이야기 표시 확인. 서버 승인 장면 `light`가 로컬에 저장된 것도 확인.
- 실제 APK zip manifest를 검사해 식별용 12종만 있으며 페르소나·본문·지식·장면 링크가 없음을 확인.
- 캡처: `docs/work-results/unity-phone/trip-egg-invitation/01-auto-egg.png` ~ `05-server-next.png`.

서버는 같은 비공개 로컬 데모 설정으로 `--without-ai` 실행했다. 고정 초대·스토리는 실제 서버 응답이고 모델 응답을 가장한 로컬 fallback이 아니다. OpenAI API 키가 없는 생성형 chat은 별도 미검증이다.

## 경계

- 중복 지급 보장은 이 기기의 namespace/profile 저장소 범위. 새 서버 게임 DB나 기기 간 지급 동기화는 추가하지 않음.
- 실제 차량/Firebase QR 페어링, 실제 제공자 AI 답변 품질, 물리 기기의 한국어 STT/영어 TTS는 이번 에뮬레이터 검증과 구분.
- 신규 캐릭터 이야기 초안의 사람 검수는 여전히 필요.
- Unity export가 만든 모델/scene fileID churn과 iOS 자동 생성 설정은 제외. 같은 작업 공간에서 별도로 추가된 마을 캐릭터 상세/산책 UI 변경은 이번 커밋에 포함하지 않고 보존.
- 실제 API 키·로컬 토큰 파일·Unity 생성 라이브러리·APK는 Git에 포함하지 않음. 원격 배포나 dev 병합은 하지 않음.
