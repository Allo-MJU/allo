# T4 — Firebase 세션 정리 준비

검토일: 2026-11-04 (KST). 상태: **로컬 준비 완료, 정리 정책·운영 실행 미승인/미실행**.

- 검토 코드 기준: `011751328d1918c3a7695e9468cb9449a6932547 (dev)`
- 근거: [이슈 #23](https://github.com/Allo-MJU/allo/issues/23) 본문·댓글(조회 당시 OPEN, 댓글 없음), 현행 `firebase/database.rules.json`, `firebase/README.md`, `docs/schema.md` 3.2/3.6/3.7, `docs/verification.md`의 11/4 고아 세션 기록, `SessionManager.kt`의 생성·발행 순서.
- 변경 파일은 이 문서, `scripts/cleanup_sessions_dry_run.py`, `scripts/tests/test_cleanup_sessions.py`, `scripts/tests/fixtures/cleanup_sessions.json`뿐이다. 규칙·workflow·공용 문서는 수정하지 않았다.

## 1. 관찰 사실과 미결정 정책

현행 `$sid/.read`와 `.write`는 정상적인 `meta.createdAt`에 대해 경과 시간이 **24시간 미만**일 때 접근을 허용한다. 데이터 자체를 지우는 코드가 아니다. 따라서 정확히 24시간이 된 시점에는 접근이 만료되지만 세션은 DB에 남는다. 현재 Firebase README의 삭제 예시 `< now - 24h`는 이슈의 **24시간 이상** 및 접근 규칙의 경계와 다르며 `<=`로 맞춰야 한다.

`/sessions` 부모 read 허용이 없으므로 앱의 일반 REST 요청으로 전체 세션을 열거할 수 없다. 자식 read 허용은 부모 조회 권한이 아니며, 인덱스는 권한을 부여하지 않는다. 정리 때문에 부모를 공개하는 변경은 제안하지 않는다. 만료·고아 데이터는 운영자 콘솔이나 적절한 관리자 인증을 사용한 별도 경로가 필요하다. 이슈의 “콘솔에서만 삭제”는 현재 앱 권한 기준이며 관리자 REST까지 불가능하다는 뜻은 아니다. [Firebase 규칙의 적용 범위](https://firebase.google.com/docs/database/security/core-syntax)

현재 `createdAt`은 차량 기기의 `System.currentTimeMillis()`로 생성된다. 규칙은 숫자 타입, 불변성, 미래 시각을 검사하지 않는다. “생성 후 24시간 접근 제한”은 정상적인 변경되지 않는 timestamp를 전제로 한 설명이며, 서버 시각으로 검증된 보존 기간 보장은 아니다.

이슈 #23의 제안은 ① 24시간 이상 세션 삭제 ② meta 없는 고아 삭제 ③ 하루 1회다. **방식과 이 기준의 채택은 미결정**이다. 누락/잘못된/미래 createdAt의 처리, 고아 유예시간, 장시간 활성 세션 예외, 기기 시계 오차 허용값도 이번에 제품 정책으로 확정하지 않았다.

## 2. 구현한 로컬 dry-run

Python 표준 라이브러리만 사용한다. 네트워크·자격증명·파일 쓰기·삭제 기능이 없다. sessionId 목록을 내보내는 옵션도 없다. 출력은 건수·사유와 고정된 기준 시각이며 `policy=issue_23_proposal_not_approved`를 표시한다. `candidate`는 **제안 기준에 해당**한다는 의미이며 삭제 승인이나 실행 manifest가 아니다.

```bash
python3 scripts/cleanup_sessions_dry_run.py \
  scripts/tests/fixtures/cleanup_sessions.json --now-ms 1793761200000
```

입력은 `/sessions` 노드의 **raw 객체** `{sessionId: sessionObject, ...}`다. 루트 export의 `{"sessions": ...}` wrapper나 HTTP 응답 envelope는 받지 않는다. `--now-ms`는 재현성을 위해 필수인 음이 아닌 정수 epoch ms다. fixture 기준 시각은 **2026-11-04 12:00 KST**, cutoff는 `1793674800000`이다. 실제 현재 시각이나 운영 데이터를 사용하지 않는다.

| 입력 조건 | 사유 | 제안상 분류 |
| --- | --- | --- |
| 숫자 createdAt ≤ now − 86,400,000ms | `expired_24h` | candidate |
| cutoff < createdAt ≤ now | `recent` | keep |
| meta 누락/null, 남은 vehicle/game/events가 객체 | `orphan_missing_meta` | candidate |
| meta 객체에 createdAt 누락/null | `missing_created_at` | review |
| createdAt 문자열/bool/배열/객체 | `invalid_created_at_type` | review |
| createdAt < 0 | `invalid_created_at_value` | review |
| createdAt > now | `future_created_at` | review |
| meta가 객체가 아님 | `invalid_meta` | review |
| 세션이 객체가 아님, 빈 객체, 알려진 자식이 없음, 고아의 자식 타입이 잘못됨 | `invalid_session` | review |

스키마가 `number`이므로 유한한 소수 epoch ms도 숫자로 받는다. bool은 Python int의 하위 타입이지만 여기서는 거부한다. 0은 유효 숫자다. 초 단위 오입력을 추측해서 보정하거나 UUID/vehicle.ts를 생성 시각으로 대신 쓰지 않는다. 이는 전체 payload 스키마 검증기가 아니므로 후보를 실제 삭제하려면 별도 검토가 필요하다.

- 성공한 분류는 exit **0**이다. review가 있어도 분류 자체의 성공이므로, 호출자는 `counts.review`를 확인해야 한다. exit 0이 삭제 허가를 뜻하지 않는다.
- 읽기 실패, UTF-8 오류, JSON 파싱 오류, 중복 키, 비유한 수치(NaN/Infinity/overflow), 잘못된 루트/오류 envelope는 exit **1**, stdout 없음, 일반화된 `input_error`만 stderr에 남긴다. 경로·응답 본문·sessionId를 오류 메시지에 넣지 않는다.
- 인자 오류는 exit **2**다. `null`은 빈 성공으로 바꾸지 않고 오류로 처리한다. **확인된 빈 매핑 `{}`만** 0건 성공이다. 향후 네트워크 adapter가 200 + JSON null을 빈 DB로 처리하려면 HTTP 상태·대상 경로·응답을 먼저 검증한 뒤 명시적으로 `{}`로 정규화해야 한다. `response or {}` 같은 처리는 금지한다.
- 실제 export는 이 도구가 수집하거나 저장하지 않는다. 운영 snapshot을 Git이나 Actions 로그/기본 artifact로 올리지 않는다. 공개 집계에는 sessionId·pairCode·payload·자격증명이 없다.

### fixture와 검증 결과

21개 synthetic 세션: **candidate 5 / keep 4 / review 12**. 후보는 만료 3건과 고아 2건이다. 경계는 age **24h−1ms → keep**, **24h 정확히 → candidate**, **24h+1ms → candidate**로 각각 검증했다.

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
python3 scripts/cleanup_sessions_dry_run.py scripts/tests/fixtures/cleanup_sessions.json --now-ms 1793761200000
git diff --check
git diff --cached --check
```

결과: **8개 테스트 통과**, fixture 집계 일치, 공백 검사 통과. 개별 21건의 사유, 경계, 유효 숫자 0/소수, 누락·타입·미래 시각, 읽기/UTF-8/파싱/오류 envelope/중복 키 실패, 로그 비노출을 검사했다. 구현 전 실패를 확인했고, 별도 읽기 전용 리뷰가 찾은 잘못된 고아 자식 타입도 실패 재현 후 수정했다. Flutter/Kotlin 및 운영 Firebase 검증은 이 Python 전용 변경의 검증 범위에 포함하지 않았다.

## 3. 방식 비교와 추천안

저장소에는 현재 `.github/` workflow, Functions 구현, `firebase.json` 배포 설정이 없다. 운영 프로젝트 요금제·IAM·Secrets·실제 데이터 건수는 조회하지 않았다.

| 방식 | 현행 인프라 대비 준비 | 장점/한계 | 11/15 제출 추천 |
| --- | --- | --- | --- |
| 운영자 수동 정리 | 기존 콘솔 권한 + 실행 기록, 후보 검토·백업 | 신규 서버·장기 키 불필요. 잊으면 누적되므로 담당·시각·대체 담당 필요 | **현재 우선안.** 자동화를 검증하지 못한 상태의 제출 범위에 가장 작게 맞음 |
| GitHub Actions 하루 1회 | A workflow/실행기, C 관리자 인증/Secret/index, 실패 확인 담당 | 자동화와 코드 근거 확보. 관리자 자격증명 관리·스케줄 지연/누락 처리 필요 | 11/5 Go/No-go에서 자동화가 필요하면 채택할 대안. 검증 전 자동 삭제 활성화 금지 |
| Scheduled Cloud Functions | Functions 코드·배포 설정, Blaze, Scheduler/API/배포 권한 | Firebase 안에서 운영 가능. 현재 없는 기반·요금제 설정이 추가됨 | 이번 제출의 우선안으로는 비추천 |

이 표는 **조정 담당/팀의 결정을 위한 추천**이다. 수동을 선택해도 한 번만 지우고 끝내는 정책으로 쓰지 말고, 예를 들어 매일 12:15 KST와 제출 직전 점검처럼 실행 시각·담당자를 명시해야 한다. 이 시각은 제안이며 아직 배정되지 않았다.

Actions schedule은 기본 브랜치 기준이고 지연·누락될 수 있다. 정각을 피해 예를 들어 `15 3 * * *`(UTC 03:15 = KST 12:15)를 검토한다. 공개 저장소는 장기간 활동이 없으면 schedule이 비활성화될 수도 있다. 따라서 정상적으로 매일 실행돼도 보관 기간은 대략 **24~48시간**, 실패하면 더 길 수 있으며 “정확히 24시간에 자동 삭제”라고 설명하면 안 된다. [GitHub schedule 동작](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)

Functions 배포에는 Blaze가 필요하며 스케줄 함수는 Cloud Scheduler를 사용한다. 스케줄 실행이 겹칠 수도 있어 중복 실행에 안전해야 한다. [Functions 시작 안내](https://firebase.google.com/docs/functions/get-started), [스케줄 함수](https://firebase.google.com/docs/functions/schedule-functions)

## 4. Actions 선택 시 A/C 인수인계 계약안

### 담당과 권한

- **A:** workflow 및 향후 네트워크/삭제 실행기 작성. 기본 `dry-run`, 명시적 실행 모드, 고정 runNowMs, 환경/대상 DB 확인, timeout, 동시 실행 1개, 집계 로그와 실패 상태를 구현한다. 이 도구에 삭제 옵션을 덧붙인 것으로 간주하지 않는다. 기본 브랜치 반영과 수동 dispatch에는 저장소 write 권한이 필요하다. [수동 workflow 실행](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- **C:** 채택 후 조정 담당의 별도 운영 단계에서 전용 서비스 계정·인증 준비, GitHub Secret 등록, `.indexOn` 변경 검토/적용을 맡는다. 조직 저장소의 repository Secret 등록에는 write 권한, environment Secret 설정에는 admin 권한이 필요하다. IAM 역할 부여·서비스 계정/키 생성 권한은 GitHub 권한과 별개로 프로젝트 관리자가 확인해야 한다. [GitHub Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
- **프로젝트 관리자/실행자:** 대상 프로젝트의 RTDB 데이터 read/write 권한을 확인한다. `roles/firebasedatabase.admin`은 RTDB read/write를 제공하는 제품 역할 후보지만 `/sessions`만으로 제한된 삭제 전용 역할은 아니므로 범위를 확인하고, 일반 Owner/Editor를 편의상 추가하지 않는다. 규칙 배포 권한도 별도 확인한다. [Firebase 제품별 IAM 역할](https://firebase.google.com/docs/projects/iam/roles-predefined-product)

인증 계약 제안: 비밀이 아닌 `ALLO_DB_URL`(대상 host/project 확인)과 Secret `FIREBASE_CLEANUP_SERVICE_ACCOUNT_JSON`(이름도 제안이며 미등록)을 분리한다. `google-services.json`, 앱 API key, DB URL은 관리자 삭제 자격증명이 아니다. Secret 값·OAuth 토큰·전체 응답은 출력하지 않고 PR/포크 작업에 관리자 자격증명을 전달하지 않는다. workflow의 GitHub 권한은 checkout에 필요한 `contents: read`를 기준으로 줄인다.

서비스 계정 REST OAuth에는 `firebase.database`와 `userinfo.email` scope가 필요하다. 자격증명은 런타임에만 사용하고 Bearer header로 전달한다. 키 생성·조회·Secret 등록이나 기존 권한 확인은 **이번 작업에서 하지 않았다**. [Firebase REST 인증](https://firebase.google.com/docs/database/rest/auth)

### 조회 API와 선별 조건

인증된 `GET /sessions.json?orderBy="meta/createdAt"&endAt=<cutoffMs>`는 **선별의 1단계**일 뿐이다. 결과를 전부 삭제하면 안 된다. Firebase 정렬에서 null/누락 및 bool은 숫자보다 앞에 오므로 함께 걸릴 수 있으며, 문자열·객체·미래 시각 등은 이 쿼리에서 빠질 수 있다. 전체 이상 데이터 점검은 별도의 검증된 전체 snapshot이 필요하다. REST JSON 객체의 반환 순서에 의존하지 않는다. [REST 데이터 조회와 정렬](https://firebase.google.com/docs/database/rest/retrieve-data)

`limitToFirst`를 반복하면 검토 대상으로 남겨 둔 malformed 세션이 첫 페이지를 계속 차지할 수 있다. 큰 DB가 아니라면 먼저 크기를 확인하고 제한된 전체 export를 검증하는 방식이 단순하다. 페이지 처리 도입 시 동일 timestamp의 key tie-break와 중복/누락을 따로 검증해야 한다.

후속 실행기는 읽기 실패/401/403/429/5xx·timeout·잘못된 JSON을 실패로 처리한다. 출력 계약은 `scanned`, `candidate`, `review`, `deleted`, `skipped_changed`, `failed` 건수와 사유 중심이며, 부분 실패도 nonzero 종료해야 한다. dry-run 집계 자체는 이 문서 2장의 현행 도구 계약을 따른다.

## 5. 조정 담당에게 넘기는 공유 파일 제안

### `firebase/database.rules.json` 최소 index 패치 (미적용)

Actions의 필터 쿼리를 채택하면 `/sessions` 바로 아래에 추가한다. `$sid/meta` 아래가 아니다. 전체 snapshot을 수동 export해 점검하는 것에는 이 쿼리 인덱스가 필요하지 않다.

```diff
     "sessions": {
+      ".indexOn": ["meta/createdAt"],
       "$sid": {
```

REST 필터 쿼리에 필요한 index이며, 접근 허용·삭제·TTL을 수행하지 않는다. 실제 배포는 C/조정 담당의 별도 단계다. [Firebase index](https://firebase.google.com/docs/database/security/indexing-data)

### 삭제 후 재생성 및 시각 검증 보강 (별도 검토, 미적용)

현행 `.write`의 `!data.exists()`는 세션 전체 삭제 후 오래된 차량 클라이언트가 같은 sid의 `/vehicle`을 다시 PUT하는 것도 허용한다. `sessionReady`는 이미 완료되어 meta를 다시 쓰지 않을 수 있어 고아가 재생성된다. 삭제 직전 조건부 검사만으로 **삭제 후** 재생성을 막을 수는 없다.

규칙 보강 제안은 새 `$sid` 생성 분기를 다음처럼 제한하는 것이다. 기존 생성 코드가 meta를 먼저 쓰는지와 모든 seed/클라이언트 경로를 에뮬레이터에서 검증한 뒤 공유 계약으로 반영해야 한다.

```text
!data.exists()
→ (!data.exists() && newData.child('meta').hasChildren(['createdAt', 'pairCode', 'paired', 'carAppVersion']))
```

추가 제안: 남은 세션에는 meta 필수, createdAt 숫자 타입·불변성, read/write 시 숫자 여부 확인. 미래 timestamp 거부/허용 오차 및 서버 timestamp 채택은 A/C가 결정할 항목이다. 이번에는 read/write 규칙을 직접 바꾸거나 배포하지 않았다.

### `firebase/README.md` 교체 문구안 (미적용)

현재 “만료 데이터 정리” 절을 다음 문구로 교체하고, 선택된 방식·담당자·주기·마지막 성공 시각·미처리 건수·중지/복구 절차를 채워 넣는다.

> 정상적인 meta.createdAt 기준 세션 접근은 생성 후 24시간 미만까지 허용된다. 접근 만료와 물리 삭제는 별개이며 정리 방식은 현재 미확정이다. 이슈 #23의 제안 기준은 유효한 숫자 createdAt이 실행 기준 시각보다 24시간 이상 오래된 세션(createdAt ≤ runNowMs − 86400000)과 meta 없는 고아다. 누락·잘못된 타입·미래 createdAt은 별도 검토한다. 로컬 dry-run은 후보와 검토 건수를 출력할 뿐 삭제하지 않는다. 실제 정리는 담당자가 후보·대상 DB·백업을 확인하고 삭제 직전에 현재 값을 재검증한 뒤 관리자 권한으로 실행한다. 실행 기록에는 건수와 사유를 남기며 sessionId나 payload를 공개하지 않는다.

`docs/schema.md` 3.7, 루트 README의 “24시간 후 만료”, A의 기획서 개인정보 문구도 같은 구분으로 맞춰야 한다. 실제 DB에는 연결 키 외에 vehicle/game/events 임시 상태도 있으므로 “연결용 임시 키만”이라는 표현은 실제 저장 내용과 맞춰 검토한다. 문서상 자동 삭제 완료라고 미리 쓰지 않는다.

## 6. 운영 실행 전제·검증·복구 한계

아래는 **향후 조정 담당의 실행 절차**이며 이 작업에서 수행한 운영 조작이 아니다.

1. 11/5에 방식, 후보/고아 정책, 하루 주기, 담당·대체 담당을 정한다. 전체 `/sessions` 삭제는 정상 활성 세션도 지우므로 이번 도구의 후보별 정리와 구분해 별도 결정한다.
2. 실제 프로젝트/DB host·접속 권한을 확인하고, 관련 차량·폰 앱/시연 주입기를 중지한다. 현행 규칙의 삭제 후 재생성 문제를 해결하지 않았다면 자동 정리 활성화 전 별도 대책이 필요하다.
3. 승인된 범위의 snapshot과 대상별 백업을 접근 제한된 위치에 보관하고 보존/폐기 시점을 정한다. 백업을 레포나 공개 로그/기본 workflow artifact에 올리지 않는다. 건수·대상·실행 시각이 고정된 검토 기록을 남긴다.
4. emulator/격리된 테스트 DB에서 정상 보존, 경계 3종, 고아, 모든 잘못된 timestamp, 권한/HTTP/응답 실패, 부분 실패와 재시도를 검증한다. 이 문서의 로컬 fixture는 DB 권한·index·배포·실행기를 검증하지 않는다.
5. 실제 실행 직전 세션 **전체 경로**를 다시 GET하고 현재 구조·createdAt으로 재분류한다. REST 실행기라면 `X-Firebase-ETag: true`로 받은 동일 경로 ETag를 조건부 DELETE의 `If-Match`에 사용하고, 412는 변경됨으로 건너뛰어 다시 검토한다. `/meta`만 읽은 ETag로 세션 전체 삭제를 보호할 수 없다. 자동 재시도하며 무조건 삭제하지 않는다. 콘솔 수동 삭제는 이 조건부 보장을 제공하는 실행기로 간주하지 않는다. [Firebase 조건부 쓰기/삭제](https://firebase.google.com/docs/database/rest/save-data)
6. 삭제 후 남은 후보/고아 재생성·유지 세션 보존을 관리자 경로에서 확인하고, 삭제/건너뜀/실패 건수를 기록한다. 실패를 0건 성공으로 기록하지 않는다. 다음 실행에서도 확인하고 실패 담당자가 수동 대체 여부를 판단한다.

중지/롤백은 workflow 비활성화·진행 실행 취소·새 실행 차단, 필요 시 자격증명 회수다. 이것만으로 삭제 데이터는 복구되지 않는다. 복구는 백업과 현재 경로를 비교해 승인된 대상만 수행하며, 현재 새 데이터가 있으면 덮어쓰지 않는다. 전체 root snapshot import는 이후 정상 데이터를 덮어쓸 수 있다. 백업 이후의 변경, 클라이언트 메모리 상태, 이미 전달된 이벤트까지 되돌린다고 보장할 수 없다.

## 7. 인수인계 시 남은 항목

- **정책 미결정:** 수동/Actions/Functions, 후보 기준 채택, 고아 유예·검토, 시계 오차/미래 시각, 활성 세션 예외, 실행 주기·담당자, 백업 보존.
- **운영 미검증:** 실제 프로젝트/요금제/IAM/Secrets, 운영 세션 수·형태, 현재 배포 규칙, 인증·query/index·조건부 삭제, 작업 실패 알림·복구.
- **별도 실행:** A workflow/네트워크 실행기, C 인증·Secret/index, 공용 문서 변경, emulator/격리 DB 통합 검증, 승인된 운영 정리. 서비스 계정 생성·키 조회·Secret 등록·운영 삭제·규칙 배포·원격 push/PR/병합·팀 메시지는 수행하지 않았다.
- 산출 SHA는 이 파일의 내용을 포함한 최종 로컬 커밋이며 최종 채팅 보고에 명시한다(자기 참조 SHA를 문서 안에 넣지 않음).
