# 친구별 퀘스트와 방문 이력

2026-11-15. 사용자 새 기능 요청과 ‘친구마다 각각 이틀마다’ 답변을 정리한다. 저장 구조는 사용자가 추천안으로 진행하라고 승인했다. 아래 명세로 로컬 구현·검증하며, 실DB 배포와 APK 교체는 별도 작업이다.

## 사용자 확정 내용

- 시설/마을 캐릭터의 기존 상세 화면을 재사용한다.
- 캐릭터가 먼저 대화를 자동 재생하지 않는다. 옆에 `?` 표시로 할 이야기가 있음을 알리고 사용자가 눌렀을 때 내용을 연다.
- 각 소유 친구가 이틀마다 제안할 수 있다. 전체 중 한 마리만 제안하는 제한이 아니다.
- 먹이가 먹고 싶은 간단한 부탁, 자기 이야기와 연결되는 부탁, 오래 방문하지 않은 바다 등 여행 제안으로 확장한다.
- 과거 방문 장소와 다른 곳을 추천할 수 있도록 Pleos 여행 목적지 이력을 우리 DB에 저장한다.

## 제안하는 동작

친구별 안정적인 소유 개체 ID를 기준으로 48시간 주기를 저장한다. 종이 같은 두 친구도 별개다. 최초 제안 발급 시각부터 48시간으로 계산하며, 수락한 미완료 부탁은 하나만 유지하고, 미수락 부탁은 다음48시간 주기에 교체할 수 있다. 밀린 부탁을 여러 개 쌓지 않는다. 앱을 껐다 켜도 주기는 유지한다. 생성 시점 기준48시간과 최초 부탁 즉시 가능은 기존 요청을 구체화한 구현 판단이다.

### 마을과 상세

마을에 선택한 최대4마리 중 제안이 있는 친구 옆에 작은 `?` 배지를 표시한다. 다른 소유 친구의 부탁은 도감/상세에서도 확인할 수 있어 표시4마리에만 기회가 제한되지 않는다. 배지는 캐릭터 탭/드래그·산책·마을 표시 선택을 방해하지 않는다.

캐릭터를 누르면 기존 상세가 열린다. 상세에서도 `?`를 누르기 전까지 부탁 본문·TTS를 열지 않는다. `?`를 누르면 기존 상세 안의 작은 부탁 영역에 제목, 짧은 캐릭터 대사, 완료 조건과 `함께하기`/`나중에`를 표시한다. 읽기만 했다고 완료하지 않으며 원래 메뉴와 요리 주기를 그대로 사용할 수 있다.

수락 후에는 같은 상세에서 진행 조건을 보여준다. `나중에`를 누르면 현재 제안을 이번 주기 동안 유지하고 음성/푸시로 재촉하지 않는다. 완료 시 기존 감사 반응을 보여주며, 새로운 재화·별도 완료 보상은 이번 제안에 추가하지 않는다. 기존 음식 효과·훈련 효과는 유지한다.

### 부탁 종류와 검증 가능한 완료 조건

| 종류 | 예시(제안 문구) | 완료 근거 |
| --- | --- | --- |
| 먹이 | `오늘은 베리 간식이 먹고 싶어. 하나 나눠 줄래?` | 해당 소유 친구에게 기존 foodFeed가 성공하고 음식1개가 저장된 재고에서 차감됨 |
| 이야기·관찰 | 길싹이의 기존 작은 정원 이야기와 연결해 `내 작은 정원처럼, 주변의 초록빛을 같이 찾아볼까?` | 기존 창밖 보기/관찰 행동의 사용자 확인. 실제 풍경을 센서로 확인했다고 주장하지 않음 |
| 여행 | 실제 마지막 바다 방문이 충분히 오래전이면 `바다를 본 지 꽤 됐네. 이번엔 다른 바닷가에 가 볼까?` | 수락한 특정 목적지와 대응되는 실제 도착 이벤트. 내비 요청 성공·주차·여행 종료만으로는 완료하지 않음 |

먹이 재고가 없으면 기존 요리/가방으로 이어준다. 장소 방문 기록이 없으면 `바다를 함께 보러 갈까?`처럼 첫 제안 문구를 쓴다. `오랜만`, `전에 가봤던`은 확인된 이력이 있을 때만 쓴다. 바다 방문 간격의 초기 기준은14일로 정한다. 이는 구현 기본값이며 사용자 지정 숫자는 아니다.

## 이야기와 추천의 근거

기존 서버 `data/companion_learning/story.json`의 페르소나·고정 배경·장면을 읽는 퀘스트 템플릿을 서버에 둔다. 폰은 본문을 번들하지 않고 식별 정보와 받은 응답을 표시한다. 기존6개 legacy 대화 프로필에는 고유 이야기가 제공되지 않았으므로 그 과거를 새로 지어내지 않는다. 해당 친구는 먹이/확인된 여행 이력 기반 제안을 사용하고, 이야기 부탁은 자료가 있는 종부터 제공한다.

