# 차 안·밖 탐험 게임 — 기반 (0~1단계) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flutter 폰 앱 안에 Unity 탐험 화면을 띄우고, 차 신호를 메시지로 넘기며, 스크립트로 만든 3D 차 내부를 가로 화면에서 360도로 둘러볼 수 있게 한다.

**Architecture:** Flutter 가 `/vehicle` 구독·판정을 그대로 맡고, 표시에 필요한 값만 JSON 메시지(v1)로 Unity 에 보낸다. Unity 는 `flutter_unity_widget`(Unity as a Library)로 한 화면에 들어간다. 3D 모델은 Blender Python 스크립트가 `.glb` 로 만들고 Unity 는 glTFast 로 읽는다. Unity 빌드가 없으면 기존 `WindowView` 로 대체한다.

**Tech Stack:** Flutter (기존), `flutter_unity_widget`, Unity 6 LTS + Android Build Support, glTFast(`com.unity.cloud.gltfast`), Blender 4.x (`blender -b -P`), Unity Test Framework (EditMode).

**Spec:** `docs/superpowers/specs/2026-11-09-car-explore-design.md`

**이후 계획:** 2단계(창밖)·3단계(캐릭터)·4단계(물체 놀이)·5단계(앱 가로 개편)·6단계(다듬기)는 이 계획의 Task 1 결과(연동 가능 여부)를 보고 단계마다 따로 쓴다.

## Global Constraints

- 판정은 `allo_core` 에서만 한다. Unity 는 표시·놀이 전용이다 (CLAUDE.md 규칙 5)
- Unity 는 Firebase 에 접근하지 않고 위도·경도를 받지 않는다. `envTags` 에서 만든 장면 값만 받는다 (CLAUDE.md 규칙 2)
- 메시지는 JSON 한 줄, 모든 메시지에 `"v":1` 과 `"type"` 이 있다. 모르는 필드·모르는 type 은 무시한다
- 카메라: 좌우 360도, 위아래 ±35도, 앞뒤는 뒷좌석 ↔ 앞좌석 레일 위에서만, 자이로는 설정으로 끌 수 있다
- 앱 전체 가로 고정 (Android `screenOrientation`, iOS `UISupportedInterfaceOrientations`, Flutter `setPreferredOrientations`)
- Unity 내보내기 결과(`phone/unity/`)는 git 에 넣지 않는다. Unity 없이도 `flutter test`·`flutter build apk` 가 통과해야 한다
- 색은 Figma ALLO Design System 변수 값을 `tools/blender/palette.py` 와 `Assets/Scripts/Common/Palette.cs` 한 곳씩에 둔다
- 커밋·PR 에 Claude 흔적(Co-Authored-By 등)을 남기지 않는다. 브랜치는 `dev` 에서 `feat/explore-*` 로 딴다

## Review Focus

1. **Unity 빌드 없이 앱 실행** — `phone/unity/` 가 비어 있어도 앱이 빌드되고 탐험 화면 대신 `WindowView` 가 보여야 한다 → Task 2 테스트 `unity 없으면 WindowView 로 대체`
2. **Unity 준비 전 메시지** — Unity 가 `ready` 를 보내기 전에 온 `scene`·`cast` 를 버리지 말고 마지막 값을 보내야 한다 → Task 2 테스트 `ready 전 메시지는 마지막 것만 모았다가 보낸다`
3. **모르는 필드·다음 버전 메시지** — `"v":2` 나 새 필드가 와도 Unity 가 죽지 않고, 아는 필드만 쓴다 → Task 3 테스트 `UnknownFieldsAndVersionAreTolerated`
4. **같은 스냅샷 반복·재구독** — `/vehicle` 이 같은 값을 여러 번 보내거나 재연결돼도 `jolt` 는 누적값이 늘 때 한 번만 → Task 2 테스트 `jolt 는 누적값이 늘 때만 한 번`
5. **앱 백그라운드 후 복귀** — 홈으로 갔다 돌아오면 Unity 화면이 멈춘 채 남지 않고 다시 그린다 → Task 6 수동 확인 항목 + Task 2 의 `didChangeAppLifecycleState` 처리

