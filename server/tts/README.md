# 캐릭터 음성 중계 서버

모바일 여행 이야기는 DashScope WebSocket PCM을 받아 즉시 재생하며, Pleos 광장의 고정24문장은 완성된 WAV를 캐시해서 재생한다. 동일 캐릭터는 두 앱에서 같은 목소리 설정을 쓴다. 앱에는 DashScope API 키가 들어가지 않는다.

## 캐릭터 목소리 (2026-11-14)

- **지금: 기본 목소리 + 페르소나 말투.** `voice_profiles.json`이 대사가 있는 17종(게임 판정 12종 ∪ 원본 아트 12종 중 대사가 있는 캐릭터)마다 목소리·음높이(`pitch`)·속도(`rate`)·말투 지시(`instruction`)를 정한다. 근거는 `docs/character-personas.md`, `docs/dialogue-style.md` 2절·신규 6종 표.
- 이 계정(싱가포르)에서 한국어로 합성되는 기본 목소리는 `tts-plus`의 4개뿐이다(`longanlingxin`·`longanhuan`·`longanfengyue` 여성, `xunanchuan` 남성). `tts-flash` 아이·캐릭터 목소리 29개는 모두 `Engine error 411`로 실패했다. 그래서 목소리를 나눠 쓰고 음높이·속도·말투로 구분한다.
- **말투 지시는 한국어 40자 이하 한 문장.** 두 문장 이상이거나 길면 모델이 지시문을 소리 내어 읽는다(3초 대사가 12–14초로 늘어남, 2026-11-14 확인). `load_profiles()`가 이를 거부한다.
- **나중: 복제 목소리.** `voices.local.json`에 복제 voice ID가 등록된 캐릭터는 그 목소리에 말투 지시만 적용한다(음높이·속도는 기본 목소리 전용). 2026-11-14 현재 음성 복제(`voice-enrollment`)는 `AccessDenied.Unpurchased`로 막혀 있어 알리바바 문의가 필요하다.
- 설정을 바꾸면 서버 캐시는 자동으로 새로 만들고, 차량 앱은 `ALLO_TTS_VOICE_REVISION`을 올려야 로컬 캐시가 바뀐다.
- `tts-plus` 무료 사용량은 1만 자다. 넘으면 종량 과금된다.

## 에뮬레이터 로컬 테스트 (Firebase 로그인 없이)

체험(fake) 모드 폰 앱과 Pleos 미리보기 앱에는 Firebase 로그인이 없다. 로컬에서만 쓰는 개발 토큰으로 대신한다. **배포 서버·release 빌드에는 절대 넣지 않는다.**

1. `server/tts/.env.local`에 `TTS_DEV_TOKEN=<24자 이상 임의값>`. 서버는 이 토큰을 **같은 컴퓨터(127.0.0.1)에서 온 요청만** 받는다.
2. 서버: `uvicorn server.tts.app:create_app --factory --env-file server/tts/.env.local --host 127.0.0.1 --port 8787 --workers 1`
3. 폰: `ALLO_UNITY_LOCAL_HTTP=1 scripts/export_unity.sh` (테스트 전용 export, http 허용). 끝나면 `ProjectSettings.asset`의 `insecureHttpOption` 변경을 되돌리고, 실제 배포용은 환경변수 없이 다시 export한다. 빌드: `flutter build apk --debug --dart-define=FEED=fake --dart-define=UNITY_APP=true --dart-define=ALLO_TTS_BASE_URL=http://10.0.2.2:8787 --dart-define=ALLO_TTS_DEV_TOKEN=<같은 값>`
4. Pleos: `car/local.properties`에 `ALLO_TTS_BASE_URL=http://10.0.2.2:8787`, `ALLO_TTS_DEV_TOKEN=<같은 값>`. 실차 앱은 폰 연결 후에만 광장이 열리므로 미리보기 앱으로 확인한다: `./gradlew -PincludePreview=true :preview:installDebug` 후 `am start -n ai.allo.preview/.PreviewActivity --es screen Home --ez plazaAllFriends true`.
5. 개발 토큰은 debug 빌드 + loopback http 주소일 때만 쓰인다(폰 `StoryVoiceConfig`, 차량 `PlazaCloudVoice.tokenSupplier`). 두 앱이 같은 토큰을 쓰면 서버에서는 한 사용자로 보여, 동시에 말하면 한쪽이 429(동시 1건 제한)로 기존 WAV에 폴백할 수 있다.