실제 장소 후보와 방문 여부는 코드/DB가 정하고, AI를 쓰더라도 캐릭터 말투를 다듬는 역할로 한정한다. AI가 방문 사실, 장소 이름/위치, 미확인 영업 여부, 보상이나 완료 판정을 만들지 않는다. 초기 후보는 기존 차량 추천의 검증 가능한 장소 목록을 재사용할 수 있다. 공개 POI 검색 API를 연결해 후보를 넓히는 것은 별도 확장이다.

부탁은 기본적으로 음식/스토리/여행 중 현재 가능한 종류에서 선택한다. 처음부터 오래 걸리는 여행 부탁만 강요하지 않는다. 여행 제안은 보호자에게 전달한 뒤 기존 운전자 확인 흐름으로 내비에 연결하며, 아이의 탭만으로 진행 중인 경로를 변경하지 않는다.

## Pleos에서 무엇을 얻는가

현재 `NaviEtaReader`는 `onDestinationInfo`에서 남은 시간만, `onDestinationArrived`에서 도착 시각만 사용한다. 설치된 NaviHelper3.0.5와 navi-data3.0.4를 읽어 다음을 확인했다.

- `DestinationInfo`: name, poiId, poiSubId, poiProvider와 남은 시간/거리 제공.
- `DestinationArrivedInfo`: name, address, duration, distance 제공. POI ID는 없음.
- `getRecentDestinationInfo`가 존재하지만 최근 목적지 목록을 실제 방문/도착 이력이나 완전한 과거 여행으로 간주하지 않는다.

따라서 목적지 설정/변경 때 차량 안에서 목적지 식별 정보를 보관하고, 대응되는 도착 콜백에서 방문을 확정해야 한다. 경로 취소, 목적지 변경, 경유지 도착, 앱 재시작으로 연결 정보가 없는 도착은 따로 구분한다. 현재 기어P3분/30분에 따른 세션 종료는 목적지 도착 증거가 아니다.

SDK 콜백의 실제 전달 여부는 에뮬레이터/차량 내비 상태에서 확인해야 한다. API에 필드가 존재한다는 것과 실차에서 이벤트를 관측했다는 것은 구분한다.

## 영속 방문 이력과 소유자 경계

기존 `/sessions/{sessionId}`는24시간 접근용이므로 이력을 여기에만 저장하지 않는다. 기존 Firebase 인증의 연결된 phoneUid를 서버가 확인한 뒤 별도 영속 영역에 저장하는 안을 권장한다.

```text
travelHistory/{phoneUid}/visits/{visitId}
  sessionId
  routeRevision
  placeId          # provider+poiId+subId 또는 우리 장소 카탈로그 ID
  placeName        # 확인된 목적지 이름
  regionTag        # coast/mountain/city/unknown
  arrivedAtMs      # 관측된 도착 시각
  receivedAtMs     # 서버 수신 시각
  companionIds    # 실제 동행하던 소유 친구 식별자
  evidence         # destination-arrived / unknown 등
```

`visitId`는 세션+경로/목적지의 결정적인 키를 사용해 재전송과 재접속에서 같은 방문을 두 번 기록하지 않는다. 서버는 요청 본문의 임의 phoneUid를 신뢰하지 않고 세션 ACL로 저장 소유자를 결정한다. 기록에는 `도착 관측`이라는 의미만 부여하며 물리적으로 증명된 차량/사람 신원이라고 부르지 않는다.

좌표와 이동 경로는 계속 차량 안에서만 사용한다. DB에는 방문 목적지의 ID·이름·지역·시각을 저장하고 주소·실시간GPS궤적은 보내지 않는다. 장소별 방문 횟수/마지막 날짜는 같은 owner transaction의 `travelHistory/{phoneUid}/places/{placeId}` 요약에도 함께 저장해 전체 이력 조회 없이 추천한다. 추천이 이미 방문한 장소를 제외할 때 provider까지 포함한 장소 키를 쓴다. 같은 이름의 다른 지점을 합치지 않는다. POI ID가 없으면 임의로 과거와 동일 장소라 단정하지 않는다.

현재 `docs/schema.md`는 추천 이벤트의 이름 저장도 허용하지 않으므로 이 사용자 요청에 맞춰 방문 데이터 계약을 명시 개정해야 한다. 현재 개인 AI API의 공유 데모 토큰을 방문 이력의 사용자 식별자로 쓰지 않는다. 기존 익명 인증 UID는 같은 앱 설치의 소유 경계이며 재설치/다른 폰까지 연결하는 가족 계정은 아직 없다.