---

### Task 1: 연동 검증 (spike) — 빈 Unity 장면을 Flutter 에 넣기

설계 0단계. 이 Task 가 실패하면 멈추고 사용자에게 보고한다 (Flame 2.5D 전환 검토).

**Files:**
- Create: `unity/allo_explore/` (Unity 6 LTS 프로젝트, URP 3D 템플릿)
- Create: `unity/allo_explore/Assets/Scenes/Explore.unity`
- Create: `scripts/export_unity.sh` — Unity 를 배치 모드로 열어 Android 라이브러리를 `phone/unity/unityLibrary` 로 내보낸다
- Modify: `phone/pubspec.yaml` (dependency `flutter_unity_widget`)
- Modify: `phone/android/settings.gradle.kts`, `phone/android/app/build.gradle.kts` (unityLibrary 포함, 없으면 건너뜀)
- Modify: `.gitignore` (`phone/unity/`, `unity/allo_explore/{Library,Temp,Logs,Obj,Build,UserSettings}/`)
- Modify: `docs/verification.md` (spike 결과 절 추가)

**Interfaces:**
- Produces: `scripts/export_unity.sh` (인자 없음, 성공 시 `phone/unity/unityLibrary/build.gradle` 생성, exit 0)
- Produces: Unity 장면 `Explore` 안의 GameObject `FlutterBridge` (Task 3 이 스크립트를 붙인다)

- [ ] **Step 1:** Unity Hub 에 Unity 6 LTS + Android Build Support(SDK·NDK·OpenJDK) 가 설치됐는지 확인한다. 없으면 멈추고 사용자에게 설치를 요청한다.
  Run: `ls "/Applications/Unity/Hub/Editor/"`  Expected: `6000.0.` 으로 시작하는 폴더
- [ ] **Step 2:** `flutter_unity_widget` README 에서 Unity 6 지원 버전과 내보내기 방법을 확인하고, 그 버전을 `pubspec.yaml` 에 고정한다. 지원 버전이 없으면 멈추고 보고한다.
- [ ] **Step 3:** Unity 프로젝트를 만들고, 패키지가 제공하는 Unity 쪽 스크립트(`FlutterUnityIntegration`)를 가져온다. `Explore` 장면에는 회전하는 큐브 하나와 `FlutterBridge` 빈 GameObject 를 둔다.
- [ ] **Step 4:** `scripts/export_unity.sh` 를 쓴다. `"$UNITY" -batchmode -quit -projectPath unity/allo_explore -executeMethod <패키지의 Android 내보내기 메서드> -logFile -` 형태이며, `UNITY` 기본값은 Hub 설치 경로다.
- [ ] **Step 5:** 내보내기를 실행한다.
  Run: `scripts/export_unity.sh && test -f phone/unity/unityLibrary/build.gradle && echo OK`  Expected: `OK`
- [ ] **Step 6:** Android gradle 설정이 `phone/unity/unityLibrary` 가 **있을 때만** 포함하도록 한다 (Global Constraints: Unity 없이도 빌드).
  Run: `mv phone/unity /tmp/unity_off && (cd phone && flutter build apk --debug) ; mv /tmp/unity_off phone/unity`  Expected: 빌드 성공
- [ ] **Step 7:** 임시 화면에서 `UnityWidget` 을 띄워 휴대폰 에뮬레이터에서 큐브가 도는지 본다.
  Run: `cd phone && flutter run -d emulator-5554`  Expected: 큐브가 보이고, logcat 에 Unity 초기화 오류가 없다
- [ ] **Step 8:** 앱 용량 증가분과 첫 진입 시간을 재서 `docs/verification.md` 에 "탐험 spike" 절로 적는다 (설계 6절 기준: 용량 +80MB 이하, 진입 3초 이내).
- [ ] **Step 9: Commit**
  ```bash
  git add unity/allo_explore scripts/export_unity.sh phone/pubspec.yaml phone/pubspec.lock phone/android .gitignore docs/verification.md
  git commit -m "chore(explore): Unity as a Library 연동 spike (빈 장면, Android)"
  ```

