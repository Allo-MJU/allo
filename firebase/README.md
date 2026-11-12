# Firebase

게임 상태 전달 저장소는 Realtime Database를 씁니다. 스키마는 `docs/schema.md` 3장이 기준입니다.

## 인증·세션 설정

실제 연결은 Firebase Authentication 익명 로그인, 서버 callable, RTDB 역할 규칙을 함께 사용한다. [인증·세션 계약 및 로컬 검증](AUTH_SESSION.md)을 따른다. 예전 무인증 규칙과 직접 meta 생성 경로는 더 이상 지원하지 않는다.

1. 개발용 Firebase 프로젝트와 Realtime Database를 준비하고 Authentication의 Anonymous 제공자를 활성화한다.
2. 폰 Android 앱 `ai.allo.allo_phone`을 등록한다. `phone/config/firebase.example.json`을 `firebase.local.json`으로 복사해 해당 앱 설정과 DB 루트 URL, Functions region을 채운다. 현재 코드는 명시적 FirebaseOptions 초기화를 사용한다.
3. 차량 `car/local.properties`에 `ALLO_DB_URL`, `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `FIREBASE_FUNCTIONS_REGION=asia-northeast3`를 넣는다. 차량은 Firebase SDK 대신 REST 인증을 사용한다. 서비스계정 키를 앱에 넣지 않는다.
4. 서버의 `createVehicleSession`/`joinVehicleSession`/`renewVehiclePairing`과 이 디렉터리의 rules를 같은 프로젝트에 배포한 뒤 새 세션으로 연결한다. 기존 ACL 없는 세션은 규칙에서 차단된다. 이번 작업은 로컬 구현/검증이며 실제 배포를 실행하지 않았다.
5. Functions 배포에는 Blaze 요금제가 필요하다. 결제 설정이나 플랜 변경은 이번 작업에서 하지 않는다. [공식 배포 안내](https://firebase.google.com/docs/functions/get-started)

## 권한 요약

- 서버가 세션 `acl`과 `meta`를 만들고 폰 한 대의 가입을 확정한다. 클라이언트는 이 값을 바꿀 수 없다.
- 인증된 세션 참여자만 meta/vehicle/game/events를 읽는다. 루트 목록과 acl/pairing 비밀 읽기는 차단한다.
- 차량 소유 UID만 vehicle, 가입된 폰 UID만 game을 작성한다. 이벤트는 역할과 type이 일치하는 새 항목만 허용한다.
- 신규 폰 연결 코드는 10분 유효하며 오입력 5회 후 잠긴다. 동일 폰의 재연결은 세션 24시간 안에서 허용하며 종료 세션은 재사용하지 않는다.
- 일반 앱은 모의 낚시 진입점과 별개이며, 모의 샘플 친구를 실제 도감에 자동 복사하지 않는다.

## 매일 만료 세션 정리 — 준비 상태

`.github/workflows/cleanup-sessions.yml`과 `scripts/cleanup_sessions.py`는 매일 정리를 위한 **준비 코드**입니다. 키·IAM·repository variables를 등록하거나 workflow를 활성화·실행한 상태가 아닙니다. 적용 전 A workflow 담당자와 함께 검토합니다.

- 기준: 실행 시작 때 한 번 고정한 `runNow`에서 유효한 숫자 `meta/createdAt`이 **24시간 이상** 지난 세션만 자동 삭제 후보입니다. 정확히 24시간 경계도 포함합니다.
- 정상 세션은 보존합니다. `meta` 없는 orphan, timestamp 누락·잘못된 형식·음수·미래 값은 `review`로 집계하고 자동 삭제하지 않습니다. 생성 중인 세션과 구분할 근거 및 운영 정책이 아직 없습니다.
- 기존 `cleanup_sessions_dry_run.py`의 분류 함수를 재사용하되, 기존 issue #23 제안의 orphan 후보 매핑은 자동 정리에 적용하지 않습니다. 기존 fixture dry-run의 `candidate` 수와 새 실행기의 수는 다를 수 있습니다.
- Firebase 보안 규칙은 접근을 제한할 뿐 물리 삭제를 하지 않습니다. 이 작업의 서비스계정 인증은 규칙을 우회할 수 있어 IAM 검토가 필요합니다.

### 실행 조건과 제안 시간

제안 주기는 매일 **UTC 03:15 / KST 12:15**입니다. GitHub schedule은 기본 브랜치에서 실행되며 지연·누락될 수 있습니다. 세션 생성 24시간 정각의 삭제나 일정한 보관 기한을 보장하지 않습니다. 정상적인 하루 주기에서도 24시간을 넘긴 뒤 다음 실행까지 기다립니다.

| 설정 / 실행 | 동작 |
| --- | --- |
| `ALLO_CLEANUP_READY` 없음 또는 `true` 아님 | job 전체를 건너뜀. 인증·DB 요청 없음 |
| READY=`true`, APPLY_ENABLED 없음/false | schedule 및 기본 수동 실행은 dry-run |
| 수동 `apply=false` (기본값) | APPLY_ENABLED 값과 무관하게 dry-run |
| 수동 `apply=true`, APPLY_ENABLED=`true` | 개별 재조회 후 조건부 삭제 |
| 수동 `apply=true`, APPLY_ENABLED 없음/false | 인증·DB 요청 전에 실패 |
| schedule, READY=`true`, APPLY_ENABLED=`true` | 실행기에 `--apply`를 명시해 조건부 삭제 |

수동 실행도 기본 브랜치만 허용합니다. `--apply` 없는 CLI는 DELETE를 보내지 않습니다. 실제 삭제는 `--apply`와 환경의 `ALLO_CLEANUP_APPLY_ENABLED=true`가 모두 있어야 합니다. 중지하려면 READY를 false로 바꾸면 이후 job이 멈추고, APPLY_ENABLED를 false로 바꾸면 이후 schedule은 dry-run이 됩니다. 진행 중인 실행은 별도로 중단해야 합니다.

### 추후 소유자가 검토할 설정

이 문서는 아래 값을 등록하거나 IAM을 변경할 권한을 부여하지 않습니다. 검토 후 소유자가 별도로 설정합니다. 실제 키·토큰은 문서, 코드, 채팅, 실행 로그에 붙여 넣지 않습니다.

| GitHub 위치 | 이름 | 용도 |
| --- | --- | --- |
| Repository variable | `ALLO_DB_URL` | Firebase 콘솔의 HTTPS DB 루트 URL. 기본값 없음 |
| Repository variable | `ALLO_FIREBASE_PROJECT_ID` | URL과 서비스계정 키의 프로젝트를 대조할 명시적 project ID |
| Repository variable | `ALLO_FIREBASE_SERVICE_ACCOUNT` | 정리 전용 서비스계정 이메일 |
| Repository secret | `ALLO_FIREBASE_SERVICE_ACCOUNT_JSON` | 해당 계정의 서비스계정 JSON 키. runtime에서만 auth action에 주입 |
| Repository variable | `ALLO_CLEANUP_READY` | 검토·설정 완료 후에만 문자열 `true`. 초기에는 미등록 유지 |
| Repository variable | `ALLO_CLEANUP_APPLY_ENABLED` | 실제 삭제의 별도 opt-in. 초기에는 미등록 유지 |

현재는 기존 OIDC 설정이 확인되지 않아 서비스계정 키 방식의 최소 경로를 준비했습니다. Google auth action을 공식 저장소의 v3.0.0 commit에 고정했고, 600초 OAuth access token을 생성합니다. Firebase에 필요한 `firebase.database`, `userinfo.email` scope만 요청하며 토큰은 `Authorization: Bearer` 헤더로 전달합니다. 인증 파일을 만들거나 credential 환경변수를 전역으로 내보내지 않습니다. Python은 표준 라이브러리만 사용합니다.

키는 장기 자격증명입니다. 정리 전용 계정에 대상 DB 데이터 접근과 토큰 생성에 필요한 최소 권한만 검토해 부여하고 Owner/Editor나 공용 관리자 키는 쓰지 않습니다. auth action 문서상 키 계정으로 access token을 생성하려면 그 계정 자체에 대한 `roles/iam.serviceAccountTokenCreator`가 필요합니다. 실제 Firebase 데이터 권한과 IAM Credentials API 사용 가능 여부는 운영 소유자가 검증해야 합니다. OAuth scope는 `/sessions` 경로 권한 제한을 보장하지 않으며, 이 실행기의 경로 제한만으로 IAM 최소 권한을 대체할 수 없습니다.

키 회전 주기·담당자를 정하고 교체 후 이전 키를 폐기합니다. 키/토큰/세션 ID/payload/응답 본문을 echo하거나 shell tracing·추가 debug 로그·artifact 업로드로 남기지 않습니다. 실행기는 집계만 출력하며 외부 오류 본문도 출력하지 않습니다. workflow가 신뢰하는 기본 브랜치 및 workflow 수정 권한을 제한합니다. 추후 OIDC 전환은 별도 권한·trust 설정 검토 후 진행합니다.

### 실행기 안전 경계와 규모 제한

- URL은 project ID에 대응하는 기본 DB host만 허용합니다: `<project>.firebaseio.com`, `<project>-default-rtdb.firebaseio.com`, `<project>-default-rtdb.<region>.firebasedatabase.app`. HTTPS 루트만 허용하고 사용자 정보·포트·query·fragment·하위 경로·다른 project는 거부합니다. 커스텀 이름의 다중 DB는 지원하지 않습니다. redirect와 환경 proxy를 사용하지 않습니다.
- `/sessions.json`을 한 번 읽는 소규모 스캔입니다. 페이지 처리는 하지 않습니다. 초기 응답 **5 MiB**, **1,000개 세션** 상한을 넘으면 어떤 삭제도 시작하지 않고 실패합니다. 읽기/파싱/인증 실패를 빈 DB로 취급하지 않습니다. HTTP 200의 JSON `null` 또는 `{}`는 확인된 빈 DB이며 성공할 수 있지만, HTTP 200의 빈 body는 실패입니다.
- 삭제 직전 개별 `/sessions/<sid>.json`을 `X-Firebase-ETag: true`로 다시 읽고 같은 `runNow` 기준으로 다시 분류합니다. 여전히 만료 상태인 경우에만 받은 ETag를 `If-Match`로 보내 DELETE합니다. 재조회 후 데이터가 바뀌어 412가 오면 `skipped_changed`로 보존하고 재시도하지 않습니다. 재조회 때 이미 삭제되었거나 후보가 아니면 역시 보존합니다.
- 요청의 소켓 timeout은 최대 10초이고 각 요청 전후 240초 실행 예산을 확인합니다. 이는 응답이 조금씩 계속 오는 단일 요청을 정확히 240초에 중단하는 강제 제한은 아닙니다. workflow 전체의 최종 제한은 6분입니다. 실패 요청을 자동 재시도하지 않습니다. 이미 일부 삭제한 뒤 나머지 읽기/삭제가 실패하면 집계를 출력하고 exit 1로 끝납니다. 원자적 일괄 삭제나 rollback은 제공하지 않습니다.
- 결과의 `counts.candidate`는 최초 스캔 기준이며 `deleted`, `skipped_changed`, `failed`는 apply 결과입니다. 후보 0건도 검증된 응답이면 성공입니다. 상한에 닿거나 실행이 실패하면 소유자가 aggregate와 권한·규모를 확인합니다. 규모가 커지면 인덱스 및 cursor 기반 스캔을 별도 설계해야 하며, 현재는 `database.rules.json` 변경이 필요 없습니다.

### 로컬 모의 검증

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_cleanup_sessions*.py'
```

새 실행 테스트는 `urlopen`을 합성 응답으로 교체합니다. 실제 Firebase, 자격증명, GitHub workflow를 호출하지 않습니다. 기존 fixture 분류 테스트도 함께 실행합니다. 운영 권한·실제 REST 응답·Actions 등록/스케줄은 검증하지 않았습니다. 배포/활성화 전에는 별도로 허가받은 비운영 환경에서 dry-run 집계와 IAM을 먼저 확인해야 합니다.

공식 근거(2026-11-04 확인): [Firebase REST 인증](https://firebase.google.com/docs/database/rest/auth), [REST API와 ETag 조건부 요청](https://firebase.google.com/docs/reference/rest/database), [Google auth action](https://github.com/google-github-actions/auth/tree/7c6bc770dae815cd3e89ee6cdf493a5fab2cc093), [GitHub schedule 제약](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).