## 퀘스트 상태의 저장

친구별 쿨다운·수락·완료는 기존 폰의 거점 저장 단위에 넣어 음식 차감과 같은 직렬 저장을 재사용하는 것이 가장 작다.

```text
creatureId -> questId, kind, templateId, templateVersion,
              issuedAtMs, nextEligibleAtMs, status,
              targetFoodId / targetPlaceId, acceptedAtMs, completedAtMs
```

친구 소유와 음식 판정은 기존처럼 폰이 소유한다. 서버의 영속 방문 이력은 인증된 폰이 읽고 로컬 추천 입력으로 사용한다. 퀘스트 본문 서버와 상태 저장·완료 판정을 구분한다. 앱 재설치/다른 폰에서도 퀘스트를 이어가려면 후속 소유 개체/거점 동기화가 필요하다.

## 접근법

1. 전부 폰 로컬: 가장 작지만 사용자가 요청한 DB 여행 이력과 장기 추천을 충족하지 못한다.
2. **방문 이력은 Firebase 영속화, 퀘스트 판정은 기존 폰 거점, 본문은 기존 스토리 서버:** 현재 역할과 보유 아이템을 유지하며 요구를 충족하는 권장안이다.
3. 계정·거점·음식·퀘스트까지 모두 서버 권위로 이전: 기기 간 동기화에는 유리하지만 기존 게임의 큰 이전이므로 이번 요청에 불필요하다.

## 구현 순서와 완료 기준

1. 방문 목적지/도착 구분과 Firebase 이력: 라우트 변경·경유지·취소·재전송·24시간 만료·다른 UID 접근을 검증한다.
2. 친구별48시간 상태와 먹이 부탁: 개체별 독립 주기, 앱 재시작, 시간 역행, 미완료1개, 실제 음식 차감 성공 후1회 완료, 저장 실패를 검증한다.
3. 마을/도감/상세의?배지와 제안 UI: 자동 대사 없음, 기존 탭/드래그/산책/4마리 선택/뒤로 가기를 유지한다.
4. 기존 스토리 기반 부탁과 실제 이력 기반 여행 추천: 근거 없는 과거 발화 없음, 같은 장소 반복 제외, 현재 경로 보호와 보호자 확인을 검증한다.

이전 요청에서 후순위로 둔 짧은 여행 부화·사진 시간 유예, 보류한 작업 시간/효과 안내는 변경하지 않는다. 이 설계 작성만으로 실DB에 방문 데이터가 저장되거나 기능이 배포됐다고 말하지 않는다.

## 구현 인터페이스 확정

- 장소 원본 `data/travel_places.json`은 기존18개 목적지의 이름/지역/고정 ID만 담는다. ID는 `place_`+SHA256(region+newline+name)의 앞16hex. 좌표는 포함하지 않는다.
- Firebase callable `recordDestinationVisit` 입력: `sessionId, visitId, routeRevision, placeId, placeName, regionTag, arrivedAtMs, companionIds` (추가 좌표/주소 금지). 결과 `visitId, recorded:true`. phoneUid는 서버가 session ACL에서 결정한다. 저장은 `travelHistory/{phoneUid}`의 visits+places 한 transaction이다. 소유 폰만 해당 경로를 읽는다.
- 차량 TravelRequest에 선택적 `targetPlaceId` 추가. 기존 `wishId,targetRegion`은 유지한다. 정확한 장소를 요청한 경우 그 장소만 운전자 후보에 올리고 다른 목적지로 바꾸지 않는다.
- 서버 `POST /v1/companion/quest-template`: `{speciesId,kind,variant}` → `{schemaVersion:1,templateId,templateVersion:1,speciesId,kind,title,text,storyId,targetFoodId,targetRegion}`. kind는food/story/travel이며 unsupported legacy story는food로 반환한다. 새 권위/보상/사용자 이력 저장 없이 고정 자료를 사용한다.
- Dart `CompanionQuestKind {food,story,travel}`, `CompanionQuestStatus {offered,accepted,completed}`. BaseCamp에서 `quests`, `questDue`, `offerQuest`, `acceptQuest`, `completeStoryQuest`, `completeTravelQuest`를 제공하며 feedFood 성공에 같은 snapshot 안에서 food quest 완료를 연결한다. 완료 보상 재화를 추가하지 않는다.
- UI snapshot root `quests`는 `creatureId,questId,available,opened,busy,status,kind,title,text,error,requirement,candidates`를 갖는다. candidates는`placeId,name,region`뿐이다. intents는`openQuest,laterQuest,acceptQuest,observeQuest,requestQuestTravel`; body는`creatureId,questId,placeId`다. Unity는 대사/쿨다운/완료를 판정하지 않는다.