---

### Task 2: Flutter 쪽 메시지와 탐험 화면

**Files:**
- Create: `phone/lib/explore/explore_messages.dart` — 메시지 만들기 (순수 Dart)
- Create: `phone/lib/explore/explore_link.dart` — Unity 준비 전 큐잉, 보낸 값 중복 제거
- Create: `phone/lib/explore/explore_screen.dart` — `UnityWidget` 또는 대체 `WindowView`
- Modify: `phone/lib/app.dart` (라우트 `/explore`)
- Test: `phone/test/explore_messages_test.dart`, `phone/test/explore_link_test.dart`, `phone/test/explore_screen_test.dart`

**Interfaces:**
- Consumes: `WindowScene` (`phone/lib/scene/window_scene.dart`), `VehicleState`, `Species` (`allo_core`), `GameController.collectedSpecies`, `GameController.hatched`
- Produces:
  - `String sceneMessage(WindowScene s)` → `{"v":1,"type":"scene","kind":"coast","night":false,"highway":false,"rain":2,"speedKph":62.0,"moving":true}`
  - `String castMessage({Species? companion, required List<Species> friends})` → `{"v":1,"type":"cast","companion":{"id","sprite","attribute"}|null,"friends":[...]}` (friends 최대 3, companion 은 friends 에서 뺀다)
  - `String joltMessage(String kind)` (`kind` 는 `"brake"` 또는 `"steer"`)
  - `String settingsMessage({required bool gyro, required bool reducedMotion})`
  - `class JoltDetector { List<String> update(VehicleState v); }` — 직전보다 `harshBrake`·`harshSteer` 가 늘었을 때만 `"brake"`/`"steer"` 를 돌려준다. 첫 스냅샷은 기준값만 잡고 빈 목록
  - `class ExploreLink { ExploreLink(void Function(String) send); void post(String type, String json); void onReady(); }` — `ready` 전에는 type 별 마지막 값만 모았다가 `onReady()` 때 보낸다. `jolt` 는 모으지 않고 버린다. 같은 type 에 같은 문자열이면 다시 보내지 않는다
  - `class ExploreScreen extends StatefulWidget { const ExploreScreen({required GameController controller, bool? unityAvailable}); }` — `unityAvailable` 이 null 이면 `bool.fromEnvironment('EXPLORE_UNITY')` 를 쓴다

- [ ] **Step 1: 실패하는 테스트를 쓴다** (`explore_messages_test.dart`)
  ```dart
  test('scene 메시지는 WindowScene 을 그대로 옮긴다', () {
    final m = jsonDecode(sceneMessage(const WindowScene(
        kind: SceneKind.coast, rainLevel: 2, speedKph: 62))) as Map;
    expect(m, {'v': 1, 'type': 'scene', 'kind': 'coast', 'night': false,
      'highway': false, 'rain': 2, 'speedKph': 62.0, 'moving': true});
  });
  test('cast 는 친구 최대 3, 동행 캐릭터는 친구에서 뺀다', () { /* companion=a, friends=[a,b,c,d,e] → friends ids [b,c,d] */ });
  test('jolt 는 누적값이 늘 때만 한 번', () {
    final d = JoltDetector();
    expect(d.update(v(brake: 0, steer: 0)), isEmpty);
    expect(d.update(v(brake: 1, steer: 0)), ['brake']);
    expect(d.update(v(brake: 1, steer: 0)), isEmpty); // 같은 값 반복
    expect(d.update(v(brake: 1, steer: 2)), ['steer']);
  });
  ```
