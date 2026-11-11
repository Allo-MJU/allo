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
