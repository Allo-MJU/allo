using UnityEngine;
using Rig = Allo.CameraRig.CameraRig;

namespace Allo
{
    /// 영상 촬영용: 화면 위 UI(버튼·패널·HUD)를 그리지 않고 장면만 보인다. UI 코드는 건드리지 않고 캔버스만 끈다.
    /// - 진입 연출(CameraRig.Intro) 동안은 늘 가린다
    /// - 촬영 모드를 켜면 차 안에서는 계속 가리고, 차 안에 들어올 때마다 진입 연출을 다시 보여 준다
    /// 켜고 끄기: 세 손가락으로 화면을 한 번 누른다. 또는 기기에 파일을 둔다 (지우면 꺼진다, 앱 다시 시작).
    /// 파일에 배경 이름(road | coast | mountain | city | highway)을 적으면 그 배경으로 고정한다.
    /// shot1 ~ shot4 를 적으면 앱 화면 대신 정해 둔 장면을 카메라 고정으로 보여 준다 (소개 영상 소재):
    ///   shot1 숲 고속도로를 달리는 빈 차 안 / shot2 알 부화 (화면을 누르면 4초 뒤 시작) /
    ///   shot3 멈춘 차, 옆자리 길싹이 / shot4 달리는 우리 차를 위에서
    ///   adb shell "echo coast > /sdcard/Android/data/ai.allo.allo_phone/files/film"
    public sealed class FilmMode : MonoBehaviour
    {
        public static bool On;

        readonly System.Collections.Generic.List<Canvas> _hidden = new System.Collections.Generic.List<Canvas>();
        bool _threeDown;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            var file = System.IO.Path.Combine(Application.persistentDataPath, "film");
            On = System.IO.File.Exists(file);
            if (On)
            {
                var kind = System.IO.File.ReadAllText(file).Trim();
                if (System.Array.IndexOf(new[] { "road", "coast", "mountain", "city", "highway" }, kind) >= 0) World.WorldDirector.FilmKind = kind;
                if (kind.Length == 5 && kind.StartsWith("shot") && kind[4] >= '1' && kind[4] <= '4') _shot = kind[4] - '0';
            }
            Rig.IntroEveryTime = On;
            var go = new GameObject("FilmMode");
            DontDestroyOnLoad(go);
            var film = go.AddComponent<FilmMode>();
            if (_shot > 0)
            {
                Bridge.FlutterBridge.Hold = true;
                Rig.IntroEnabled = false;
                film.StartCoroutine(film.Shot(_shot));
            }
        }

        static int _shot;
        Camera _cam;
        Vector3 _camAt;
        Quaternion _camRot;
        Critters.CritterDirector _critters;
        bool _holdCompanion;

        void Pose(Vector3 at, Quaternion rot) { _camAt = at; _camRot = rot; }