- [ ] **Step 2:** `cd phone && flutter test test/explore_messages_test.dart` → FAIL (파일 없음)
- [ ] **Step 3:** `explore_messages.dart` 를 구현한다. `jsonEncode` 에 Map 을 넘긴다.
- [ ] **Step 4:** 같은 명령 → PASS
- [ ] **Step 5: 실패하는 테스트를 쓴다** (`explore_link_test.dart`)
  ```dart
  test('ready 전 메시지는 마지막 것만 모았다가 보낸다', () {
    final sent = <String>[];
    final link = ExploreLink(sent.add)
      ..post('scene', 's1')..post('scene', 's2')..post('cast', 'c1')..post('jolt', 'j1');
    expect(sent, isEmpty);
    link.onReady();
    expect(sent, unorderedEquals(['s2', 'c1']));
  });
  test('같은 값은 다시 보내지 않는다', () { /* ready 후 post('scene','s2') 두 번 → 한 번만 */ });
  ```
- [ ] **Step 6:** 실패 확인 → `explore_link.dart` 구현 → PASS 확인
- [ ] **Step 7: 실패하는 위젯 테스트를 쓴다** (`explore_screen_test.dart`)
  ```dart
  testWidgets('unity 없으면 WindowView 로 대체', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ExploreScreen(controller: fakeController(), unityAvailable: false)));
    expect(find.byType(WindowView), findsOneWidget);
  });
  ```
  `fakeController()` 는 기존 `test/widget_test.dart` 처럼 `FakeVehicleFeed` 로 `GameController` 를 만든다.
- [ ] **Step 8:** `ExploreScreen` 을 구현한다. `unityAvailable` 이면 `UnityWidget(onUnityCreated, onUnityMessage)` 를 쓰고, `controller` 변경마다 `SceneStabilizer` 를 거친 `WindowScene`·`castMessage`·`JoltDetector` 결과를 `ExploreLink.post` 로 보낸다. Unity 에서 `{"type":"ready"}` 가 오면 `onReady()`. `WidgetsBindingObserver` 로 `resumed` 때 `UnityWidgetController.resume()` 을 부른다. 라우트 `/explore` 를 추가한다.
- [ ] **Step 9:** `cd phone && flutter test` → 전체 PASS
- [ ] **Step 10: Commit**
  ```bash
  git add phone/lib/explore phone/lib/app.dart phone/test/explore_*_test.dart
  git commit -m "feat(explore): Flutter→Unity 메시지(v1)와 탐험 화면 (Unity 없으면 WindowView)"
  ```

---

### Task 3: Unity 쪽 메시지 받기 (Bridge)

**Files:**
- Create: `unity/allo_explore/Assets/Scripts/Bridge/Messages.cs` — 메시지 타입 (`[Serializable]` 클래스)
- Create: `unity/allo_explore/Assets/Scripts/Bridge/MessageParser.cs` — 순수 C#, MonoBehaviour 아님
- Create: `unity/allo_explore/Assets/Scripts/Bridge/FlutterBridge.cs` — `FlutterBridge` GameObject 에 붙는 MonoBehaviour
- Create: `unity/allo_explore/Assets/Scripts/Bridge/Allo.Bridge.asmdef`, `Assets/Tests/EditMode/Allo.Tests.EditMode.asmdef`
- Test: `unity/allo_explore/Assets/Tests/EditMode/MessageParserTests.cs`

**Interfaces:**
- Consumes: Task 2 의 JSON 형식 그대로
- Produces:
  - `public sealed class SceneState { public string kind; public bool night, highway, moving; public int rain; public float speedKph; }`
  - `public sealed class CastMember { public string id, sprite, attribute; }`, `public sealed class CastState { public CastMember companion; public CastMember[] friends; }`
  - `public static class MessageParser { public static bool TryParse(string json, out string type, out object payload); }` — `v` 가 1 이 아니어도 아는 필드는 읽는다. 깨진 JSON 은 false
  - `public sealed class FlutterBridge : MonoBehaviour { public static event Action<SceneState> SceneChanged; public static event Action<CastState> CastChanged; public static event Action<string> Jolted; public static event Action<bool,bool> SettingsChanged; public void OnFlutterMessage(string json); }` — `Start()` 에서 Flutter 로 `{"v":1,"type":"ready"}` 를 보낸다. 마지막 `SceneState`·`CastState` 를 `FlutterBridge.LastScene`·`LastCast` 로 들고 있어 늦게 구독한 쪽도 읽을 수 있다

