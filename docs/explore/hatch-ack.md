# 탐험 부화 완료 확인

#101 / #91 통합에서 `hatched` 상태를 Unity에 보냈다는 이유만으로 부화 연출을 본 것으로 처리하던 경로를 수정했다.

Unity → Flutter 완료 메시지:

```json
{"v":1,"type":"hatchShown","eggId":"현재 알 ID"}
```

Unity `CritterDirector.Hatch`는 흔들림·금·빛 연출 후 둥지에서 동행을 꺼내고 태어남 문구를 표시한 뒤 한 번 보낸다. 알이 교체되거나 사라져 연출이 중단되면 보내지 않는다. `eggId`는 시작한 `egg` 메시지의 ID이며 기존 거리/시간 모드의 ID가 없으면 빈 문자열이다.

Flutter는 Unity가 ready인 현재 탐험 route에서 직접 incubating을 관찰했고, 같은 알이 현재 hatched이며, 세션과 화면이 닫히지 않았을 때만 확인을 인정한다. ready/egg 발행 자체는 완료 증거가 아니다. 기존에 부화한 알로 탐험에 들어온 경우와 다른 알 ID의 확인은 무시한다.

닫을 때 완료 확인이 없으면 기존 Flutter `/hatching` 경로를 사용한다. 따라서 이전 Unity export처럼 이 메시지를 보내지 않는 버전도 부화 연출을 건너뛰지 않는다. 새 Unity export를 만들어야 Unity 연출 완료 후 Flutter 연출 생략이 적용된다.

회귀 검증: Unity 준비 전 닫기, 완료 확인 없이 닫기, 잘못된 ID, 부화 전 확인, 다른 route가 열린 동안 확인, 정상 확인, 이미 부화한 상태로 진입. Flutter 테스트는 bridge 메시지를 모의 주입한다. 이 환경에는 Unity Editor가 없어 C# 컴파일·EditMode·Android 재export·실기 완료 타이밍은 검증하지 못했다.
