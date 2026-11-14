using Allo.Bridge;
using Allo.World;
using UnityEngine;

namespace Allo.CameraRig
{
    /// 주행 화면에 처음 들어올 때의 연출: 뒤쪽 하늘에서 우리 차와 앞 풍경을 비스듬히 내려다보다가 차 뒤로 내려와 뒷좌석에 앉는다.
    /// 차는 실내 모델 그대로다: 밖에 있는 동안만 벽·지붕을 양면으로 그리고 바퀴(WorldDirector.MakeIntroShell)를 단다.
    /// 바깥 풍경은 그때의 장면(SceneState) 그대로다. 화면을 누르면 바로 자리에 앉는다.
    public sealed partial class CameraRig
    {
        public const float IntroSeconds = 5.5f;

        /// 테스트·배치 캡처가 끈다
        public static bool IntroEnabled = true;
        public static bool IntroActive => _instance != null && _instance._intro;

        /// 촬영 모드(FilmMode): 차 안에 들어올 때마다 다시 보여 준다
        public static bool IntroEveryTime;

        static bool _introPlayed; // 앱을 켠 뒤 한 번만
        bool _introWanted, _intro, _introInside;
        float _introT;
        Transform _shell;
        readonly System.Collections.Generic.Dictionary<Material, float> _introCull = new System.Collections.Generic.Dictionary<Material, float>();
        Vector3 _introGround, _introForward;
        Bounds _introCabin;

        /// 실내 모델을 감싸는 상자와, 차 방향으로 잰 길이·너비
        public static bool CabinBox(GameObject cabin, Vector3 forward, out Bounds bounds, out float length, out float width)
        {
            bounds = new Bounds(); length = width = 0;
            var first = true;
            foreach (var r in cabin.GetComponentsInChildren<Renderer>())
            {
                if (!r.enabled) continue;
                if (first) { bounds = r.bounds; first = false; } else bounds.Encapsulate(r.bounds);
            }
            length = Mathf.Abs(forward.x) * bounds.size.x + Mathf.Abs(forward.z) * bounds.size.z;
            width = Mathf.Abs(forward.z) * bounds.size.x + Mathf.Abs(forward.x) * bounds.size.z;
            return !first;
        }

        /// 실내 재질(Allo/Toon)을 양면(밖에서 볼 때) 또는 원래대로 돌린다. saved 에 원래 값을 적어 둔다
        public static void CabinTwoSided(GameObject cabin, bool on, System.Collections.Generic.Dictionary<Material, float> saved)
        {
            if (on)
            {
                foreach (var r in cabin.GetComponentsInChildren<Renderer>())
                foreach (var m in r.sharedMaterials)
                    if (m != null && m.HasProperty("_Cull") && !saved.ContainsKey(m)) { saved[m] = m.GetFloat("_Cull"); m.SetFloat("_Cull", 0); }
                return;
            }
            foreach (var pair in saved)
                if (pair.Key != null) pair.Key.SetFloat("_Cull", pair.Value);
            saved.Clear();
        }

        /// 눈 자리(eye)로 끝나는 길. t 는 0~1, ground 는 차 가운데 아래 노면, forward 는 차가 달리는 방향
        public static void IntroPose(float t, Vector3 ground, Vector3 forward, Vector3 eye, Quaternion eyeRotation,
            out Vector3 position, out Quaternion rotation)
        {
            var f = forward; f.y = 0; f.Normalize();
            var up = Vector3.up;
            // 뒤쪽 높은 곳에서 비스듬히(앞 풍경이 보이게) → 차 뒤로 내려와 따라가며 → 지붕 뒤 → 뒷좌석
            var p = new[]
            {
                ground + up * 27f - f * 24f,
                ground + up * 15f - f * 16f,
                ground + up * 5f - f * 9.5f,
                eye + up * 1.7f - f * 2.6f,
                eye,
            };
            var r = new[]
            {
                Quaternion.LookRotation(ground + f * 10f - p[0], up),
                Quaternion.LookRotation(ground + f * 9f - p[1], up),
                Quaternion.LookRotation(ground + f * 8f + up * 1f - p[2], up),
                Quaternion.LookRotation(eye + f * 6f - p[3], up),
                eyeRotation,
            };
            // 천천히 떠나 천천히 앉는다
            t = Mathf.Clamp01(t);
            var u = t * t * (3f - 2f * t) * (p.Length - 1);
            var i = Mathf.Min((int)u, p.Length - 2);
            var k = u - i;
            Vector3 P(int n) => p[Mathf.Clamp(n, 0, p.Length - 1)];
            position = CatmullRom(P(i - 1), P(i), P(i + 1), P(i + 2), k);
            rotation = Quaternion.Slerp(r[i], r[i + 1], Mathf.SmoothStep(0, 1, k));
        }

        static Vector3 CatmullRom(Vector3 a, Vector3 b, Vector3 c, Vector3 d, float k) =>
            0.5f * (2f * b + (c - a) * k + (2f * a - 5f * b + 4f * c - d) * k * k + (3f * b - a - 3f * c + d) * k * k * k);

        bool BeginIntro()
        {
            _introWanted = false;
            if (!IntroEnabled || _introPlayed && !IntroEveryTime || rearAnchor == null || lookTarget == null) return false;
            _introPlayed = true;
            if (FlutterBridge.LastSettings != null && FlutterBridge.LastSettings.reducedMotion) return false;
            var world = FindFirstObjectByType<WorldDirector>();
            var cabin = GameObject.Find("Cabin");
            if (world == null || cabin == null) return false;
            _introForward = world.forward; _introForward.y = 0; _introForward.Normalize();
            _introGround = new Vector3(world.carCenter.x, world.roadY, world.carCenter.z);
            if (!CabinBox(cabin, _introForward, out _introCabin, out var length, out var width)) return false;
            _shell = world.MakeIntroShell(width, length, Vector3.Dot(_introCabin.center - _introGround, _introForward), _introCabin.min.y - world.roadY);
            CabinTwoSided(cabin, true, _introCull);
            _introInside = false;
            _introT = 0;
            _intro = true;
            return true;
        }

        /// 연출 중이면 카메라를 옮기고 true (그 프레임의 둘러보기 입력은 받지 않는다)
        bool IntroTick()
        {
            if (_introWanted) BeginIntro();
            if (!_intro) return false;
            var skip = _introT > 0.08f && (Input.touchCount > 0 || Input.GetMouseButtonDown(0));
            _introT = skip ? 1 : _introT + Time.deltaTime / IntroSeconds;
            var eyeRotation = Quaternion.Euler(0, _baseYaw, 0);
            IntroPose(_introT, _introGround, _introForward, rearAnchor.position, eyeRotation, out var pos, out var rot);
            if (!_introInside && _introCabin.Contains(pos)) EnterCabin();
            transform.SetPositionAndRotation(pos, rot);
            if (_introT >= 1) EndIntro();
            return _intro;
        }

        void EnterCabin()
        {
            _introInside = true;
            if (_shell != null) Destroy(_shell.gameObject);
            _shell = null;
            CabinTwoSided(null, false, _introCull);
        }

        /// 연출을 끝내고 뒷좌석 정면에서 둘러보기를 시작한다. 중간에 화면이 바뀌어도(OnDisable) 실내를 되돌린다
        void EndIntro()
        {
            if (!_intro) return;
            EnterCabin();
            _intro = false;
            _state = default;
            _velocity = Vector2.zero;
        }
    }
}