        System.Collections.IEnumerator Shot(int n)
        {
            yield return null; yield return null; // 장면의 Start 가 끝난 뒤
            _cam = Camera.main;
            var rig = _cam.GetComponent<Rig>();
            rig.enabled = false; // 카메라 고정: 손가락·자이로·연출로 움직이지 않는다
            if (_cam.TryGetComponent<TapInput>(out var tap)) tap.enabled = false;
            var world = FindFirstObjectByType<World.WorldDirector>();
            _critters = FindFirstObjectByType<Critters.CritterDirector>();
            var eye = rig.rearAnchor.position;
            var dir = rig.lookTarget.position - eye;
            var yaw = Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg;
            Pose(eye, Quaternion.Euler(0, yaw, 0));
            var driving = new Bridge.SceneState { kind = "highway", highway = true, moving = true, speedKph = 90 };
            var sprout = new Bridge.CastState { companion = new Bridge.CastMember { id = "road_sprout", sprite = "", attribute = "normal" }, friends = new Bridge.CastMember[0] };
            Bridge.FlutterBridge.Inject(new Bridge.CastState { friends = new Bridge.CastMember[0] });
            Bridge.FlutterBridge.Inject(new Bridge.EggState { state = "idle", eggId = "", bornText = "" });
            var scene = n == 3 ? new Bridge.SceneState { kind = "highway", highway = true, moving = false, speedKph = 0 } : driving;
            Bridge.FlutterBridge.Inject(scene);
            world.Apply(scene, reset: true);
            world.EditorStep(150); // 뒤쪽 길도 깔리게 조금 달린 자리에서 시작한다
            yield return null;
            world.SnapSpeed();
            // 알이 없는 장면에서는 빈 둥지도 치운다
            var nest = _critters != null ? _critters.transform.Find("EggNest") : null;
            if (nest != null && n != 2) nest.gameObject.SetActive(false);
            switch (n)
            {
                case 2:
                    Bridge.FlutterBridge.Inject(new Bridge.EggState { state = "incubating", progress = 0.2f, eggId = "film", bornText = "" });
                    yield return new WaitUntil(() => Input.touchCount > 0 || Input.GetMouseButtonDown(0));
                    yield return new WaitForSeconds(4f);
                    // 알 → 동행 순서: 깨지는 동안에는 동행을 세우지 않고, 다 깨지면 둥지에서 나온다
                    Bridge.FlutterBridge.Inject(new Bridge.EggState { state = "hatched", progress = 1, eggId = "film", bornText = "길싹이가 태어났어요!" });
                    Bridge.FlutterBridge.Inject(sprout);
                    yield return new WaitForSeconds(9f);
                    _holdCompanion = true; // 인사를 마치면 통로에 서 있는다
                    break;
                case 3:
                    Critters.CritterDirector.Mute = true;
                    Bridge.FlutterBridge.Inject(sprout);
                    _holdCompanion = true;
                    Pose(eye, Quaternion.Euler(15, yaw + 72, 0)); // 옆자리와 그 너머 창
                    break;
                case 4:
                    var f = world.forward; f.y = 0; f.Normalize();
                    var ground = new Vector3(world.carCenter.x, world.roadY, world.carCenter.z);
                    var cabin = GameObject.Find("Cabin");
                    if (cabin != null && Rig.CabinBox(cabin, f, out var box, out var length, out var width))
                    {
                        world.MakeIntroShell(width, length, Vector3.Dot(box.center - ground, f), box.min.y - world.roadY, out var solid);
                        if (solid) foreach (var r in cabin.GetComponentsInChildren<Renderer>()) r.enabled = false;
                        else Rig.CabinTwoSided(cabin, true, new System.Collections.Generic.Dictionary<Material, float>());
                    }
                    if (_critters != null) _critters.gameObject.SetActive(false);
                    var at = ground + Vector3.up * 19f - f * 8f;
                    Pose(at, Quaternion.LookRotation(ground + f * 4f - at, Vector3.up));
                    break;
            }
        }

        void Update()
        {
            var three = Input.touchCount == 3;
            if (three && !_threeDown) { On = !On; Rig.IntroEveryTime = On; }
            _threeDown = three;
        }

        void LateUpdate()
        {
            if (_cam != null) _cam.transform.SetPositionAndRotation(_camAt, _camRot);
            if (_holdCompanion && _critters != null && _critters.Companion != null) _critters.Companion.Brain.Hold = true;
            var rig = Camera.main != null ? Camera.main.GetComponent<Rig>() : null;
            var cabin = rig != null && rig.enabled;
            var hide = Rig.IntroActive || On && (cabin || _shot > 0);
            if (!hide)
            {
                foreach (var c in _hidden) if (c != null) c.enabled = true;
                _hidden.Clear();
                return;
            }
            // 연출·촬영 중에 새로 생긴 캔버스도 가린다 (화면 위에 얹는 것만. 말풍선 같은 장면 속 캔버스는 둔다)
            foreach (var c in FindObjectsByType<Canvas>(FindObjectsSortMode.None))
                if (c.enabled && c.isRootCanvas && c.renderMode != RenderMode.WorldSpace) { c.enabled = false; _hidden.Add(c); }
        }
    }
}
