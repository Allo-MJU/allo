# 차량 UI 미리보기

표준 Android 에뮬레이터에서 실제 `DrivingScreen` / `ParkedScreen` Compose UI를 테스트 데이터로 실행합니다. Pleos 센서, Firebase, 실제 폰 이동, 화면 공유 또는 내비게이션 성공을 검증하는 앱이 아닙니다.

```sh
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ANDROID_HOME="$HOME/Library/Android/sdk" sh ./gradlew -PincludePreview=true :preview:assembleDebug
adb install -r preview/build/outputs/apk/debug/preview-debug.apk
adb shell am start -n ai.allo.preview/.PreviewActivity --es mode parked --es species road_sprout
```

`mode`: `parked` / `driving`, `species`: 카탈로그 ID, `disconnected`: boolean extra.

상단 버튼에서 주행/주차와 기존·품기준비·실패·폰이동·거점·연결끊김 상태를 선택합니다. 품기준비는 새 알 진행률과 기존 동행 캐릭터를 동시에 보여줍니다. 호감도 준비 완료와 부화 성공은 별개입니다. 거점은 알 상태와 무관한 읽기 전용 요약입니다.

주행 화면은 기존 달리기 프레임, 주차 화면은 기존 잠자기·낚시 프레임을 재사용합니다. 6종(`road_sprout`, `puddle_pip`, `lamp_moth`, `storm_lantern`, `highway_comet`, `sea_mist`)에 대응하는 8프레임 시트를 사용하고 나머지는 기존 폴백을 유지합니다. 신규 아트는 생성하지 않습니다. 연결 끊김, 백그라운드, 시스템 애니메이션 설정은 기존 모션 게이트를 따릅니다.

v2 테스트 상태에서 ‘폰으로 친구 부르기’는 모의 수락 응답을 즉시 적용합니다. 기존 달리기 프레임으로 1회 퇴장한 뒤 폰 위치 안내를 표시합니다. 실제 앱은 폰의 일치하는 수락 응답 후에만 퇴장합니다. 실제 요청/타임아웃/중복 응답은 별도 상태 머신 테스트와 실기 통합 검증 대상입니다.

실차 검증: 주행 애니메이션 허용 정책, 제한 전환, 폰 응답과 위치 동기화, 거점/호감도 실제 데이터, 화면 공유와 내비게이션은 로컬 todo에서 관리합니다.

## 로컬 폰 낚시 연동 모드 (개발 전용)

`--ez localDemo true`로 실행하면 정적인 시안 대신 호스트 `127.0.0.1:8765`의 모의 전송 서버를 사용한다. Android에서는 `10.0.2.2:8765`로 접속한다.

```sh
adb -s emulator-5554 shell am force-stop ai.allo.preview
adb -s emulator-5554 shell am start -n ai.allo.preview/.PreviewActivity --ez localDemo true
```

폰이 전체 game snapshot을 게시하면 실제 parser·낚시 요청 controller·화면을 사용한다. 차량은 P/UX 허용을 모의하고 앱 활성 상태와 폰 revision freshness를 반영한 presence를 전송한다. 시간 계산·보상·저장은 폰 소유이며 차량은 결과를 만들지 않는다. 시작·일시정지·재개·저장 재시도와 저장된 관찰 수를 확인할 수 있다. Firebase, Pleos 센서 및 실제 차량 검증을 대신하지 않는다. 기본 실행은 기존 정적 미리보기다.

모의 전송도 production FirebaseRest와 동일하게 `Json { encodeDefaults = true }`로 직렬화한다. `FishingPresence.version=1` 같은 필수 기본값이 wire에서 생략되면 폰은 유효 신호로 인정하지 않는다.

서버·폰 빌드·두 에뮬레이터 실행 및 검증 범위: [로컬 낚시 연동 안내](../../docs/vehicle/local-fishing-demo.md).
