# T3 지역 수집·추천 계약 검토

작성일: 2026-11-04 (KST). 산출물은 설계안과 fixture이며 **스키마 승인이나 기능 구현 완료가 아니다.**

- 검토 코드 기준: `011751328d1918c3a7695e9468cb9449a6932547 (dev)`
- 변경 범위: 이 문서와 `docs/work-results/fixtures/T3-region-cases.json`만. 제품 코드·공용 스키마는 수정하지 않았다.

## 1. 조정 담당이 채택할 수 있는 최소안

추천은 **현재 기기의 도감에 수집 기록이 없는 지역 유형**을 기준으로 한다. 실제 방문 여부를 추정하지 않는다. 집계안을 채택한다면 폰에서 알 지급→부화 동안 관측한 지역 시간을 누적하고, 결과 한 개 또는 미확정(null)을 기존 `DexEntry.regionTag`에 저장한다. 부화 후 동행은 제외한다. 도감 전체는 로컬에 유지하고 `/game`에는 추천용 요약 두 필드만 보낸다.

다음은 구현자가 제안하는 최소안이다. ① 수집 의미·지역 집계 정책 결정, ② C의 schema 반영 및 전원 공유, ③ 폰 모델·저장·controller 통합과 차량 소비 구현 순으로 진행한다. 이번 결과만으로 ①~③을 완료 처리하지 않는다.

| 구분 | 상태와 근거 |
| --- | --- |
| 현재 기기의 도감에 지역 수집 기록이 없는 유형을 추천 | **사용자 확정**. 방문 이력·기기 간 이력으로 확대하지 않는다. |
| 알 지급→부화까지 가장 오래 머문 coast/mountain/city를 수집 지역으로 기록 | **사용자 제안, 미확정**. 40분 품기의 city 25분 / mountain 10분 / coast 5분 예시는 이 안을 설명한다. |
| `regionCollectionKnown` + `uncollectedRegions`, unknown/후보 없음 구분 | **C 조정안, A 동의 댓글 있음**. 공용 schema와 제품 코드는 아직 미반영. B 저장·전송 연결 확인 필요. |
| 빈 도감도 지원 버전의 정상 로드·검증 후 known=true, 과거 null 기록은 수집으로 세지 않음 | **A 제안**. 빈 기록이라는 이유만으로 true가 되는 것은 아니다. 아래 권고는 버전·마이그레이션·로드 성공을 추가 조건으로 둔다. |
| 시간 기준·TTL·미확정 판정·중단 처리·과거 기록 호환 | **이번 구현자 권고**. 사용자 확정으로 인용하지 않는다. |

## 2. 실제 소스·최신 원격 대조

2026-11-04 조회 시 `gh pr view`, `gh api`, `git ls-remote`로 원격 head를 확인하고 같은 SHA의 로컬 Git object를 읽었다. GitHub 연결 도구는 404를 반환해 인증된 gh 읽기 조회를 사용했다. 원격 push/fetch·PR 변경·Firebase 접근은 하지 않았다.