- [ ] **Step 1: 실패하는 테스트를 쓴다** (`MessageParserTests.cs`)
  ```csharp
  [Test] public void ParsesScene() {
    Assert.IsTrue(MessageParser.TryParse("{\"v\":1,\"type\":\"scene\",\"kind\":\"coast\",\"night\":false,\"highway\":false,\"rain\":2,\"speedKph\":62.0,\"moving\":true}", out var t, out var p));
    Assert.AreEqual("scene", t);
    var s = (SceneState)p; Assert.AreEqual("coast", s.kind); Assert.AreEqual(2, s.rain); Assert.AreEqual(62f, s.speedKph);
  }
  [Test] public void UnknownFieldsAndVersionAreTolerated() {
    Assert.IsTrue(MessageParser.TryParse("{\"v\":2,\"type\":\"scene\",\"kind\":\"city\",\"newThing\":[1,2]}", out var t, out var p));
    Assert.AreEqual("city", ((SceneState)p).kind);
  }
  [Test] public void UnknownTypeIsIgnoredNotThrown() { Assert.IsTrue(MessageParser.TryParse("{\"v\":1,\"type\":\"dance\"}", out var t, out var p)); Assert.IsNull(p); }
  [Test] public void BrokenJsonReturnsFalse() { Assert.IsFalse(MessageParser.TryParse("{oops", out _, out _)); }
  ```
- [ ] **Step 2:** EditMode 테스트 실행 → FAIL
  Run: `"$UNITY" -batchmode -projectPath unity/allo_explore -runTests -testPlatform EditMode -testResults /tmp/editmode.xml; grep -o 'result="[A-Za-z]*"' /tmp/editmode.xml | head -1`
- [ ] **Step 3:** `MessageParser` 를 구현한다. `JsonUtility.FromJson` 으로 먼저 `{v,type}` 만 읽고, type 에 따라 해당 클래스로 다시 읽는다 (JsonUtility 는 모르는 필드를 무시한다). 예외는 잡아서 false.
- [ ] **Step 4:** 같은 명령 → `result="Passed"`
- [ ] **Step 5:** `FlutterBridge` 를 구현하고 `Explore` 장면의 `FlutterBridge` 에 붙인다. Task 1 의 큐브가 `SceneChanged` 를 받으면 `kind` 에 따라 색을 바꾸게 해서, 에뮬레이터에서 `FakeScenario.sceneTour` 로 메시지 왕복을 눈으로 확인한다 (이 큐브는 Task 5 에서 지운다).
- [ ] **Step 6:** `scripts/export_unity.sh && cd phone && flutter run -d emulator-5554 --dart-define=EXPLORE_UNITY=true --dart-define=SCENARIO=scene_tour` → 8초마다 큐브 색이 바뀐다
- [ ] **Step 7: Commit**
  ```bash
  git add unity/allo_explore/Assets/Scripts/Bridge unity/allo_explore/Assets/Tests unity/allo_explore/Assets/Scenes
  git commit -m "feat(explore): Unity 메시지 받기 (v1, 모르는 필드·버전 허용)"
  ```

---

### Task 4: Blender 로 차 내부 모델 만들기

**Files:**
- Create: `tools/blender/palette.py` — Figma 변수 값 (`car_ground`, `logo_ground`, `shell_yellow`, `egg_cream`, 시트·대시보드·내장재 색). 값은 PR #47 의 `_Palette`·`_CabinPainter` 색을 그대로 옮긴다
- Create: `tools/blender/kit.py` — 공용 도형 함수
- Create: `tools/blender/cabin.py` — 차 내부 전체를 만들어 `.glb` 와 미리보기 PNG 로 내보낸다
- Create: `tools/blender/README.md` — 실행 방법 한 줄씩
- Output (커밋함): `unity/allo_explore/Assets/Models/Cabin.glb`, `docs/work-results/explore/cabin_front.png`, `cabin_left.png`, `cabin_back.png`

