using Rig = Allo.CameraRig.CameraRig;
using Allo.Critters;
using Allo.World;
using UnityEngine;
using UnityEngine.EventSystems;

namespace Allo
{
    /// 손가락 하나의 입력을 상황에 따라 나눈다. 판정하지 않고 CritterDirector·WorldDirector 에 넘긴다.
    ///
    /// - 간식·공을 들고 있으면: 톡 치거나 휙 밀어 그쪽으로 던진다
    /// - 캐릭터 위에서 시작한 끌기: 쓰다듬기 (짧게 떼면 탭 = 폴짝, 자고 있으면 담요)
    /// - 둥지의 알 위에서 시작한 끌기: 알 문지르기 (짧게 떼면 톡톡)
    /// - 유리를 꾹(0.45초) 누르면 입김, 김 서린 유리 위를 끌면 그림
    /// - 짧은 탭: 창밖 친구 발견, 비눗방울 터뜨리기, 놀이 물건(흔들 인형·장난감 차·오르골·그림책·비눗방울 병·휴지),
    ///   둥지(알이 없으면 동행이 쉰다), 물병(물)·인형·쿠션(작은 장난감), 천장등(불 끄면 잠), 머리받침 등 흔들림, 유리 반짝
    /// - 그 밖의 끌기: 둘러보기 (CameraRig). 위 동작 중에는 CameraRig.Locked 로 둘러보기를 멈춘다
    [RequireComponent(typeof(Camera))]
    public sealed class TapInput : MonoBehaviour
    {
        public CritterDirector critters;
        public WorldDirector world;
        public Light cabinLight;

        enum Mode { None, Look, Throw, Pet, Draw, Egg }

        const float LongPress = 0.45f;

        Camera _cam;
        Mode _mode;
        Vector2 _down, _last, _prev;
        float _downTime, _lastTime, _prevTime;
        bool _overUi;
        CritterView _petting;
        float _rub;
        FogGlass _glassAtDown;
        float _drawn;
        FogGlass _lastGlass;
        Vector2 _lastUv;

        void Awake() => _cam = GetComponent<Camera>();

        void Start()
        {
            // 유리 판에 김서림을 붙인다. 손가락 자리의 UV 를 얻으려고 상자 대신 메시 충돌체를 쓴다
            Physics.queriesHitBackfaces = true;
            foreach (var r in FindObjectsByType<MeshRenderer>(FindObjectsSortMode.None))
            {
                if (!r.name.StartsWith("Glass_") || r.GetComponent<FogGlass>() != null) continue;
                var mf = r.GetComponent<MeshFilter>();
                if (mf == null || mf.sharedMesh == null) continue;
                foreach (var col in r.GetComponents<Collider>()) Destroy(col);
                r.gameObject.AddComponent<MeshCollider>().sharedMesh = mf.sharedMesh;
                r.gameObject.AddComponent<FogGlass>();
            }
        }

        void Update()
        {
            if (Allo.App.AppSession.StoryActive || Allo.App.StoryOverlay.CapturingInput || Allo.CameraRig.CameraRig.IntroActive) { Cancel(); return; }
            FogGlass.Raining = world != null && world.Scene != null && world.Scene.rain > 0 && world.Scene.kind != "tunnel";
#if UNITY_EDITOR
            if (Input.GetMouseButtonDown(0)) Begin(Input.mousePosition, -1);
            else if (Input.GetMouseButton(0)) Move(Input.mousePosition);
            if (Input.GetMouseButtonUp(0)) End(Input.mousePosition);
#endif
            if (Input.touchCount == 1)
            {
                var t = Input.GetTouch(0);
                if (t.phase == TouchPhase.Began) Begin(t.position, t.fingerId);
                else if (t.phase is TouchPhase.Moved or TouchPhase.Stationary) Move(t.position);
                else if (t.phase == TouchPhase.Ended) End(t.position);
                else if (t.phase == TouchPhase.Canceled) Cancel();
            }
            else if (Input.touchCount > 1) Cancel();
        }

        void Begin(Vector2 p, int finger)
        {
            _down = _last = _prev = p;
            _downTime = _lastTime = _prevTime = Time.unscaledTime;
            _overUi = EventSystem.current != null && EventSystem.current.IsPointerOverGameObject(finger);
            _petting = null; _rub = 0; _glassAtDown = null; _drawn = 0; _lastGlass = null;
            _mode = Mode.Look;
            if (_overUi) { _mode = Mode.None; return; }
            if (critters != null && critters.Holding) { Lock(Mode.Throw); return; }
            if (!Physics.Raycast(_cam.ScreenPointToRay(p), out var hit, 80f)) return;
            var critter = hit.collider.GetComponentInParent<CritterView>();
            if (critter != null) { _petting = critter; Lock(Mode.Pet); return; }
            if (critters != null && critters.HasEgg && (critters.IsEgg(hit.collider) || critters.IsNest(hit.collider))) { Lock(Mode.Egg); return; }
            var glass = hit.collider.GetComponent<FogGlass>();
            if (glass != null)
            {
                _glassAtDown = glass;
                if (glass.FogAt(hit.textureCoord) > 0.25f) Lock(Mode.Draw);
            }
        }

