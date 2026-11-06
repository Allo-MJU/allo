# 알로(ALLO) 파트별 상세 로드맵

> 각자 이 문서의 자기 섹션만 보면 됩니다.
> 공통 규칙과 일정은 `dev-plan.md` 참조.

---

## 공통 — Day 1 오전에 전원이 함께

이거 먼저 끝내야 나머지가 병렬로 갑니다.

1. **Firebase 프로젝트 생성** (C 주도) — Realtime Database, 테스트 규칙으로 시작
2. **인터페이스 계약 확정** (A·C) — 스키마 문서화 후 전원 공유
3. **저장소 생성** — `main` 보호, 파트별 브랜치
4. **`git config user.name` 설정** — 실명 허용 (2026-11-03 팀 결정). 소속·연락처는 넣지 않는다
5. **에셋 네이밍 규칙 합의** (B·D) — 예: `species_water_t2.png`

---

# A — 차량 앱 · Pleos SDK · 기획서

가장 리스크가 큰 파트입니다. **검증을 먼저, 구현은 나중에.**

## A-1. 환경 구축 (Day 1, 반나절)

- [ ] Android Studio + SDK Platform 35 + JDK 17
- [ ] [Pleos Playground](https://pleos.ai/playground) 계정 생성 → 프로젝트 생성
- [ ] SDK 사용 신청 — Vehicle, NaviHelper (+ 가능하면 TTS/STT)
- [ ] Pleos Connect Emulator 설치 및 부팅 확인
- [ ] `settings.gradle.kts`에 Pleos Maven 저장소 등록
- [ ] [공식 샘플앱](https://github.com/Pleos-Playground/pleos-sample-vehicle-app) 클론 → `./gradlew installDebug` → Door Position 동작 확인

> 샘플앱의 `VehicleApiExplorer`가 19개 도메인 442개 메서드를 훑어줍니다. 검증할 때 이걸 쓰세요.

## A-2. 검증 8개 (Day 1~3) ← **최우선**

각 항목마다 "됨 / 안 됨 / 조건부"를 기록하고 전원에게 공유.

| # | 확인할 것 | 방법 | 실패 시 영향 |
| --- | --- | --- | --- |
| 1 | `Wiper` 값 갱신 | 에뮬레이터 adb로 와이퍼 상태 변경 후 리스너 수신 확인 | 속성 시스템 붕괴 |
| 2 | `Light`(전조등) 값 갱신 | 동일 | 어둠 속성 불가 |
| 3 | NaviHelper ETA 갱신 | 목적지 설정 후 주행 시뮬레이션, 주기 확인 | 부화 타이밍 1안 불가 |
| 4 | `Odometer` 해상도 | 짧은 거리 주행 시 값이 변하는지 | 거리 폴백 부정확 |
| 5 | `INTERNET` 권한 외부 호출 | 빈 앱에서 HTTP GET 한 번 | **폰 연동 전체 붕괴** |
| 6 | `CarUxRestrictions` 신호대기 판정 | 기어 D + 속도 0 상태에서 제한 상태 읽기 | 정차 공유 범위 축소 |
| 7 | Gleo 함수 등록 | `schema.json` 등록 시도 | 음성 기능 제외 |
| 8 | `Seat` 2열 점유값 반전 | 좌석 점유 토글하며 값 비교 | 상수로 뒤집어 처리 |

**5번이 실패하면 즉시 전원 회의.** 설계를 갈아야 합니다.

## A-3. 신호 수집 레이어 (Day 4~5)

```
app/
  vehicle/
    VehicleSignalReader.kt    # 도메인별 구독
    SignalDerivation.kt       # 파생 신호 계산
    EnvTagger.kt              # envTags 변환
  sync/
    SessionManager.kt         # 세션 생성 + 페어링 코드
    FirebasePublisher.kt      # 1초 주기 전송
```

**구현 순서**

1. `Vehicle(context)` 생성 → `initialize()` → 콜백 완료 대기
2. 도메인별 `checkXXXCapabilities()` 먼저 호출 — 미지원 신호는 수집 목록에서 제외
3. `registerXXX(listener)` 등록. **리스너가 세션보다 오래 살지 않게** `onDestroy`에서 해제
4. 속도는 **AAOS `CarPropertyManager`** 사용 (Vehicle SDK 속도 리스너는 2.3.2에서 삭제됨)
5. 좌석 점유는 반전 상수 적용 — `const val SDK_OCCUPIED = false`

**파생 신호 계산 규칙** (C와 임계값 합의)

- `harshBrakeCount` — 브레이크 압력 급상승 or 감속도 임계 초과
- `harshSteerCount` — 조향각 변화율 임계 초과
- `distanceM` — Odometer 델타, 해상도 부족 시 속도 적분
- `envTags` — `wiperLevel>0` → `rain` / `headlightOn && 주간` → `tunnel` / `speedKph>80 지속` → `highway`

> **위치 좌표는 절대 올리지 않습니다.** 지역 판정도 차량 앱 안에서 하고 태그만 보냅니다.

## A-4. 차 화면 UI (Day 8~9)

`CarUxRestrictionsManager.onUxRestrictionsChanged`로 두 모드 전환.

- **주행 중** — 한 줄 상태만. *"알이 자라는 중 · 60%"*
- **정차(기어 P)** — 게임 상태를 차 화면 레이아웃으로 렌더. 영상 미러링 아님, Firebase `game` 노드를 읽어 다시 그림
- **전환** — 기어 D 진입 시 즉시 주행 모드로. **이 전환이 PT 시연의 핵심 장면입니다**

## A-5. Gleo 음성 (Day 9)

`schema.json`에 함수 2~3개 등록

- `reportEggStatus` — *"뒷자리에서 희귀한 알을 품고 있어요"*
- `suggestDestination` — 미방문 지역 제안 → NaviHelper 목적지 설정
- `celebrateHatch` — 부화 시 운전자에게 알림

## A-6. 기획서 (Day 6~13)

- [ ] **MAU 리서치** — 통계청 가구 데이터로 "Pleos 탑재 대수 × 초등 자녀 가구 비율 × 설치율" 추정
- [ ] **Retention 목표치** — 벤치마크(D1 22%, D7 4%) 대비 목표 제시
- [ ] 공식 접수양식 다운로드 → 기존 내용을 양식에 맞춰 이식
- [ ] 팀 정보, 부문(일반) 기재

> 기획서는 2026-11-03 부터 A 담당 (원래 D-4). 부화 비율 등 설계가 바뀌면 문구도 A 가 고친다 (이슈 #3).

## A-7. 완료 기준

- [ ] 에뮬레이터 주행 시 Firebase에 1초마다 데이터가 쌓임
- [ ] 기어 P ↔ D 전환 시 차 화면이 즉시 바뀜
- [ ] Gleo 음성이 한 번이라도 발화됨
- [ ] `CONTROL_CAR_*` 권한을 선언하지 않음
- [ ] 기획서 공란 0개

---

# B — 폰 앱

**A를 기다리지 마세요.** Fake 어댑터부터 만들면 Day 1부터 풀속도로 갑니다.

## B-1. 셋업 + Fake 어댑터 (Day 1~2) ← **최우선**

- [ ] Flutter 프로젝트 생성 (핸들온 선례, iOS/Android 동시)
- [ ] Firebase 연결
- [ ] **`FakeVehicleFeed`** — 가짜 신호를 1초마다 주입하는 클래스

```dart
abstract class VehicleFeed {
  Stream<VehicleState> watch(String sessionId);
}
class FirebaseVehicleFeed implements VehicleFeed { ... }  // 나중
class FakeVehicleFeed implements VehicleFeed {            // 지금
  // 시나리오: 맑은날 / 비오는날 / 터널 / 거친운전
}
```

> 이 추상화가 있으면 A의 검증 결과와 무관하게 끝까지 개발됩니다. **PT 때 실기 연동이 불안정해도 시연이 됩니다.**

## B-2. 페어링 (Day 3)

- [ ] QR 스캐너 (차 화면의 QR 촬영)
- [ ] 6자리 코드 수동 입력 대안 — QR이 안 될 때
- [ ] `sessionId` 로컬 저장, 재탑승 시 자동 재연결

## B-3. 화면 구현 (Day 3~9)

**순서가 중요합니다. 품기 → 부화 → 동행 → 도감.**

### 품기 화면 (Day 3~5)

- 알 표시 + 성장 진행도
- 흔들림 반응 — `harshBrake`/`harshSteer` 수신 시 알이 흔들림
- 상호작용 2종
  - **감싸기** — 흔들릴 때 터치로 감싸주면 등급 보정
  - **노래** — 길게 누르면 알이 안정
- 진행 상태 — *"앞으로 12분"* or *"앞으로 8km"*

### 부화 화면 (Day 6~7) ← **가장 공들일 곳**

시연 영상의 하이라이트입니다. 연출에 시간을 쓰세요.

- 금 가는 연출 → 빛 → 등장
- 속성별 이펙트 차별 (물/어둠/일반)
- 등급 표시
- 차 화면과 동시 재생 (정차 시)

### 동행 화면 (Day 8)

- 생물 표시, 차 기울기에 따라 같이 기울어짐
- **창밖 보기 프롬프트** — *"저기 봐! 산이야"* + 영어 단어 1개
- 먹이 주기 / 놀아주기

### 도감 (Day 9)

- 그리드 + 빈칸(미수집)
- 상세: 영어 이름, 속성, 등급, **획득 날짜·장소·날씨**
- 로컬 저장 (서버 저장 안 함)

## B-4. 아트 통합 (Day 9~10)

D의 에셋을 받아 적용. 네이밍 규칙 지켜서 코드 수정 없이 교체되게.

## B-5. 완료 기준

- [ ] Fake 모드로 품기→부화→동행→도감 완주
- [ ] 실제 Firebase 모드로도 동일 동작
- [ ] 도감 데이터가 앱 재시작 후 유지됨
- [ ] 아동 개인정보 미수집 — 이름/생년월일/연락처 입력란 없음

---

# C — 게임 로직 · 연동

**앱에 의존하지 않는 순수 모듈**로 만드세요. 단위 테스트로 검증되므로 A/B와 무관하게 진행됩니다.

## C-1. Firebase 스키마 확정 (Day 1 오전) ← **팀 전체의 블로커**

A와 함께 반나절 안에 못 박고 문서화. 이후 변경은 C 승인 + 전원 공지.

- [ ] 스키마 문서 작성 및 공유
- [ ] Firebase 프로젝트 생성, 보안 규칙 초안
- [ ] 샘플 데이터 1건 수동 삽입 → B가 읽히는지 확인

## C-2. 희귀도 엔진 (Day 2~4)

```
RarityEngine
  input:  harshBrakeCount, harshSteerCount, 주행시간, envTags, eggTier
  output: tier (1~3), attribute (water|dark|normal)
```

**설계 원칙**

- 주행 품질 → **등급(tier)** 결정. 급제동·급조향이 적을수록 높음
- 환경 태그 → **속성(attribute)** 결정. `rain`→water, `tunnel`→dark, 없으면 normal
- 둘은 독립. 거친 운전으로도 물 속성은 나오되 등급이 낮음

**테스트 케이스**

- [ ] 급제동 0회 + rain → water, tier 3
- [ ] 급제동 10회 + rain → water, tier 1
- [ ] 태그 없음 → normal
- [ ] 태그 2개(rain+tunnel) → 우선순위 규칙 적용

## C-3. 부화 타이밍 엔진 (Day 5~6)

```
HatchTimer
  case A: etaSeconds 있음 → 총 ETA의 50% 지점
  case B: etaSeconds 없음 → eggTier별 목표거리의 50%
  이어하기: 세션 종료 시 progress 저장, 다음 주행에서 누적
```

| eggTier | 목표 거리 |
| --- | --- |
| small | 10km |
| mid | 50km |
| large | 150km |

**테스트 케이스**

- [ ] ETA 60분 → 30분 시점 부화
- [ ] ETA null + small 알 → 5km 시점 부화
- [ ] 3km에서 세션 종료 → 다음 주행 2km에서 부화
- [ ] 주행 중 ETA가 null→값으로 바뀌면 매끄럽게 전환

## C-4. 생물 데이터 테이블 (Day 6~7)

D와 함께 12종 확정. JSON으로 관리.

```json
{
  "speciesId": "tide_keeper",
  "nameEn": "Tide Keeper",
  "nameKo": "물결지기",
  "attribute": "water",
  "tier": 2,
  "hint": "비 오는 날 부드럽게 달리면"
}
```

12종 = 속성 3 × 등급 3 + 희귀 3

## C-5. 밸런싱 + 주행 재현 스크립트 (Day 8~9)

- [ ] 시뮬레이션 — 100회 주행 가정 시 종별 출현 분포가 적절한지
- [ ] **주행 재현 스크립트** — adb로 에뮬레이터에 시나리오 주입
  - `scenario_rainy_highway.sh` — 비 + 고속도로 + 부드러운 운전
  - `scenario_tunnel_rough.sh` — 터널 + 거친 운전
  - **PT 시연에 그대로 씁니다**

## C-6. 완료 기준

- [ ] 단위 테스트 전부 통과
- [ ] 시나리오 스크립트 2종 이상 동작
- [ ] 12종이 모두 획득 가능한 경로가 존재함

---

# D — 아트 · 영상

아트가 병목이 되기 쉽습니다. **스타일을 Day 1에 확정하고 양산하세요.**

## D-1. 아트 스타일 확정 (Day 1)

- [x] 캐릭터 스타일 — 스타일라이즈드 3D, `character-production-01` 12종 (11/5 승인. 도트 48×48안 폐기)
- [x] 색·글자·컴포넌트 — [`design-system.md`](./design-system.md) (11/6 확정 팔레트)
- [ ] 12종 데이터 정합 — G~L 6종이 `species.json`에 없음 (C 확인)

> **무료 도트 에셋 팩을 베이스로 변형**하는 걸 권합니다. 12종을 백지에서 그리면 2주에 못 끝냅니다. 라이선스는 반드시 확인하고 출처를 README에 표기.

## D-2. 알 + 생물 (Day 2~11)

| 시점 | 산출물 |
| --- | --- |
| Day 3 | 알 1종 (3단계 성장: 초기/중기/부화직전) |
| Day 5 | 생물 3종 (각 속성 1종, tier 2) |
| Day 7 | 누적 6종 |
| Day 9 | 누적 9종 |
| Day 11 | 12종 완료 |

**등급 차별화** — tier가 높을수록 실루엣이 복잡하고 장식이 많게. 색만 바꾸면 티가 안 납니다.

## D-3. UI 에셋 (Day 4~8)

- [ ] 버튼, 진행바
- [ ] 도감 프레임 (획득/미획득)
- [ ] 배경 — 주행 중 느낌의 단순 패럴랙스
- [ ] **부화 연출 프레임** — 금 가기 3컷, 빛 2컷. B와 협의

## D-4. 시연 영상 (Day 11~13)

**시나리오** — 비 오는 날 고속도로

1. 아이가 뒷자리에 탑승 → 좌석 감지 → 폰에 알림
2. QR로 페어링
3. 알 품기 시작, 와이퍼 작동 → 화면에 빗방울
4. 급제동 → 알 흔들림 → 아이가 감싸줌
5. **휴게소 정차 → 차 화면에 아이 화면이 뜸 → 가족이 같이 봄**
6. 부화! 물 속성 희귀종
7. Gleo 음성 — *"희귀한 아이가 깨어났어요"*
8. 동행 → 창밖 보기 → 영어 단어
9. 도착 → 도감 등록

- [ ] 화면 녹화 (에뮬레이터 + 폰)
- [ ] 편집, 자막
- [ ] 2~3분 이내

## D-5. 완료 기준

- [ ] 생물 12종 + 알 3단계
- [ ] 영상 3분 이내, 위 9단계가 전부 들어감
- [ ] README에 에셋 출처·라이선스 표기

---

## 통합 포인트 — 전원이 모이는 시점

| 시점 | 할 것 | 통과 조건 |
| --- | --- | --- |
| 11/3 오전 | 인터페이스 계약 확정 | 스키마 문서 공유 완료 |
| 11/5 | 검증 결과 공유 | Go/No-go 판단 |
| 11/9 | 1차 통합 | A 신호 → B 화면 도달 |
| 11/12 | **기능 동결** + 통합 테스트 | 핵심 루프 완주 |
| 11/14 | 최종 점검 | DoD 전 항목 충족 |