| 소스 | 확인한 버전 / 관찰 |
| --- | --- |
| [이슈 #9](https://github.com/Allo-MJU/allo/issues/9) | [C 댓글](https://github.com/Allo-MJU/allo/issues/9#issuecomment-6623302919), [A 답변](https://github.com/Allo-MJU/allo/issues/9#issuecomment-6624402975)을 포함해 읽었다. A는 필드 의미에 동의하고 schema 반영 뒤 구현하겠다고 답했다. |
| [PR #22](https://github.com/Allo-MJU/allo/pull/22) | head `2fc5b883421158a09e129837da2e5228ee8521c1`, base `016aea6f836cbc9c61a2b002f0e18d0732634ce8`. `game_controller.dart:205–245,275–283,306–336`에서 새 알 및 매 신호마다 GameState를 새로 생성하며, 지역은 여전히 `seenTags...firstOrNull`. 지역 계약 구현을 미룬 PR이다. |
| [PR #25](https://github.com/Allo-MJU/allo/pull/25) | head `2cf1903516f1f637b627c60ed29c67355b3e8d19`, API상 base SHA `a55173299051fdba559273df54be1f14e8448d30`. head는 #22 최신 head와 별개라 조정 시 재통합 필요. `game_controller.dart:219–259,270–352,386–434`에 새 상태 생성, 첫 지역 선택, 저장 재시도, 마지막 vehicle 읽기가 있다. 지역·반복 시간 정책은 PR 범위 밖이다. |
| 시작점 폰 | `phone/lib/game/game_controller.dart:48–60,63–91`도 첫 지역 선택. PR #22/#25의 저장·종료 보완을 되돌리는 패치를 제안하지 않는다. |
| 로컬 도감 | #22 `phone/lib/storage/dex_store.dart:8–25,28–69`: `dex.entries.v1`, `hatch.progress.v2.<tier>`, 과거 `hatch.carried.v1.<tier>` 읽기. 진행 기록은 carriedM+sessionDistances이며 지역 집계·eggId·복구 자료가 없다. #25는 add 저장 실패 반환도 검사한다. |
| 공용 모델·전송 | #22 `phone/packages/allo_core/lib/src/models.dart:79–131`의 GameState에는 제안 필드가 없다. #25 `phone/lib/feed/firebase_feed.dart:80–82`도 `/game.set(state.toJson())`. DB에 수동으로 키를 붙여도 다음 set에서 지워진다. |
| 차량 지역 | 시작점 `RegionTagger.kt:11–16,23–68`은 참조 지점 주변 원형 영역으로 분류하며 coast→mountain→city 우선순위로 최대 한 지역만 반환한다. 미분류·위치 없음은 null. `EnvTagger.kt:27–40`은 다른 환경 태그와 지역 태그 한 개를 함께 보낸다. 실제 지리 경계나 체류의 정답을 보증하는 분류기는 아니다. |
| 차량 발행·위치 | 시작점 `SessionManager.kt:201–234`는 PUT을 기다린 뒤 1초 delay하므로 정확한 1Hz가 아니다. GPS poll도 10회 루프마다다. `NaviEtaReader.kt:30–32,63–65,79–97`은 위치 시각·만료 없이 마지막 값을 유지한다. 새 `vehicle.ts`가 와도 지역이 오래된 GPS일 수 있다. |
| 차량 추천·JSON | 시작점 `SessionManager.kt:104–113`은 `unvisitedRegions=null` 고정. `DestinationSuggester.kt:66–82`는 null=기본, empty=후보 없음, 현재 지역 제외+120km 제한을 적용한다. `Models.kt:40–52`에는 두 필드가 없고 `FirebaseRest.kt:42`는 ignoreUnknownKeys=true다. |
| [PR #24](https://github.com/Allo-MJU/allo/pull/24) 보정 확인 | `700ddb8778db84aea499edca9142f1391222f04c`의 `SessionManager.kt:121–128`, `DestinationSuggester.kt:138–143`, `NaviEtaReader.kt:102–107`은 SDK 호출 준비·실패를 확인한 뒤 accepted를 보낸다. 시작점의 무조건 accepted 문제를 새 미수정 이슈로 복제하지 않는다. 다만 성공은 SDK 요청이 예외 없이 반환됐다는 뜻이며 비동기 안내 시작까지 확인한 것은 아니다. 두 지역 필드와 GPS 만료는 여전히 없다. |

게시 전 추가 확인: PR #25는 `9b7e18c07689b917cdba9360829b999b85086d6d`로 갱신됐다. 위 표의 #25 행은 최초 검토 snapshot을 가리킨다. 새 head의 저장 실패 시 구독 pause/resume 등 보완을 확인했으며, 첫 지역 선택과 지역 요약 미전송이라는 이 문서의 핵심 관찰은 유지된다. 구현 시에는 새 head 위에서 통합한다.

경로가 짧게 표시된 차량 파일은 `car/app/src/main/java/ai/allo/car/` 아래다. 이 문서 1장의 확정/제안 구분을 기준으로 검토했다. 아래 권고는 공용 `docs/schema.md`에 반영된 확정 계약이 아니다.

## 3. 집계 접근 비교와 시간 입력 계약 — 권고, 미채택

| 접근 | 장점 | 한계 / 판단 |
| --- | --- | --- |
| 태그 수신 횟수 또는 첫 태그 | 작음 | 느린 PUT·재연결·주기 차이가 지역 결과를 바꾼다. 요구하는 시간 집계에 맞지 않는다. |
| 차량 `ts` 차이 누적 | 차량 관측 간격을 반영 | 현재 ts는 GPS 취득 시각이 아닌 벽시계 발행 시각이다. 폰의 지급/부화 시각과 시계 오차가 있고, ts 점프·재전송·복구 매핑이 추가로 필요하다. 향후 차량 관측 이력/sequence가 있으면 재검토한다. |
| **폰의 단조 증가 시각으로 관측 구간 누적, 차량 ts는 순서 검사** | 기존 payload 유지, 폰이 관리하는 알 경계와 같은 시계, 벽시계 변경 영향 없음 | **권고**. 수신 지연 때문에 실제 체류가 아닌 관측 체류의 근사다. 최초 캐시·신호 단절·GPS 만료를 unknown으로 다루어야 한다. |

순수 Dart 모듈 후보: `phone/packages/allo_core/lib/src/region_accumulator.dart`. 이 문서의 API는 제안이며 파일을 만들지 않았다. `atMs`는 폰 어댑터가 주입하는 단조 증가 밀리초이고 `vehicle.ts`와 빼거나 더하지 않는다. `_now=DateTime.now()`로 대체하지 않는다. 프로세스 재시작 시 저장된 논리 시각 뒤로 재기준화하고, 중단의 벽시계 경과는 자동 합산하지 않는다.

```text
beginEgg(eggId, atMs, maxHoldMs=5000)
observe(eggId, feedEpoch, sessionId, sourceTsMs, atMs, envTags,
        trustedFresh) -> accepted | duplicate | outOfOrder | wrongEpoch | closed
breakContinuity(atMs, newFeedEpoch, newSessionId)  // 같은 session은 source cursor 유지
pause(atMs) -> RegionCheckpoint
restorePaused(checkpoint)                       // 같은 eggId; 열린 관측 없음
resume(atMs)
finish(eggId, hatchAtMs) -> RegionResult         // 한 번 확정, 재호출 동일 결과

RegionResult {
  eggId, durationMs:{coast,mountain,city}, unknownMs, activeMs,
  regionTag:String?, reason:uniqueWinner|tie|insufficient|noRegion
}
RegionCheckpoint {
  version, eggId, durationMs, unknownMs, activeMs, lastAtMs,
  feedEpoch, sessionId, lastSourceTsMs, paused:true, maxHoldMs
}
```

`feedEpoch`는 폰 내부 연결 세대이며 Firebase 필드가 아니다. 콜백을 만들 때 eggId/연결 세대를 캡처하여 이전 알·이전 구독의 지연 콜백을 버린다. snapshot만으로 새 알을 지급하거나 차량 세션 변경을 알 회차 변경으로 간주하지 않는다.

### 구간 계산 규칙

1. 지급 시점 이전·부화 이후는 집계하지 않는다. 반열린 구간 `[issuedAt, hatchAt)`만 인정한다. 한 지역이 나타난 관측은 그 시각부터 다음 유효 관측까지 유지되는 것으로 근사한다. 부화 시점의 새 태그는 이전 구간에 소급하지 않는다.
2. `coast/mountain/city`와 교집합이 정확히 1개면 그 지역, 0개면 unknown이다. `rain/night/tunnel/highway`는 무시한다. 지역이 여러 개면 unknown으로 남긴다. `water/dark/normal`은 생물 속성이므로 지역으로 변환하지 않는다. 중복된 같은 태그는 집합으로 정규화한다.
3. 이전 관측부터 d ms 경과 시, 그 관측의 지역에는 `min(d, maxHoldMs)`만 준다. 남은 시간은 unknown이다. 이전 관측 자체가 unknown이면 d 전체가 unknown이다. 최초 관측 전 시간도 unknown이다. 합은 항상 `coast+mountain+city+unknown=activeMs`다. `maxHoldMs=5000`은 **제안값**이며 A의 실제 수신 간격 측정 후 확정한다.
4. 같은 연결 세대의 `sourceTsMs`는 정수 양수여야 한다. 동일 ts는 내용이 달라도 중복으로 버리고, 작은 ts는 역순으로 버린다. 둘 다 지역 유지시간을 연장하지 않는다. `atMs`가 뒤로 가는 관측도 버린다. 큰 ts 점프는 체류에 더하지 않는다. source 시계가 뒤로 바뀌어도 같은 session의 cursor는 자동 reset하지 않는다. 마지막 인정 ts를 다시 넘을 때까지 unknown이 될 수 있다. 새 차량 세션으로 명시적으로 재연결한 경우에만 cursor를 비우며 첫 캐시는 unknown부터 시작한다. 단지 역순 패킷이 왔다는 이유로 새 세션을 만들지 않는다.
5. `trustedFresh=false`는 캐시/신선도 미확인 관측이다. 순서가 유효하면 그 시각에 이전 구간을 닫고 새 열린 지역을 unknown으로 둔다. 구독 직후 최초 RTDB snapshot은 캐시일 수 있으므로 false로 취급한다. 이후 증가한 source ts의 live 발행을 확인하고, A의 GPS 만료 처리가 함께 적용되어야 true로 취급할 수 있다. 단일 `/vehicle`로 서버에 덮어써진 구간을 복원하지 않는다.
6. stream 오류·끊김에는 마지막 지역을 무한 유지하지 않는다. 오류가 확인되면 `breakContinuity`로 자르고, 이후 live 관측까지 unknown이다. 오류가 통지되지 않아도 5초 상한이 작동한다. 같은 세션 재연결은 누적 합과 source cursor를 보존하며 캐시 재수신은 다시 더하지 않는다. 새 세션은 새 세대+빈 source cursor를 쓰되 같은 알을 재개할지는 별도 정책이다. fixture의 e2/s2 첫 관측은 캐시(false), 다음은 검증된 live(true)로 명시했다.
7. 품기 종료 시 `finish`가 꼬리 구간도 동일한 상한으로 닫고 결과를 고정한다. 시간 엔진이 이미 알고 있는 실제 부화 경계가 있으면 늦은 콜백 시각 대신 그 경계에서 자른다. **경계가 pending 관측보다 과거면 관측 적용 전에 먼저 finish해야 한다.** 처리 순서는 `경계까지 닫기 → 부화 확정 → 동행/새 알 → 이후 관측`이다. 지나간 결과를 태그로 다시 고치지 않는다.

수신 주기가 1초→4초로 바뀌어도 같은 지역 전환 시각을 관측하고 상한 이내라면 시간 합·결과가 같다. 전환을 놓쳤거나 지연·batch 전달됐다면 같음을 보장하지 않는다. 현재 payload로 실제 경로·실제 체류를 재구성한다는 주장을 하지 않는다.

### 동률·미확인 시간이 있을 때 — 권고

최대 관측 시간이 0이면 `regionTag=null, reason=noRegion`. 공동 최대이면 null/tie. 단독 최대 W, 두 번째 S, 미확인 U에 대해 **`W > S + U`일 때만** 해당 지역을 기록하고, 아니면 null/insufficient를 권고한다. unknown 전부가 경쟁 지역이었다고 가정해도 순위가 유지되는 경우만 확정하는 보수적인 안이다. 예를 들어 city 10분+unknown 30분은 city로 정하지 않는다. unknown을 city로 채우거나 동률을 첫 수신/사전순으로 깨지 않는다. 별도의 최소 체류 분 기준은 이 안에 추가하지 않았으며 필요하면 제품 정책으로 정한다.

### GPS 신선도: A에 필요한 작은 수정안

폰의 5초 전송 상한만으로 오래된 GPS가 계속 새 ts로 발행되는 문제는 해결되지 않는다. `NaviEtaReader`가 위치와 수신 시각을 한 값 `PositionSample(point, receivedAtElapsedMs)`으로 보관하고 `freshPosition(maxAgeMs)`를 제공하는 안을 권고한다. Android `SystemClock.elapsedRealtime()`으로 나이를 계산하고 stop/초기화 시 지운다. `SessionManager`의 지역 태그 생성과 추천에서 모두 이 accessor를 쓴다. 만료 시 좌표 전송 없이 지역 태그를 빼면 wire shape는 유지된다.

GPS 상한은 10회 루프 polling보다 길게, **30초를 실측 전 후보값**으로 둔다. 폰의 전송 상한 5초와 목적이 다르다. SDK callback이 오래된 fix를 반복 전달한다면 callback 수신 시각만으로 실제 fix 나이를 알 수 없다. SDK 취득 시각 제공 여부를 A가 확인하고, 제공되면 그것으로 검증해야 한다. 이 제한이 남으면 기능 설명도 “차량 지역 태그의 관측 시간”으로 한정한다.

## 4. 회차 reset·중단·저장·과거 도감

### 새 알과 같은 알 재개를 분리

| 새 알 지급 시 초기화 | 보존 / 재주입 |
| --- | --- |
| 새로운 eggId, 세 지역 duration=0, unknown/active=0, 열린 관측, 알별 판정 태그, 최종 region 결과 | 모든 기존 도감 entries, 로드/마이그레이션 완료 상태, 그 도감에서 계산한 추천 요약 두 필드 |
| speciesId/attribute/tier=null, progress=0, care/lookOut/feed/play count, 동행 메시지, 새 알의 hatch 기준 | 현재 pairing/sessionId, 마지막 vehicle 정보와 연결 세대, 세션 거리·source cursor 중복 방지 이력. 새 알이라고 동일 세션 누적 distance/harsh 값을 0으로 간주하지 않음 |
| 이전 알의 지역 duration은 새 알에 복사하지 않음 | 품기/동행 시간 정책, 거리 평가 baseline은 T1·조정 담당 계약을 사용. 반복 알 지급을 기존 `startIncubating(tier)`의 “이어하기”와 혼용하지 않음 |

반복 예시: 90분에서 알1은 `[0,40분)`, 40~70분 동행은 제외, 알2는 `[70,80분)`, 나머지는 동행이다. 알1 지역과 알2 지역은 따로 판정한다. `GameState`의 stage에는 동행용 새 값을 임의로 추가하지 않는다.

중단 시 같은 알을 이어가는 방식을 채택한다면 `pause`가 열린 구간을 닫은 checkpoint를 로컬에 저장하고 누적 합+eggId를 복구한다. 재개는 열린 지역 없이 시작한다. 명시적인 중단 시간은 activeMs에서 제외하는 안을 권고하며, **네트워크 신호만 끊긴 활성 품기 시간은 unknown**으로 둔다. 앱 종료/프로세스 강제 종료의 누락 구간을 소급해서 채우지 않는다. 마지막 성공 checkpoint까지 복구하고 미저장 이후 관측은 잃을 수 있음을 명시한다. 전원 종료까지 보장하려면 저장 빈도·시간 엔진과 원자 저장 범위를 후속 결정한다.

#25의 `readLatestVehicle()` 종료 보완은 최신 값 한 개를 재소비하는 경로다. source cursor 검사와 TTL을 동일하게 적용해 다시 더하지 않는다. 종료 이벤트 ts를 지역 관측으로 쓰지 않는다. 종료/품기 checkpoint와 새 알 발급을 직렬화하고, 저장 실패 중 새 알을 시작하지 않는다. 단순 재연결은 알 회차를 reset하지 않는다.

### 도감 호환과 known 계산 — A 제안을 보완한 권고

- 기존 `regionTag`는 nullable string이므로 null·키 없음은 지역 미확정으로 읽고 기록을 지우지 않는다. 유효한 과거 coast/mountain/city는 **저장된 지역 수집 기록**으로 인정하는 안을 권고한다. 과거 첫 태그 방식의 기록을 시간 방식의 산출이라고 소급 설명하지 않는다. envTags로 과거 체류를 재계산하지 않는다.
- 과거 null/미확정 기록은 어느 지역에도 더하지 않는다. 알 수 없는 regionTag/손상 JSON은 임의로 버려 빈 도감으로 만들지 않고 요약을 unknown으로 둔다. 읽기·마이그레이션 성공 후에만 로컬 지원 버전 marker를 저장한다. 새 규칙의 출처를 구분해야 하면 이후 optional `regionRuleVersion`을 추가하되 이번 최소안에는 필수로 넣지 않는다.
- `known=true` 조건: 지원 버전 로컬 저장소가 초기화됐고, 현재 기기 도감 전체 읽기·형식 검증·호환 처리가 끝났으며, 관련 저장 작업이 완료되어 일관된 결과를 얻은 상태. 앱 버전만 최신이거나 entries가 비었다는 사실만으로 true로 바꾸지 않는다.
- 위 조건을 충족한 새 빈 도감은 true+세 유형 모두 미수집이다. null만 있는 정상 도감도 같은 결과다. 이것은 “수집 기록 없음”이지 “실제 미방문”이나 “지역 관측 완벽”이라는 뜻이 아니다. legacy/null 기록이 있어도 이 정의로 known=true를 허용할지는 C가 최종 결정한다.
- `collected = 정상 기록의 유효 regionTag 집합`, `uncollected = {coast,mountain,city} - collected`. 중복 획득은 set으로 처리한다. 도감 저장 성공 뒤 다시 계산한다. 저장 실패·로드 실패 시 false로 낮추고 기본 추천으로 돌아가는 안을 권고한다. 부화 결과의 저장 재시도에는 동일 DexEntry/eggId를 재사용한다.
- #22는 인코딩 문자열 중복 제거가 있지만 `dex.add`와 진행 checkpoint는 별도 쓰기다. 추천 요약을 미리 제거하지 말고, 도감 commit 완료 이후 publish한다. 지역 checkpoint만 추가해도 crash 원자성이 생기지는 않는다. checkpoint 내부 `version+eggId+지역 합+거리/시간 상태`를 하나의 로컬 값으로 묶는 후속 통합이 필요하다. 도감 내용·집계 checkpoint는 Firebase에 올리지 않는다.

## 5. `/game` 추천 요약과 Kotlin 호환 계약안

```json
{"regionCollectionKnown": true, "uncollectedRegions": ["coast", "mountain"]}
```

위는 전체 `/game`의 추가 필드 예시이며 단독 노드나 전체 game 대체 payload가 아니다.

| 수신 상태 | 해석 / 차량에 전달할 내부 목록 |
| --- | --- |
| known 키 없음 또는 false | 모름 → 기본 추천, 내부 null. 목록이 있어도 사용하지 않음 |
| true + 유효한 비어 있지 않은 목록 | 미수집 유형에서 추천, 중복 제거 |
| true + `[]` 또는 키 없음/null | 확인 결과 미수집 후보 없음 → 내부 empty. RTDB의 빈 배열 키 소멸을 포함. 세 유형의 수집 기록이 있다는 뜻 |
| 잘못된 known 타입, true + 잘못된 목록 타입/원소/알 수 없는 값 | 모름 → 내부 null. 손상 값을 일부 필터링해서 empty로 오인하지 않음 |

허용값은 coast/mountain/city뿐이다. `none`, `unknown`, `water` 같은 sentinel을 목록에 넣지 않는다. known=false인 동안 목록은 생략하는 편을 권고한다. JSON 순서는 결정적으로 coast→mountain→city를 쓰되 추천 우선순위를 뜻하지 않는다. 좌표·도감 entries·시간 합은 전송하지 않는다.

### B/C 모델·set 경로의 최소 패치 명세

`GameState`에 `bool regionCollectionKnown=false`, `List<String> uncollectedRegions=const []`를 추가한다. constructor·copyWith·toJson·새 상태 factory 모두 연결한다. copyWith는 생략 시 기존 필드를 유지하되 목록에 `[]`, known에 false를 명시할 수 있어야 한다. 리스트는 외부에서 변경되지 않게 보관한다.

`toJson`은 known boolean을 **모든 set에 항상 포함**한다. known=true이면 목록을 포함하고 빈 배열이 서버에서 사라져도 boolean으로 구분한다. 로드 중/실패에는 false를 보낸다. 새로운 GameState를 만드는 #22/#25의 `startIncubating`과 `_onVehicle`가 copyWith를 우회하므로 **copyWith만 수정하면 실패한다**. controller가 보관한 도감 요약을 모든 새 상태에 재주입하는 공통 함수/factory를 두거나 명시적으로 전달한다. care/lookOut·부화·idle·새 알·재시도 publish까지 확인한다. `/game.update`로 바꾸기만 하면 모델에서 잃은 값·오래된 값 문제를 숨길 수 있으므로 이 계약의 대안으로 삼지 않는다.

초기 pairing 직후 도감 로드가 끝나면 idle 상태에서도 요약을 publish한다. 새 알 전후에 true가 false로 초기화되거나 목록이 사라지지 않아야 한다. 부화 저장 뒤에는 새 요약을 다시 publish하고 비동기 publish 순서를 직렬화해 오래된 전체 set이 새 요약을 덮지 않게 한다. 다른 세션으로 재연결한 뒤 이전 세션의 완료 콜백을 새 세션으로 보내지 않도록 기존 연결 세대 guard도 유지한다.

### A의 Kotlin 파서와 추천 경로

기존 ignoreUnknownKeys 덕분에 새 폰→구버전 차는 기존 game 필드를 읽지만 지역 추천은 기본으로 남는다. 새 차→구버전 폰은 known 키 없음으로 기본 추천한다. `/game` 전체 삭제(root null) 시에도 이전 수집 요약을 지워 unknown으로 전환하도록 SSE 경로를 확인한다. 현재 baseline `SessionManager.kt:249–261,289–292`는 decode 실패·root null에 이전 상태가 남을 수 있다.

두 필드를 단순 `Boolean`/`List<String>` 필수 타입으로만 추가하면 손상 자료형 때문에 **전체 GameState decode가 실패하고 이전 후보가 남는다**. 권고: raw `JsonObject`에서 해당 두 필드를 따로 검사하는 `decodeRegionCollection(JsonObject): RegionCollection` 또는 custom serializer를 사용한다. 기존 game 필드는 기존 decoder로 읽되 추천 필드를 분리/제거하여 타입 오류가 진행도 decoding을 막지 않게 한다. 매 snapshot마다 위 표대로 Unknown 또는 Known(set)을 새로 계산한다. known=null은 없음과 같이 unknown, 목록=null은 true일 때 empty다. 숫자 문자열·object·배열의 구멍/null 원소를 강제 변환하지 않는다.

`SessionManager.suggestDestination()`의 하드코딩 null을 이 결과로 치환하고 변수/대사 키의 unvisited를 uncollected로 바꾼다. `DestinationFlow`의 2분 캐시는 도감 요약이나 세션 변경 시 reset하고, accept 직전에도 최신 known 후보에 여전히 속하는지 검증한다. 알 부화 사이에 오래된 목록의 목적지를 수락하는 일을 피한다.

현재 지역 제외 정책은 “그 유형의 수집 기록 없음”과 별개다. 미수집 후보가 현재 지역 한 개뿐인데 필터로 제외되면 `ALL_VISITED`라고 말하면 안 된다. `NONE_ELIGIBLE`/`NONE_NEARBY`/`ALL_COLLECTED`를 분리하거나 중립 문구를 쓴다. 세 유형 모두 수집한 empty 상태에서는 다른 지역 기본 추천으로 자동 폴백하지 않는다. 위치가 없으면 고정 순서, 있으면 근거리 정렬이라는 현재 동작을 유지하는 안이며 **거리순·현재 유형 제외는 사용자 확정이 아니다**.

Gleo 문구 예: “이 기기 도감에는 아직 바다 지역 수집 기록이 없어요. 바다 쪽을 추천할까요?” 실제 미방문·지역 한정 생물의 존재를 단정하지 않는다. 기본 추천은 수집 여부를 언급하지 않는다. `destinationSuggest`는 `region` + `status:offered|accepted`만 공유한다. #24의 accepted가 보장하는 SDK 요청 성공 범위와, #9가 요구한 실제 목적지 설정 완료 의미를 A가 맞춰야 한다.

## 6. Fixture와 검증 조건

`docs/work-results/fixtures/T3-region-cases.json`은 **제안 정책의 기대값**이다. 현재 제품 코드가 통과한다는 테스트 결과가 아니다. 시각은 ms이고 `atMs=0`은 가상 단조 시계 원점이다. fixture의 합성 관측은 trustedFresh=true가 기본이며 실제 feed 어댑터는 이를 생략해서 true로 취급하면 안 된다.

- `aggregationCases`: segments 또는 operations를 가진다. segment `[fromMs,toMs)`에서 stepMs마다 관측을 만들고 경계에는 다음 segment 태그를 적용한다. `sourceTsMs=sourceBaseMs+atMs`가 기본. 각 case는 begin→관측/경계 처리→finish. operations는 명시 순서이며 seed는 begin 이전 캐시, break는 feedEpoch 변경, pause/restore/resume은 위 API에 대응한다. afterFinish는 무시되어야 한다.
- `wireCases`: Kotlin 정규화 후 Unknown(null), Known(list) 기대값이다. 빈 배열이 사라진 실제 RTDB형 JSON도 포함한다.
- `dexCases`: 로드·검증·호환 완료 조건과 과거 기록의 요약 기대값이다. fixture의 unknown은 DB에 보내는 문자열이 아니다.

| 핵심 사례 | 기대값 |
| --- | --- |
| city25/mountain10/coast5분: 1초·4초·서로 다른 간격 | 모두 city=1500000, mountain=600000, coast=300000, unknown=0, 결과 city |
| 지역 없음 40분 | unknown=2400000, 결과 null |
| city10/mountain10분 동률 | null/tie |
| city10분+unknown30분 | null/insufficient |
| city25/mountain10/coast5분 후 동행에 mountain | 기존 결과 city 고정 |
| 90분 반복에서 새 알 | 알1 city 40분, 동행 coast 30분 제외, 알2 mountain 10분; 별도 집계 |
| 중복·역순 source ts, 큰 source 점프 | 중복·역순은 무시, 점프로 시간 증가하지 않음 |
| 10초 수신 공백 | 이전 지역은 최대 5초만, 나머지 unknown |
| checkpoint 후 같은 알 복구 | 합 유지, pause 시간 제외, 캐시 재수신은 합산하지 않음 |
| true + 목록 키 소멸 / 손상 값 | 각각 Known(empty) / Unknown으로 구분 |

구현 시 통과해야 할 추가 검사:

1. 순수 모듈: 합 보존, finish 멱등, 태그/순서 규칙, 최초 캐시·지연 콜백, 부화 경계 소급 금지, 같은 알 재개 vs 새 알 reset.
2. 폰 통합: #25의 마지막 snapshot 중복·종료 저장 재시도, 모든 GameState 생성 및 copyWith/set 경로, 도감 로드 실패·저장 실패·병행 저장/발행 순서, 새 알에 기존 요약 유지. 구버전 도감 읽기와 기존 거리 checkpoint를 보존.
3. Kotlin: wireCases를 실제 Json serializer/SSE 경로로 전달. 특히 손상 값 뒤 기존 known 후보가 남지 않음, root null 초기화, 구버전 game defaults, Known(empty) 비폴백, 현재 지역만 남았을 때 중립 응답.
4. A: freshPosition의 무값/TTL 경계/만료/동일 좌표 재관측/stop 재시작, 새 vehicle.ts라도 오래된 GPS는 지역 태그 생략. #24 accepted의 실제 의미 확인.
5. 로컬 모의 RTDB 또는 연결 가능한 테스트 환경: 빈 배열 저장→키 소멸→차 parser, 전체 set 반복, 정상/차단/재연결. 운영 DB 쓰기를 이 작업의 검증으로 사용하지 않는다.

### 이번 작업에서 직접 실행한 검증

- 원격 PR head/API와 `git ls-remote` 일치 확인; #22/#25 로컬 object의 controller·storage·feed·models, baseline 및 #24 차량 object 읽기 대조.
- `python3 -m json.tool docs/work-results/fixtures/T3-region-cases.json`: JSON 문법 확인.
- Python stdin 독립 계산: fixture segment를 실제 관측들로 펼쳐 시간 합/unknown/승자 판정, operations의 중복·역순·경계·복구, wire 정규화, dex 요약의 기대값을 검사했다. 집계 14건(합성 관측 6,397개)·wire 13건·dex 7건 모두 통과했다. 임시 검증기는 저장소·제품 모듈을 변경하지 않았다.
- `git diff --check`, 변경 경로 제한 검사. 코드 변경이 없으므로 Flutter/Gradle 빌드·실기/Firebase 검증은 실행하지 않았다.

## 7. 후속 수정 파일과 결정 질문

| 담당 | 수정 후보 / 구체적 연결 |
| --- | --- |
| 조정 C | `docs/schema.md`: 두 필드의 네 상태·자료형 오류 처리·좌표 미전송·event 성공 의미를 먼저 합의해 반영/공유. 선택한 집계 규칙·수신 시계·TTL·unknown 기준도 기록 |
| 조정 C | `phone/packages/allo_core/lib/src/region_accumulator.dart` + test: 위 순수 API, `models.dart`: GameState 필드와 직렬화/copyWith, 필요 시 optional 도감 출처 version. `allo_core.dart` export는 조정 담당 |
| 조정 B/C | `phone/lib/game/game_controller.dart`: 회차 id, clock adapter, 집계 경계·요약 재주입·publish 직렬화. `storage/dex_store.dart`: 전체 로드 검증, 마이그레이션 marker, 지역 checkpoint와 기존 진행 기록 호환. #22/#25 위에서 통합 |
| B | `phone/test/`: 새 알/복구/마지막 신호/저장 실패/set 유지 회귀. fake feed가 위 fixture를 주입하도록 필요 최소 확장 |
| A | `car/.../model/Models.kt`, `sync/SessionManager.kt`/관련 serializer: wire 파싱·Unknown 정규화·추천 연결·root null 처리. `gleo/DestinationSuggester.kt`: uncollected 명명/empty 이유/캐시 무효화와 accept 재검증. 기존 #24 성공 gating 유지 |
| A | `car/.../navi/NaviEtaReader.kt`: 위치+monotonic 시각과 freshPosition; 발행/추천 accessor 연결. 테스트 추가. 위치 좌표는 차량 메모리 안에서만 사용 |
| 조정 C/A | `data/dialogue.json` 및 소비 코드: 수집 기준 문구·키 변경. T5 검수와 겹치므로 통합 때 함께 조정 |

미결정 질문은 아래 순서로 정하면 구현할 수 있다.

1. 알 지급→부화의 최장 관측 지역을 채택할지, 단독 최대라도 unknown이 역전시킬 수 있으면 null로 남기는 보수안을 쓸지.
2. 폰 수신 단조 시계 근사를 받아들일지, 차량의 관측 시각/연속성·이력 계약을 확장해 소스 기반 체류를 요구할지. 전송 상한 5초·GPS 상한 30초와 최소 체류 기준은 얼마로 할지.
3. 앱 중단은 pause로 제외하고 통신 단절은 unknown으로 세는지, 같은 알을 새 차량 세션에서 이어갈지, crash 시 마지막 성공 checkpoint까지의 복구로 충분한지. 시간/거리 엔진의 중단 정책과 함께 결정.
4. 정상 호환 완료한 legacy/null 기록과 빈 도감에서도 known=true를 허용할지. 유효한 과거 지역 기록은 그대로 수집으로 인정할지. 이 문서는 허용/인정을 권고한다.
5. 미수집 후보가 현재 유형뿐일 때 추천할지, 현재 유형 제외를 유지할지. 모두 수집한 상태의 발화·근거리 후보 없음의 발화를 어떻게 나눌지.
6. #24의 SDK 요청 반환을 accepted 성공으로 정의할지, 비동기 목적지 설정 완료 신호까지 기다릴지. SDK가 실제 fix 시각/설정 완료를 제공하는지도 확인해야 한다.

미검증: 실제 위치 정확도·수신 간격/배터리·앱 suspend 시 clock 동작·SDK fix 신선도·실차/에뮬레이터·Firebase 직렬화 왕복·#22/#25 병합 후 통합 실행. 제안 채택과 구현/실기 검증은 조정 담당의 후속 작업이다.
