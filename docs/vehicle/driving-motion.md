# #92 차량 속도 연동 모션

차량 화면의 실제 AAOS 속도와 기어를 로컬에서 읽고, 기존 달리기 시트의 재생 시간에 반영한다. Firebase 또는 폰의 1초 game 갱신을 모션 시계로 사용하지 않는다. 게임 점수·보상·호감도는 변경하지 않는다.

- 속도별 달리기 재생률은 상한을 두며 프레임 위상을 유지해 부드럽게 변경한다. 정지하면 idle.
- 급감속은 유효한 센서 타임스탬프로 최근 600ms 구간의 속도 회귀 기울기를 계산한다. 최소 400ms·3개 샘플, 총 3km/h 이상 감소, 시작 속도 10km/h 이상, 감속률 12km/h/s 이상을 만족하고 다음 샘플에서 100ms 이상 지속되어야 발생한다. Float m/s 변환 오차에는 0.0001 허용치를 둔다.
- 동일 속도 콜백도 관측에 포함해 정수 속도 계단과 콜백 시점 흔들림을 평활화한다. 단일 저속 스파이크 후 회복은 넘어짐을 발생시키지 않는다. 작은 노이즈·반복 타임스탬프·오래된 샘플·P/R/N/알 수 없는 기어는 급제동으로 판정하지 않는다.
- AAOS 구독은 SENSOR_RATE_UI(통상 5Hz)를 요청한다. 센서 신호 1.5초 만료 시 모션을 중지한다. 이벤트 2초 쿨다운과 500ms 감속 종료 확인으로 연속 넘어짐을 방지한다. 실제 관측률이 낮으면 감지 지연이 늘어나며, 500ms 샘플 테스트에서는 최초 관측부터 최대 1.5초가 필요하다.
- 새 급제동 이벤트에만 fall 시트를 한 번 재생한다. 넘어짐→잠깐 엎드림→일어남 후 현재 속도로 복귀한다.
- 연결/센서 만료·백그라운드·시스템 모션 꺼짐은 즉시 정지하며 복귀 때 과거 넘어짐을 재생하지 않는다.
- #92 기존 프레임·로고·레이아웃을 유지한다. 원본 캐릭터에 대응하는 6종 별도 fall-sheet를 사용한다.

## Pleos에서 재현

`app` debug의 `DrivingMotionDemoActivity`는 **실제 Pleos AAOS 신호 + 명시된 캐릭터 fixture**다. Firebase/폰 연결 없이도 production DrivingScreen 및 실제 센서 어댑터를 검증한다. 릴리스 빌드에는 이 Activity가 없다. 기본 종은 길싹이, `--es species <id>`로 6종 선택 가능하다.

```sh
adb shell pm grant --user 10 ai.allo.car android.car.permission.CAR_SPEED
adb shell am start --user current -S -W -n ai.allo.car/.debug.DrivingMotionDemoActivity
adb forward tcp:8088 tcp:8088
python3 scripts/demo_driving_motion.py
```

시나리오: 15 km/h → 85 km/h → 0.6초 급정지 → 일어남 → 40 km/h → 6초 완만한 감속. 종료·예외 시 속도 0/P 복원. 실차 주행 허용 정책·차종별 신호율과 감속 임계값은 별도 실기 검증 대상이다.


## 검증 기록 (2026-11-12)

- Pleos Connect 2.1.0 ARM64에서 실제 Virtual Console → VHAL → AAOS → 모션 연결로 위 시나리오를 두 차례 수행했다.
- 두 차례 모두 급정거 1회, 이후 40→0km/h·6초 완만한 감속은 추가 이벤트 0회였다. 종료 후 속도 0/P 복원을 확인했다.
- 첫 급감속 센서 샘플 이후 이벤트까지 각각 121ms/101ms였다. 이는 이미 쌓인 센서 관측 구간을 사용한 이번 시뮬레이션 결과이며 모든 실차의 지연 보장은 아니다.
- 227개/224개 실제 시뮬레이션 콜백의 상대 시간·속도·기어를 `app/src/test/resources/driving-motion-pleos-samples.csv`에 보존하여 두 시나리오를 순수 모델 회귀 테스트로 재생한다.
- debug 빌드의 `AlloSpeedSample` 로그는 센서 원본 시각·수신 시각·속도·기어를 남긴다. 릴리스에서는 비활성화된다. 상세 원본 로그는 로컬 `tasks/driving-motion-robust-run*.log`에만 보관한다.
- 실차, 실제 폰 연결, Firebase, 운전자 주의 분산 정책 승인을 검증한 결과는 아니다.