**Interfaces:**
- Produces (`kit.py`): `rounded_box(name, size:(x,y,z), bevel:float, color:str, location:(x,y,z)) -> bpy.types.Object`, `cylinder(name, radius, depth, color, location, rotation=(0,0,0))`, `export_glb(path)`, `render_preview(path, camera_location, look_at)`
- Produces (`Cabin.glb` 안의 객체 이름 — Task 5·이후 단계가 이름으로 찾는다): `Shell`, `Seat_FL`, `Seat_FR`, `Headrest_FL`, `Headrest_FR`, `RearSeat`, `Armrest`, `Dashboard`, `Wheel`, `Mirror`, `MirrorCharm`, `DoorPanel_L`, `DoorPanel_R`, `DoorPanel_RL`, `DoorPanel_RR`, `Glass_Front`, `Glass_L`, `Glass_R`, `Glass_Back`, `Cushion`, `Plush`, `Bottle`, `DomeLight`, `RearShelf`
- 좌표: 미터 단위, 원점은 뒷좌석 가운데 바닥, +Z 위, -Y 앞(Blender). 아이 눈높이 카메라 위치 `(0, 0.25, 0.95)`

- [ ] **Step 1:** Blender 설치 확인. 없으면 `brew install --cask blender` (사용자 승인 후).
  Run: `/Applications/Blender.app/Contents/MacOS/Blender --version`  Expected: `Blender 4.`
- [ ] **Step 2:** `kit.py`·`palette.py`·`cabin.py` 를 쓴다. 모든 물체는 베벨로 모서리를 둥글리고(말랑한 장난감 느낌), 유리는 반투명 재질, 나머지는 단색 + 낮은 광택. 위 Interfaces 의 이름을 정확히 쓴다.
- [ ] **Step 3:** 실행한다.
  Run: `/Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/cabin.py -- --out unity/allo_explore/Assets/Models/Cabin.glb --preview docs/work-results/explore/`
  Expected: glb 1개 + PNG 3장 생성, 오류 없음
- [ ] **Step 4:** PNG 3장을 직접 열어 본다. 판단 기준: 좌석·대시보드·창틀이 알아볼 수 있고, 창문 자리가 뚫려 있고, 모서리가 둥글고, 색이 PR #47 차 안 뷰와 같은 계열이다. 아니면 고쳐서 Step 3 을 다시 한다.
- [ ] **Step 5:** glb 안의 객체 이름이 Interfaces 목록과 같은지 확인하는 검사를 `cabin.py --check` 로 넣고 실행한다. Expected: `names OK (24)`
- [ ] **Step 6: Commit** (사용자에게 렌더 3장을 보여 주고 스타일 확인을 받은 뒤)
  ```bash
  git add tools/blender unity/allo_explore/Assets/Models/Cabin.glb docs/work-results/explore
  git commit -m "feat(explore): Blender 스크립트로 차 내부 모델 생성 (glb + 미리보기)"
  ```

---

### Task 5: Unity 차 내부 장면과 카메라 둘러보기

**Files:**
- Create: `unity/allo_explore/Assets/Scripts/Camera/LookMath.cs` — 순수 C# (각도·레일 계산)
- Create: `unity/allo_explore/Assets/Scripts/Camera/CameraRig.cs` — 입력 → `LookMath` → 카메라
- Create: `unity/allo_explore/Assets/Scripts/Common/Palette.cs`
- Modify: `unity/allo_explore/Assets/Scenes/Explore.unity` (glTFast 로 `Cabin.glb` 배치, 조명, Task 1 큐브 삭제)
- Modify: `unity/allo_explore/Packages/manifest.json` (`com.unity.cloud.gltfast`)
- Test: `unity/allo_explore/Assets/Tests/EditMode/LookMathTests.cs`

