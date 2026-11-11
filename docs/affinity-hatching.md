# 호감도 부화 구현 기준

2026-11-11 사용자 대화에서 선택한 첫 기능. 기존 전체 개편 초안의 3주제/3점·마감 부화·사진 선택·온디바이스 판정 기본안보다 이 문서가 우선한다. C는 이 기준으로 먼저 구현하고 팀원에게 PR 리뷰를 받는다.

## 확정 동작

- 호감도 0~100. 사진 퀘스트 완료 상태에서 100이면 즉시 부화한다.
- 알은 말로 답하지 않는다. 말 걸기 버튼의 발화 결과가 positive이면 +12를 60초에 걸쳐 선형 누적, negative이면 -12(즉시 적용 기본값), neutral이면 0과 `...`만 표시한다. 무음/인식·API 실패는 감점하지 않는다.
- 정상 판정된 발화는 180초 간격. 평가 중 중복 요청은 보내지 않는다. 재입력은 쿨다운을 연장하지 않는다.
- 쓰다듬기 +3, 10초 간격. 쿨다운 중 입력은 점수 없이 진동만.
- 차 안 네 구역을 UI가 정한 0~3 ID로 전달한다. 다른 구역에 알을 놓을 때마다 15초 쿨다운. 임의 선호 구역에 놓으면 +7 후 현재 구역을 제외한 나머지3개 중 다음 선호 구역을 랜덤 선택. 틀리면 점수 없이 진동, 선호 구역 유지. 같은 구역 재놓기는 이동으로 세지 않는다.
- 최초 50 도달 시 정확히50에서 잠그고 사진 퀘스트를 연다. 남은 발화 적립과 그 행동의 50 초과분은 종료하는 기본값이다. 퀘스트 중 일반 호감도 입력은 막는다.
- 실제 카메라의 차 밖 풍경과 알을 합성한 사진을 서버에 제출한다. 서버가 확인한 현재 알의 업로드 receipt로 한 번만 +15, 65에서 다시 진행한다. 사진내용 AI판독은 추가하지 않는다. 기기 여러 대가 같은 데모방 토큰으로 접속해 사진을 조회한다.
- 퀘스트 중 버리기로 현재 알을 종료할 수 있다. 시간/거리 마감까지 성공하지 못하면 실패(흔들리다 떠나는 표현). 종료된 알에 늦은 API/업로드 결과를 적용하지 않는다.
- 기존 ETA 품기 마감 계산과 ETA 없을 때 거리 대체를 유지한다. 퀘스트 중에도 활성 제한시간은 흐른다. 앱 중단 시간은 기존 방식대로 제외한다.
- 성공한 실제 부화 시점부터 활성시간30분 뒤, 최신 ETA가 새 알을 허용하면 다음 알을 한 개 지급한다. 원래 70분 시점까지 기다리지 않는다. 실패/버리기에서는 자동 반복하지 않고 새 알 시작 입력을 기다린다.

## 데모 API와 저장

사용자 최신 선택으로 데모의 내용 판정은 API다. 최종 전사 텍스트만 서버로 보내고 서버가 OpenAI Responses API의 positive/negative/neutral을 받아 반환한다. API 키는 서버 환경에만 둔다. 앱과 서버는 전사 원문·음성을 저장/로그하지 않는다. `store:false`는 제공자의 모든 보관을 없앤다는 뜻은 아니므로 배포 환경의 제공자 데이터 정책을 별도로 확인한다.

서버는 명시적으로 설정한 32자 이상 데모방 Bearer 토큰으로 평가·업로드·사진 조회를 보호한다. 같은 토큰을 설정한 데모 기기가 같은 사진을 조회한다. 이는 제품용 가족 계정 인증을 구현했다는 뜻이 아니다. 서버는 기본 localhost에 바인딩하고 실제 폰 연결은 HTTPS 프록시/호스트 설정을 사용한다. 사진은 EXIF 없이 재인코딩한 JPEG와 최소 metadata만 서버 디스크/SQLite에 보관한다. RTDB의 game에는 사진 원문·토큰·음성·텍스트를 넣지 않는다.

- `POST /v1/egg/evaluate`: `{eggId,requestId,text}` → `{eggId,requestId,sentiment}`. 최대500자, 실패는 오류 응답이고 점수 없음.
- `POST /v1/egg/photo`: `{eggId,requestId,imageBase64,mimeType}` → `{eggId,requestId,photoId,uploadedAtMs}`. 입력 JPEG/PNG 최대5MiB, 파싱/디코딩 검증 후 metadata 제거. 같은 requestId의 다른 입력은409.
- `GET /v1/egg/photos`: 방의 사진 metadata 목록(최근100개).
- `GET /v1/egg/photos/by-egg/{eggId}`: 현재 알의 원래 업로드 receipt 조회. 최근 목록 범위와 무관하며, 응답 유실·재촬영·재시작 때 다른 요청 ID로 완료된 같은 알의 사진도 복구한다.
- `GET /v1/egg/photos/{photoId}`: 인증 후 JPEG. 임의 경로/외부 URL 금지.

C의 연결 API는 `GameController.startIncubating(tier, useAffinity: true)`로 명시적으로 켠다. 기존 화면/테스트의 기본 흐름은 계속 기존 시간 기반 모드다. 새 UI가 C API를 연결하기 전 자동으로 현재 앱을 사진 단계에 가두지 않는다. 실제 카메라 합성·3D 뷰·녹음 UI는 B가 이 API에 연결할 입력 계층이며, 이번 C 완료와 실제 기기 전체 기능 완료를 구분한다.

## C 인터페이스

