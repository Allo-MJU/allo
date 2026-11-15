# 개인 스토리 교육 동행 최신화 확인

> 이 기록은 아래 커밋의 당시 검증이다. 이후 여행당 알 1개·서버 대화·캐릭터 탭 UI 변경의 최신 결과는 `2026-11-14-trip-egg-companion-invitation.md`를 따른다.

2026-11-14 · `fix/companion-learning-latest`

## 반영 내용

- 최신 `origin/dev` 확인 기준: `c15c12e`(#120). 기존 교육 동행 `d7e94e0`과 로컬 통합한 merge는 `7e60e73`.
- 최신 3D 캐릭터·소품, 창밖 실험 이야기, 여행 노트와 개인 스토리 교육 대화를 함께 유지.
- 이야기 액션 충돌, 중복 cast, 모달/노트 뒤의 대화·음성 수명, 중복 돌봄 UI를 수정.
- 표시용 canonical12에 맞춘 개인 고정 스토리 12편·36장면·지식22개. 기존 길싹이 v1 유지. 신규11편의 줄거리/페르소나는 검토 대기 초안.
- 새6종의 출생지·속성·등급·획득 규칙을 임의로 정하지 않음. 콘텐츠가 준비됐다는 것이 새 획득 조건의 구현을 뜻하지 않음.
- 원래 작업 공간의 iOS 미커밋 변경은 보존. 통합은 별도 managed worktree에서 진행.

## 자동 검증

| 검증 | 결과 |
| --- | --- |
| 통합 Flutter 전체 | 459개 통과 |
| 공통 Dart core | 93개 통과 |
| 통합 Unity EditMode | 176개 통과 |
| 변경 범위 Flutter analyze | 문제 없음 |
| 최종 카탈로그 포함 서버 전체 | 38개 통과 |
| 숨김 키 입력 실행기 검사 | 1개 통과; 키 입력/실제 제공자 호출 없이 설정·비출력 경계 확인 |
| Dart client → 실제 Python HTTP 서비스 | 알 사진/호감도/부화 + 개인 이야기12종 모두 통과. 모델 응답은 주입한 테스트 대체 응답 |

서버 Python 환경은 `server/affinity/.venv`에 설치했다. `scripts/verify_affinity_api.py`의 기존 직접 모듈 로딩이 새 learning 모듈을 찾지 못하는 회귀를 실제 명령으로 재현하고 경로를 수정했다.

## APK와 에뮬레이터

- Unity scene/export 성공. debug APK 빌드129.4초, 약249MiB.
- APK: `phone/build/app/outputs/flutter-apk/app-debug.apk` (생성물·비공개 데모 설정은 Git 제외).
- SHA-256: `868153386c77d44a599dd95c907bd0e99b52529c1fe0beb8f9029ab099a28e9b`.
- Android API36 `ALLO_API_36` 에뮬레이터에 `adb install -r` 성공. 기존 데이터 유지, cold launch 성공.
- 마을 → 차 안 → 보유 친구 선택 → 길싹이 개인 이야기 → 다음 장면 전환을 화면으로 확인. 돌봄 버튼을 누르고 일부 3D 캐릭터가 화면에 나타나는 것도 관측했으나 모든 애니메이션 품질을 검증한 것은 아님.
- 서버가 꺼진 상태에서 실제 질문 전송 후 연결 실패 안내와 준비된 이야기 fallback을 확인. AI가 생성한 답변으로 표시하지 않음.
- Native IME 열림과 ASCII 텍스트 입력을 확인. 실제 아동 한국어 입력/STT/TTS 품질 확인과 구분한다.
- 앱 프로세스의 확인 범위 logcat에서 FATAL EXCEPTION/Flutter 오류/NullReferenceException 없음. 기기 전체 시스템 로그에 있는 별도 시스템 서비스 메시지는 앱 오류로 세지 않음.
- 캡처: `docs/work-results/unity-phone/companion-learning-latest/01-home.png`부터 `05-next-care.png`까지.

Unity 내보내기가 재생성한 prefab/scene fileID 변경은 APK 생성 후 원래 커밋 버전으로 복원해 대량의 생성물 변경을 남기지 않았다. 모델을 만드는 코드와 최신 원본 에셋은 통합 커밋에 보존되어 있다.

## 키 설정 전 남아 있는 확인

- OPENAI_API_KEY가 없어 실제 제공자의 교육 대화 응답·사실 준수·페르소나 일관성은 호출 검증하지 않음.
- 실제 폰/차량, 한국어 STT 및 혼합 영어 TTS, 외부 음성 인식 중 Home 후 복귀 취소 보장은 아직 미확인.
- 현재 APK는 Mac+Android 에뮬레이터용 로컬 API 주소와 데모 토큰으로 빌드. OpenAI API 키는 APK·파일에 넣지 않았음.
- 원격 서버 배포·원격 dev 브랜치 병합/푸시는 수행하지 않음.
- 다음 순서는 `docs/companion-learning-local-setup.md`. 키는 사용자가 숨김 입력으로 제공하고, 서버를 켠 뒤 실제 호출을 검증한다.