**Interfaces:**
- Consumes: `FlutterBridge.SettingsChanged` (gyro on/off), `Cabin.glb` 객체 이름 (Task 4)
- Produces:
  - `public struct LookState { public float yaw; public float pitch; public float rail; }` — yaw 도 단위 [0,360), pitch [-35,35], rail [0,1] (0 = 뒷좌석, 1 = 앞좌석 사이)
  - `public static class LookMath { public const float PitchLimit = 35f; public static LookState Drag(LookState s, Vector2 deltaDegrees); public static LookState Pinch(LookState s, float deltaRail); public static LookState AddGyro(LookState s, Vector2 gyroDegrees, bool enabled); public static Vector3 RailPosition(float rail); }`
  - `RailPosition(0) = (0, 0.95, 0.25)`, `RailPosition(1) = (0, 1.0, -0.55)` (Unity 좌표, +Y 위, +Z 뒤 → glTFast 가 Blender 축을 바꾼 결과에 맞춘다)

- [ ] **Step 1: 실패하는 테스트를 쓴다** (`LookMathTests.cs`)
  ```csharp
  [Test] public void YawWrapsAround() { var s = LookMath.Drag(new LookState{yaw=350}, new Vector2(20,0)); Assert.AreEqual(10f, s.yaw, 1e-3); }
  [Test] public void PitchIsClamped() { var s = LookMath.Drag(new LookState(), new Vector2(0,90)); Assert.AreEqual(35f, s.pitch); }
  [Test] public void RailIsClamped() { Assert.AreEqual(1f, LookMath.Pinch(new LookState{rail=0.9f}, 0.5f).rail); Assert.AreEqual(0f, LookMath.Pinch(new LookState{rail=0.1f}, -0.5f).rail); }
  [Test] public void GyroOffDoesNothing() { var s = new LookState{yaw=10}; Assert.AreEqual(10f, LookMath.AddGyro(s, new Vector2(5,5), false).yaw); }
  ```
- [ ] **Step 2:** EditMode 테스트 실행 → FAIL (Task 3 Step 2 와 같은 명령)
- [ ] **Step 3:** `LookMath` 구현 → Step 2 명령 → `Passed`
- [ ] **Step 4:** `CameraRig` 를 구현한다. 한 손가락 드래그(화면 너비 = 180도), 두 손가락 핀치(손가락 거리 변화 / 화면 높이 = rail 변화), 자이로는 `Input.gyro.rotationRateUnbiased` 를 작게(0.3배) 더한다. 손을 떼면 관성 0.3초. 에디터에서는 마우스 드래그·스크롤로 같은 동작을 한다.
- [ ] **Step 5:** `Explore` 장면에 `Cabin.glb` 를 놓고, 실내 조명(주광 1 + 실내 채움광 1), 유리 재질, 창밖 자리에 임시 하늘색 배경을 둔다 (창밖은 2단계 계획).
- [ ] **Step 6:** 에뮬레이터에서 확인한다.
  Run: `scripts/export_unity.sh && cd phone && flutter run -d emulator-5554 --dart-define=EXPLORE_UNITY=true`
  Expected: 가로 화면에서 드래그로 앞유리 → 오른쪽 창 → 뒷유리 → 왼쪽 창이 차례로 보이고, 위아래는 35도에서 멈추고, 핀치로 앞좌석 사이까지만 나간다. 네 방향 스크린샷을 `docs/work-results/explore/emu_*.png` 로 남긴다
- [ ] **Step 7: Commit**
  ```bash
  git add unity/allo_explore/Assets unity/allo_explore/Packages docs/work-results/explore
  git commit -m "feat(explore): 차 내부 장면과 360도 둘러보기 카메라 (드래그·핀치·자이로)"
  ```

---

### Task 6: 앱 가로 고정과 탐험 화면 진입

**Files:**
- Modify: `phone/android/app/src/main/AndroidManifest.xml` (`android:screenOrientation="sensorLandscape"`)
- Modify: `phone/ios/Runner/Info.plist` (`UISupportedInterfaceOrientations` 에서 Portrait 제거, iPad 도 Landscape 만)
- Modify: `phone/lib/main.dart` (`SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])`)
- Modify: `phone/lib/screens/companion_screen.dart`, `phone/lib/screens/incubating_screen.dart` (탐험 화면으로 가는 버튼 "차 안 둘러보기", 라우트 `/explore`)
- Modify: `phone/test/widget_test.dart` (뷰포트를 가로 800×360 으로)
- Modify: `docs/verification.md` (가로·진입 확인 결과)