        void Move(Vector2 p)
        {
            if (_mode == Mode.None) return;
            if ((p - _last).sqrMagnitude > 0.5f)
            {
                _prev = _last; _prevTime = _lastTime;
                _last = p; _lastTime = Time.unscaledTime;
            }
            switch (_mode)
            {
                case Mode.Look:
                    // 유리를 꾹 누르고 있으면 입김 → 그림 모드
                    if (_glassAtDown != null && Time.unscaledTime - _downTime > LongPress && (p - _down).magnitude < Screen.height * 0.03f
                        && Physics.Raycast(_cam.ScreenPointToRay(p), out var h, 80f) && h.collider.GetComponent<FogGlass>() == _glassAtDown)
                    {
                        _glassAtDown.Breathe(h.textureCoord);
                        Fx.Burst(h.point, Fx.Spark, critters != null ? critters.critterMaterial : null, 3, 0.05f, 0.08f);
                        Lock(Mode.Draw);
                    }
                    break;
                case Mode.Pet:
                    if (_petting == null) break;
                    _rub += (p - _prev).magnitude;
                    if (_rub > Screen.height * 0.05f)
                    {
                        critters?.Pet(_petting);
                        _rub = Screen.height * 0.03f; // 계속 문지르면 계속 좋아한다
                    }
                    break;
                case Mode.Egg:
                    _rub += (p - _prev).magnitude;
                    if (_rub > Screen.height * 0.05f)
                    {
                        critters?.RubEgg();
                        _rub = Screen.height * 0.03f;
                    }
                    break;
                case Mode.Draw:
                    if (Physics.Raycast(_cam.ScreenPointToRay(p), out var g, 80f))
                    {
                        var glass = g.collider.GetComponent<FogGlass>();
                        if (glass != null)
                        {
                            _drawn += glass == _lastGlass ? glass.WipeLine(_lastUv, g.textureCoord) : glass.Wipe(g.textureCoord);
                            _lastGlass = glass;
                            _lastUv = g.textureCoord;
                            critters?.Watch(g.point);
                        }
                    }
                    break;
            }
        }

        void End(Vector2 p)
        {
            var mode = _mode;
            _mode = Mode.None;
            Rig.Locked = false;
            if (mode == Mode.None || _overUi) return;
            var quick = (p - _down).magnitude <= Screen.height * 0.03f && Time.unscaledTime - _downTime <= 0.4f;
            switch (mode)
            {
                case Mode.Throw:
                {
                    // 뗀 자리 + 마지막 0.1초 동안 민 방향으로 조금 더 (휙 밀면 멀리)
                    var dt = Mathf.Max(0.016f, _lastTime - _prevTime);
                    var v = (_last - _prev) / dt;
                    var target = quick ? p : p + Vector2.ClampMagnitude(v * 0.12f, Screen.height * 0.35f);
                    target.x = Mathf.Clamp(target.x, 0, Screen.width);
                    target.y = Mathf.Clamp(target.y, 0, Screen.height);
                    critters?.Throw(target);
                    return;
                }
                case Mode.Pet:
                    if (quick && _petting != null && critters != null && !critters.ToggleBlanket(_petting)) critters.Poke(_petting);
                    return;
                case Mode.Draw:
                    if (_drawn > 0.5f) critters?.DrawDone();
                    return;
                case Mode.Egg:
                    if (quick) critters?.TapEgg();
                    return;
                default:
                    if (quick) Tap(p);
                    return;
            }
        }

        void Cancel()
        {
            _mode = Mode.None;
            Rig.Locked = false;
        }

        void Lock(Mode m)
        {
            _mode = m;
            Rig.Locked = true;
        }

        void Tap(Vector2 screen)
        {
            if (!Physics.Raycast(_cam.ScreenPointToRay(screen), out var hit, 80f)) return;
            var friend = hit.collider.GetComponentInParent<Passerby>();
            if (friend != null) { world?.Spot(friend); return; }
            if (critters != null)
            {
                if (critters.TryProp(hit)) return;
                if (critters.IsNest(hit.collider)) { critters.TapNest(); return; }
            }
            var wobble = hit.collider.GetComponentInParent<Wobble>();
            if (wobble != null)
            {
                wobble.Punch();
                var n = hit.collider.name;
                if (n.StartsWith("DomeLight") && cabinLight != null)
                {
                    cabinLight.enabled = !cabinLight.enabled;
                    critters?.SetLightsOff(!cabinLight.enabled);
                }
                else if (n.StartsWith("Bottle")) critters?.Water(hit.point);
                // 3D 모델(PlushModel·CushionModel)이면 그 물건을 직접 건넨다. 도형이면 작은 복사본을 던진다
                else if (n.StartsWith("Plush")) critters?.Toy(Toys.Kind.Plush, hit.point, n.EndsWith("Model") ? hit.collider.transform : null);
                else if (n.StartsWith("Cushion")) critters?.Toy(Toys.Kind.Cushion, hit.point, n.EndsWith("Model") ? hit.collider.transform : null);
                return;
            }
            if (hit.collider.name.StartsWith("Glass_")) world?.TapGlass(hit.point);
        }
    }
}