`AffinityRound`는 Flutter/IO/시계에 의존하지 않는 회차 규칙이다. 앱 활성 경과 밀리초를 전달하며, score는 정수 milli-points(1000=1점)로 누적해 재시작·프레임 간 차이를 막는다. 현재 점수/사진 상태/쿨다운/랜덤 선호 구역/처리한 발화 ID를 checkpoint로 보존한다. 시간 경계와 100 도달이 같으면 마감이 우선한다. 늦은 tick에서도 마감 전 목표 도달이 계산되면 그 시점에 부화한 것으로 처리한다.

컨트롤러는 API 입력의 알·연결·lifecycle 세대를 검사하고, 유효한 결과만 코어에 전달한다. 저장된 판정 결과를 재시도하며 같은 알을 다시 추첨하거나 중복 획득하지 않는다. 기존 알 checkpoint는 기존 규칙으로 마무리하고 이후 새 알부터 요청한 모드를 사용한다.

일반 입력·주기 저장은 지역 관측을 끊지 않는 snapshot을 사용한다. 실제 앱 중단 때만 관측 연속성을 끊는다. 늦게 전달된 tick에서 부화 시점이 과거로 계산되면 그 시점까지의 관측만 사용하고, 이후 차량 태그·급격 조작을 해당 알의 판정에 더하지 않는다. 다음 알은 부화+30분 이후 새로 수신한 차량 신호의 ETA로 판단하며, 오래된 캐시만으로 지급하지 않는다.

성공한 쓰다듬기는 기존 돌봄 횟수도 1회 늘려 기존 희귀도 보정을 유지한다. 말·이동·사진 보상은 돌봄 횟수를 임의로 추가하지 않는다. 쿨다운·사진 잠금 중 입력도 횟수를 올리지 않는다.

## 폰 입력 연결 예시

```dart
final api = HttpEggDemoApi.fromEnvironment();
final controller = GameController(feed: feed, dex: DexStore(), eggApi: api);
await controller.startIncubating(EggTier.mid, useAffinity: true);

await controller.petEgg();
await controller.placeEgg(2); // UI의 네 구역 ID 중 실제로 놓은 구역
await controller.submitEggSpeech(finalTranscript); // 전사 원문은 호출 후 보관하지 않음
await controller.uploadEggPhoto(compositedCameraJpeg);
await controller.recoverEggPhoto(); // 서버 저장 후 응답을 잃은 경우
await controller.discardEgg();

// 입력 화면을 닫을 때 caller가 소유한 자원을 해제한다.
controller.dispose();
api.close();
```

UI는 `affinityRound`, `eggFeedback`, `speechBusy`, `photoBusy`로 표시·버튼 상태를 연결한다. neutral의 표시는 `...`이며 vibration은 진동 입력이다. 실제 카메라 합성·음성 인식·3D 구역 선택 화면을 구현했다는 예시는 아니고, 해당 화면이 사용할 C 호출 계약이다. 기존 기본 화면은 명시적으로 이 경로를 선택하기 전까지 원래 부화 방식을 사용한다.

서버의 OpenAI 처리 제한은 20초, 폰 HTTP 클라이언트 기본 제한은 25초다. API 실패에는 점수나 성공 판정을 만들어내지 않는다. 실제 키와 HTTPS 호스트를 설정한 뒤 모델 분류 품질·기기 왕복을 별도 확인한다. [서버 실행과 환경 설정](../server/affinity/README.md)을 참고한다.

## 로컬 교차 연동 확인

`flutter pub get`을 `phone/`에서 실행하고 서버의 Python 의존성을 설치한 뒤 다음 명령으로 실제 Dart 클라이언트와 Python HTTP/SQLite 서버를 함께 확인한다.

```sh
server/affinity/.venv/bin/python scripts/verify_affinity_api.py
```

`dart`가 PATH에 없으면 `DART_BIN`으로 Flutter SDK 안의 Dart 실행 파일을 지정한다. 시험은 임시 서버·임시 사진·임시 방 토큰을 사용하고 종료 후 정리한다. 다른 클라이언트의 사진 조회, 50점 잠금 → 업로드 → 65점 → 발화 선형 적립 → 100점 부화를 검증한다. 외부 모델 대신 합성 판정 함수를 주입하므로 API 키·과금·실제 발화 없이 실행되며, 실제 AI 분류 품질이나 카메라/기기 동작의 검증은 아니다.

## 구현 검증 기록 2026-11-11

- 기존 `dev` `82e77bd`를 기준으로 새 모드와 저장·클라이언트·서버를 연결했다.
- 코어 `dart test`: 70개 통과. 폰 `flutter test --no-pub`: 242개 통과. 서버 `unittest`: 24개 통과.
- 실제 Dart 클라이언트와 Python HTTP/SQLite 서버의 합성 입력 교차 시험 통과. 판정은 시험 함수를 주입했고 실제 모델 호출은 하지 않았다.
- `dart analyze`: 오류·경고 없음. 기존 library 선언 관련 info 2건은 유지한다. `flutter analyze`는 도구의 analysis-server JSON FormatException으로 종료되어 대체 분석 결과와 구분한다.
- 독립 검토에서 발견한 업로드 응답 유실/늦은 완료 복구, 저장이 지역 관측을 끊는 문제, 늦은 차량 신호가 과거 부화 결과에 섞이는 문제를 회귀 테스트로 수정했다. HTTP POST의 Content-Length도 실제 서버와 교차 검증했다.
- 사용자 확인대로 API 키는 아직 준비되지 않았다. 실제 모델의 한국어 분류 품질, HTTPS 배포·실기기 카메라/STT/차량 왕복, 최종 입력 화면 연결은 이 결과에 포함하지 않는다. 기존 UI는 자동으로 새 모드로 바뀌지 않는다.