**Interfaces:**
- Consumes: `ExploreScreen`, 라우트 `/explore` (Task 2)
- Produces: 버튼 텍스트 `'차 안 둘러보기'` (위젯 테스트가 이 문자열로 찾는다)

- [ ] **Step 1: 실패하는 테스트를 쓴다** (`widget_test.dart` 에 추가)
  ```dart
  testWidgets('동행 화면에서 차 안 둘러보기로 탐험 화면에 간다', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080); tester.view.devicePixelRatio = 3; addTearDown(tester.view.reset);
    // 기존 흐름으로 동행 화면까지 간 뒤
    await tester.tap(find.text('차 안 둘러보기')); await tester.pumpAndSettle();
    expect(find.byType(ExploreScreen), findsOneWidget);
  });
  ```
- [ ] **Step 2:** `cd phone && flutter test test/widget_test.dart` → FAIL
- [ ] **Step 3:** 버튼·라우트·가로 고정을 구현한다. 기존 화면의 가로 레이아웃 개편은 5단계 계획에서 하고, 여기서는 **가로에서 넘치지 않게만** 한다 (넘치면 `SingleChildScrollView`).
- [ ] **Step 4:** `cd phone && flutter test` → 전체 PASS, `flutter analyze` → No issues
- [ ] **Step 5:** 에뮬레이터 수동 확인: 앱 시작부터 가로, 동행 화면 → "차 안 둘러보기" → 탐험 화면, 홈 버튼으로 나갔다 돌아와도 Unity 화면이 다시 그려진다 (Review Focus 5). 결과를 `docs/verification.md` 에 적는다.
- [ ] **Step 6: Commit**
  ```bash
  git add phone docs/verification.md
  git commit -m "feat(explore): 앱 가로 고정, 동행·알 품기 화면에서 탐험 화면 진입"
  ```

---

### Task 7: 주행 중 연결 테스트 (Pleos 에뮬레이터 → Firebase → 폰)

설계 1절 "주행 중 사용 — 확인한 뒤 확정". 사용자가 `phone/config/firebase.local.json` 을 만든 뒤에만 한다. 이 파일의 내용은 열거나 출력하지 않는다.

**Files:**
- Modify: `docs/verification.md` (주행 중 탐험 화면 절)
- Modify: `docs/superpowers/specs/2026-11-09-car-explore-design.md` (열린 질문 3 확정)

- [ ] **Step 1:** 파일 존재만 확인한다. Run: `test -f phone/config/firebase.local.json && echo ready` Expected: `ready` (없으면 멈추고 사용자에게 요청)
- [ ] **Step 2:** Pleos 에뮬레이터를 켜고 차량 앱을 설치한다 (`CLAUDE.local.md` 의 빌드·설치 명령). 휴대폰 에뮬레이터에서 `flutter run --dart-define-from-file=config/firebase.local.json --dart-define=FEED=firebase --dart-define=EXPLORE_UNITY=true` 로 실행하고 페어링한다.
- [ ] **Step 3:** `scripts/demo_sea_trip.sh` 로 주행을 재현하며 탐험 화면을 연다. 확인 항목: 기어 D·속도가 오르는 동안 화면이 멈추지 않는다, `scene` 메시지가 지역 바뀔 때 온다(Unity 로그), 급제동 주입 시 `jolt` 가 한 번 온다, 신호 지연(VC 요청 → Unity 로그 시각).
- [ ] **Step 4:** 결과를 `docs/verification.md` 에 적고, 설계 문서 열린 질문 3 을 "주행 중 허용"(또는 측정 결과에 따른 결정)으로 고친다.
- [ ] **Step 5: Commit**
  ```bash
  git add docs/verification.md docs/superpowers/specs/2026-11-09-car-explore-design.md
  git commit -m "docs(explore): 주행 중 탐험 화면 연결 테스트 결과"
  ```
