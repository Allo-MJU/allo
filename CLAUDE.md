# ALLO — Claude Code 작업 지침

뒷자리 아이용 차량 연동 수집 게임. 공모전 출품작. 전체 맥락은 `docs/` 참고.

## 먼저 읽을 것

- `docs/schema.md` — **계약서.** Firebase 스키마와 레포 구조. 여기 어긋나는 코드를 쓰지 않는다
- `docs/roadmap.md` — 파트별(A 차량 / B 폰 / C 로직 / D 아트) 할 일

## 절대 규칙

1. **`CONTROL_CAR_*` 권한을 manifest에 넣지 않는다.** 읽기 권한(`CAR_*`, `READ_*`)만. 선언하면 심사 탈락
2. **위도·경도를 Firebase에 쓰지 않는다.** 차량 앱 안에서 `envTags`로 변환한다
3. **아이 개인정보 입력란을 만들지 않는다.** 이름·생년월일·연락처 금지
4. **블라인드 심사.** 코드·README·커밋에 실명·소속·연락처 금지. 커밋 전 `git config user.name` 확인
5. **판정은 폰(`allo_core`)에서만.** 차량 앱은 raw 신호 전송, 차 화면은 `/game` 읽어서 표시만
6. **`schema.md` 변경은 C 승인 + 전원 공지.** 코드 먼저 고치지 말고 문서 먼저

## 스택

| 영역 | 도구 | 빌드·테스트 |
| --- | --- | --- |
| `car/` | Kotlin, Compose, Pleos Vehicle SDK 2.3.2, Firebase RTDB | `cd car && JAVA_HOME=<jdk17> ./gradlew testDebugUnitTest assembleDebug` |
| `phone/` | Flutter | `cd phone && flutter test` |
| `phone/packages/allo_core/` | 순수 Dart (Flutter 비의존) | `cd phone/packages/allo_core && dart test` |
| `scripts/` | bash + curl (Firebase REST) | `ALLO_DB_URL=... scripts/seed_firebase.sh` |

## 알려진 SDK 제약 (docs/proposal.md 기술 활용성 참조)

- Vehicle SDK 속도 리스너는 2.3.2에서 삭제 → AAOS `CarPropertyManager`로 속도 조회
- 좌석 점유값이 반전돼 옴 → `SeatPolarity.SDK_OCCUPIED` 상수 한 곳에서 처리
- 차종별 지원 신호가 다름 → `checkXXXCapabilities` 먼저 호출, 결과를 `/vehicle/capabilities`에 기록
- 성능 기준: 주행 중 CPU 5% 미만, RAM 400MB 이하 → 차량 앱은 경량 유지

## 브랜치

`main` 보호. 파트별 `feat/car`, `feat/phone`, `feat/logic`, `feat/art`.