현재 구현 모델: `qwen-audio-3.1-tts-plus`. 사용자가 처음 요청한 `qwen3-tts-vc-2026-01-22`는 [공식 종료 공지](https://www.alibabacloud.com/en/notice/model_studio_notice_of_retirement_for_selected_legacy_models_7d9?_p_lc=1)의 2026-10-10 종료 대상이다. `Realtime`이라는 모델명 대신, 복제 음성을 지원하는 TTS의 WebSocket 스트리밍을 사용한다. 음성 대화/마이크 수집 기능은 필요하지 않다.

## 사용자가 준비할 것

1. [Model Studio 콘솔](https://modelstudio.console.alibabacloud.com/)의 API Key 화면에서 일반 종량제 API 키를 생성한다. Coding/Token Plan 전용 키가 아니다. 선택한 리전에서 `qwen-audio-3.1-tts-plus`와 음성 복제 호출 권한/서비스 활성화를 확인한다.
2. **API 키, 리전, Workspace ID, API Host**를 저장한다. 키는 리전 간 공유되지 않는다. 지원 설정은 싱가포르 `ap-southeast-1` 또는 베이징 `cn-beijing`이다.
3. `server/tts/.env.example`을 `.env.local`로 복사해 값을 채운다. `.env.local`은 Git 제외다. 키를 채팅·앱 코드·PR에 붙이지 않는다. API Host는 Workspace/리전과 일치하는지 확인용이며 코드가 공식 workspace 도메인을 구성한다.
4. 기존 Firebase 프로젝트 ID와 서버용 Google Application Default Credentials가 필요하다. 개발 시 서비스 계정 파일은 저장소 밖에 둔다. 배포 환경에서는 서비스 계정/워크로드 ID를 사용한다. 이 인증은 앱의 Firebase ID 토큰 검증용으로, DashScope 키와 별개다.
5. 캐릭터별 깨끗한 동일 목소리 샘플을 준비한다. 10–20초 권장, 연속5초 이상 발화가 필요하다. 현행 광장 전용9종은 파일이5초미만이라 새 참조가 필요하다. 임의 반복/다른 종 대체를 하지 않는다. voice ID는 아래 등록 도구가 받아 저장한다.

공식 안내: [키 발급](https://www.alibabacloud.com/help/en/model-studio/get-api-key), [음성 복제](https://www.alibabacloud.com/help/en/model-studio/voice-cloning-user-guide), [WebSocket API](https://www.alibabacloud.com/help/en/model-studio/qwen-audio-tts-websocket-api), [클라이언트 이벤트](https://www.alibabacloud.com/help/en/model-studio/qwen-audio-tts-client-events), [서버 이벤트](https://www.alibabacloud.com/help/en/model-studio/qwen-audio-tts-server-events).

## 설치·등록·실행

저장소 루트에서 실행한다. 전체 저장소의 대사 파일을 읽어 광장 허용목록을 만들므로 이 서버 폴더만 따로 배포하지 않는다.

```sh
python3 -m venv /tmp/allo-cloud-tts
/tmp/allo-cloud-tts/bin/pip install -r server/tts/requirements.txt
# .env.local 작성 후, 검수한 캐릭터 참조를 한 종씩 순차 등록한다.
/tmp/allo-cloud-tts/bin/python -m server.tts.enroll \
  --env-file server/tts/.env.local \
  --species road_sprout --sample /absolute/path/to/reviewed-road-sprout.wav
# 같은 방식으로17종 등록. 같은 캐릭터는 두 앱에서 등록을 공유한다.
/tmp/allo-cloud-tts/bin/uvicorn server.tts.app:create_app --factory \
  --env-file server/tts/.env.local --host 127.0.0.1 --port 8787 --workers 1
```

등록 도구는 대상 종/PCM16/mono/16kHz이상/5–60초/10MB이하를 검사한다. **총 파일 길이 검사는 연속발화나 음색·품질 검수를 대신하지 않는다.** 공급자 심사 `OK`이며 모델 일치 시에만 `voices.local.json`의 활성 `voice_id`에 저장한다. 심사 대기는 `pending_voice_id`로 남겨 재실행 시 중복 생성하지 않는다. 등록 명령은 동시에 실행하지 않는다. 레지스트리 변경 후 서버를 재시작한다. 참조 교체 시 별도 레지스트리를 만들고 전체 검수 후 교체한다.

서버 외부 공개에는 HTTPS 주소가 필요하다. 리버스 프록시의 응답 버퍼링을 끄고 스트리밍/65초 타임아웃을 허용한다. 현재 사용량 제한은 단일 프로세스 메모리 기반이므로 **1worker/1instance**로 운용하며, 수평 확장 전 공유 제한 저장소를 도입한다. 사용자당30요청/분·1만자/시간, 사용자당1동시요청, 전체4동시요청, 요청600자/8KB·출력60초로 제한한다. 이것은 과금 상한 보장이 아니므로 클라우드 예산도 별도로 설정한다.

## 앱 연결

모바일 Flutter 빌드에 `--dart-define=ALLO_TTS_BASE_URL=https://<gateway-host>`를 추가한다. 매 발화 시 Firebase의 현재 사용자 ID 토큰을 가져와 Unity에 일회 전달한다. Firebase 로그인이 없는 fake/demo 모드나 미설정 URL은 기존 음성으로 돌아간다. 디버그에서만 `http://10.0.2.2:8787` 등 루프백 개발 주소를 허용한다.

`car/local.properties`:

```properties
ALLO_TTS_BASE_URL=https://<gateway-host>
ALLO_TTS_VOICE_REVISION=1
```

Pleos는 기존 FirebaseIdentity 토큰을 사용한다. 모델/복제 voice ID 변경 시 **ALLO_TTS_VOICE_REVISION을 올려 재빌드**해야 로컬 광장 캐시도 교체된다. Preview에는 Firebase 인증 주입 경로가 없어 기본 오프라인 재생을 유지한다. 실제 app 경로로 클라우드 재생을 검증한다.

서버/등록이 아직 준비되지 않았으면 앱의 기본 기존 WAV 재생을 유지한다. 서버가 미등록 종에 다른 캐릭터의 목소리를 대신 반환하지 않는다.

## API와 동작

두 API 모두 `Authorization: Bearer <Firebase ID token>`과 JSON `{ "species": "road_sprout", "text": "대사" }`를 받는다. API 키나 voice ID를 클라이언트에서 받지 않는다.

- `POST /v1/story/stream`: `application/octet-stream`, PCM16 **little endian**, mono24kHz. `X-Audio-Format:s16le`, `X-Audio-Sample-Rate:24000`, `X-Audio-Channels:1`. 첫 데이터부터 재생. 현재8화자·600자 이하 텍스트를 허용하며, 새 이야기를 생성하는 LLM 자체는 이번 변경에 포함하지 않는다.
- `POST /v1/plaza/clip`: 고정24문장과 정확히 일치할 때만 완성 WAV 반환. 서버/클라이언트 양쪽에서 캐시한다. 장면/캐릭터 전환은 이전 요청·재생을 취소한다.
- 부분/실패 출력은 캐시하지 않는다. 서버 캐시 키는 리전/Workspace/모델/voice ID/화자/원문/언어/오디오 형식을 포함한다. 캐시는64MB로 제한한다.
- 모바일은 첫 음성 전 실패 시 정확히 일치하는 번들 WAV로 복귀한다. 일부 음성을 이미 들었다면 처음부터 다시 읽지 않는다. 현재 미연결 결말2개는 클라우드 성공 시 현행 문구로 읽고, 오프라인에서는 계속 무음이다.
- 클라우드 캐릭터 목소리 일치와 별개로 초상이 없는5종은 기존대로 이름만 표시한다.

## 검증과 남은 작업

```sh
/tmp/allo-cloud-tts/bin/python -m unittest discover -s server/tts/tests -v
python3 -m unittest discover -s scripts/tests -p test_prepare_tts_manifest.py -v
```

모의 WebSocket으로 task-started 전 텍스트 전송 방지, task ID 일치, 부분 PCM 도착, 취소 시 upstream cancel/close, 오류 정리와 캐시 재사용/격리를 검사한다. 실제 공급자 인증, 샘플 심사, 음색·한국어 발음, 실제 APK 스트리밍 및 청취는 **키·참조 등록·배포 전에는 완료되지 않은 상태**다. 서버 배포나 클라우드 과금 호출은 아직 하지 않았다.
