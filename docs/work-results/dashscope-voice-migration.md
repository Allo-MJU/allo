# DashScope 캐릭터 음성 전환

2026-11-14 기준. **서버 중계와 두 앱 클라이언트는 구현했다. 실제 키 연결·캐릭터 음성 등록·클라우드 음성 청취는 아직 하지 않았다.** 키가 없거나 서버가 설정되지 않으면 두 앱 모두 기존 WAV로 재생한다.

## 구조 (2026-11-14 결정)

- **모바일 여행 이야기 → 스트리밍.** Unity `StoryStreamVoice`가 서버 `POST /v1/story/stream`의 PCM(s16le·24kHz·mono)을 받는 대로 150ms 버퍼 후 재생. 첫 음성 전 실패 시 정확히 일치하는 번들 WAV로 복귀하고, 이미 들린 대사를 처음부터 다시 읽지 않는다. Flutter가 매 대사마다 Firebase ID 토큰을 Unity에 일회 전달한다(`storyVoiceConfigRequest`/`storyVoiceConfig`, 게임 상태에 저장 안 함).
- **Pleos 광장 고정 24문장 → 캐시 재생.** `PlazaCloudCache`가 `POST /v1/plaza/clip`의 완성 WAV를 종·문구·서버·`ALLO_TTS_VOICE_REVISION`별로 저장. 실패 시 `PlazaRecordedEngine`이 기존 WAV로 폴백.
- **서버 `server/tts/`.** DashScope 키는 서버에만 둔다. Firebase ID 토큰 검증, 허용 화자/문구 목록, 사용자·전체 동시 요청 제한, 부분 출력 미캐시, 클라이언트 연결 끊김 시 상위 합성 취소. 모델은 `qwen-audio-3.1-tts-plus`의 WebSocket 스트리밍. 상세 사용법은 `server/tts/README.md`.
- 다음 버튼·화면 전환·백그라운드에서는 요청과 재생을 모두 취소하고, 늦게 도착한 음성은 무시한다.

## 검증 (2026-11-14)

- 서버 단위 테스트 15개 통과(응답 헤더 전 연결 끊김 시 슬롯 해제, 광장 합성 중 연결 끊김 시 취소 포함). 대사 매니페스트 테스트 3개 통과.
- 차량 단위 테스트 335개 통과, preview debug·app release Kotlin 컴파일 성공.
- Flutter 전체 439개 통과, 변경 파일 정적 분석 이상 없음. Unity EditMode 163개 통과(PCM 버퍼·스트리밍 취소 포함).
- 모의 WebSocket·모의 서버로만 검증했다. 실제 DashScope 인증, 음성 복제 심사, 한국어 발음·음색, APK에서의 스트리밍 청취는 미검증이다.

## 실제 계정 연결 (2026-11-14 오후)

- 싱가포르 종량제 키(`allo-tts-server`)·Workspace 연결(값은 `server/tts/.env.local`에만 둔다). WebSocket 인증·모델 목록 조회 성공.
- 음성 복제(`voice-enrollment`)는 결제 수단 등록 후에도 `403 AccessDenied.Unpurchased`. 문서상 원인(서비스 미활성화)은 해당 없음 — Model Studio는 활성화·무료 사용량 표시됨. 알리바바 문의 필요.
- 대신 **기본 목소리 4개 + 캐릭터별 페르소나 말투**로 전환(`server/tts/voice_profiles.json`, 상세는 `server/tts/README.md` "캐릭터 목소리").
- 17종 실제 대사 각 1줄을 실제 API로 생성해 확인. 처음 쓴 긴 말투 지시는 모델이 소리 내어 읽어(4종, 3초 대사가 11–14초) 한 문장 40자 이하로 줄였고, 이후 17종 모두 지시 없는 합성과 길이가 같았다(±0.7초). 서버 테스트 20개 통과.
- 실제 청취 평가(캐릭터 구분, 아이 대상 적합성)와 앱에서의 재생은 아직 하지 않았다.

## 범위

모바일 이야기 8종104단계와 Pleos 광장12종24문장. 공통3종(길싹이, 웅덩이삐약, 고속혜성)을 합친17종이며 중복 대사를 합치면104개 음성 파일이다. 동일 캐릭터의 voice ID를 두 앱이 공유한다. 앱에 키를 넣거나 Firebase 게임 데이터 계약을 변경하지 않는다.

## 모델을 바꾼 이유

사용자가 요청한 `qwen3-tts-vc-2026-01-22`는 Alibaba Cloud의 [공식 종료 공지](https://www.alibabacloud.com/en/notice/model_studio_notice_of_retirement_for_selected_legacy_models_7d9?_p_lc=1)에 2026-10-10 종료 대상으로 올라 있다. 별도 계정 권한/실제 API 가용성은 확인하지 않았다.

현재 [음성 복제 문서](https://www.alibabacloud.com/help/en/model-studio/voice-cloning-user-guide)는 Qwen-Audio-3.1-TTS-Plus 등의 복제를 안내하며 한국어를 지원 언어로 명시한다. 사용자와 협의해 이 모델의 WebSocket 스트리밍으로 구현했다. 유료 호출은 아직 하지 않았다.

실제 생성에는 로컬 `DASHSCOPE_API_KEY`와 리전이 필요하다. 현재 환경에는 키가 설정되지 않았다. 키는 소스/문서/앱에 저장하지 않는다.

## 참조 음성 감사

- 저장소 이야기78 WAV와 Desktop/out_story 원본 바이트 일치.
- 저장소 광장24 WAV와 Downloads/allo_tts_plaza 원본 바이트 일치.
- 전부24kHz mono PCM16. 합계17종의 동일 species 파일만 참조 후보로 선택한다.
- 공통3종은 이야기 음성을 양쪽 화면의 기준으로 선택한다. 두 원본 manifest에 voice ID/모델이 없어 실제 음색 일치 여부는 청취가 필요하다.
- 광장 전용9종의 단일 파일은5초 미만이다. 문서의 연속5초 발화/10~20초 권장 조건을 만족한다고 볼 수 없다. 더 긴 같은 캐릭터 샘플 확보 또는 제공사에서 인정하는 샘플 조건 확인이 필요하다.
- 이야기 종도 단일 발화 길이와 품질을 별도 확인해야 한다. 서로 다른 문장을 붙이거나 반복해서 샘플 조건을 충족했다고 간주하지 않는다.
- 이전 Desktop/allo_tts 폴더는 현재 존재하지 않는다.

## 준비 도구 및 검증

```sh
python3 scripts/prepare_tts_manifest.py
python3 -m unittest discover -s scripts/tests -p test_prepare_tts_manifest.py -v
```

출력: `tasks/verification/dashscope/manifest.json` (로컬 전용).

도구는 현재 이야기 JSON과 광장 런타임 매핑을 읽어 화자·대사·적용 경로·참조 후보 해시를 내보낸다. 네트워크 호출이나 앱 에셋 수정은 하지 않는다. `model: null`, `status: prepared_not_generated`로 미생성 상태를 명시한다.

기존 카탈로그의 오래된 문구/중복 단계/출력 경로 충돌은 오류로 중단한다. 기존 불일치 결말2개는 게임 JSON의 현행 문구로 생성 대상에 포함한다. 이 결말의 런타임 카탈로그는 아직 변경하지 않았다.

회귀 검사3개 통과: 전체128소비 지점/104음성/17종 일치, 공유 캐릭터의 참조 통일, 결말 현행 문구, 오래된 카탈로그 차단. 실제 enrollment/synthesis, 복제 품질 청취, Qwen 음성으로 교체한 APK 출력은 미검증이다.
