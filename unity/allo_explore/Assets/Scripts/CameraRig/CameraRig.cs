using Allo.App;
using Allo.Bridge;
using UnityEngine;

namespace Allo.CameraRig
{
    /// 기기를 돌려 차 안을 둘러보는 카메라. 입장할 때 기기를 든 방향이 정면이다.
    /// - 자이로가 꺼졌거나 센서값이 없으면 한 손가락 드래그로 둘러본다.
    ///   (화면 너비 = 180도)
    /// - 두 손가락 핀치: 뒷좌석 ↔ 앞좌석 사이 레일
    /// - 손을 떼면 0.3초 동안 관성으로 부드럽게 멈춘다
    /// 에디터에서는 마우스 드래그·스크롤로 같은 동작을 한다.
    [RequireComponent(typeof(Camera))]
    public sealed partial class CameraRig : MonoBehaviour
    {
        [Tooltip("뒷좌석 아이 눈 위치")] public Transform rearAnchor;
        [Tooltip("앞좌석 사이 위치")] public Transform frontAnchor;
        [Tooltip("처음에 바라볼 곳 (대시보드)")] public Transform lookTarget;

        LookState _state;
        Vector2 _velocity;   // 도/초, 관성용
        float _baseYaw;      // 앞(대시보드)을 0도로 본다
        bool _gyro = true;
        Quaternion? _neutral;
        LookState? _gyroAtGlance;
        ScreenOrientation _orientation;
        AppUi _ui;
        bool _paused, _unfocused;
        float? _lastPinch;

        void OnEnable()
        {
            _paused = _unfocused = false;
            FlutterBridge.SettingsChanged += OnSettings;
            if (FlutterBridge.LastSettings != null) OnSettings(FlutterBridge.LastSettings);
            SetSensorEnabled(_gyro);
            if (!CabinInteraction.IsCapturing)
            {
                ResetGyroReference();
                _glanceAt = null;
                _rideTo = _rideRestore = null;
                _introWanted = true;
            }
        }

        void OnDisable()
        {
            FlutterBridge.SettingsChanged -= OnSettings;
            _velocity = Vector2.zero;
            _lastPinch = null;
            if (!CabinInteraction.IsCapturing || AppSession.State?.view != "cabin") SetSensorEnabled(false);
            if (_intro) { EndIntro(); Apply(); }
        }

        static void SetSensorEnabled(bool enabled)
        {
            if (!SystemInfo.supportsGyroscope) return;
            if (enabled) Input.compensateSensors = true; // Unity 보정으로 양쪽 가로 화면의 축을 맞춘다.
            if (Input.gyro.enabled != enabled) Input.gyro.enabled = enabled;
        }

        void OnSettings(SettingsState s)
        {
            var enabled = s.gyro && !s.reducedMotion;
            if (_gyro == enabled) return;
            _gyro = enabled;
            ResetGyroReference();
            _velocity = Vector2.zero;
            SetSensorEnabled(enabled);
        }

        void ResetGyroReference()
        {
            _neutral = null;
            _gyroAtGlance = null;
        }

        void OnApplicationPause(bool paused) { _paused = paused; ResetGyroReference(); }
        void OnApplicationFocus(bool focused) { _unfocused = !focused; ResetGyroReference(); }

        void Start()
        {
            if (lookTarget != null && rearAnchor != null)
            {
                var dir = lookTarget.position - rearAnchor.position;
                _baseYaw = Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg;
            }
            Apply();
        }

        bool _uiTouch; // 버튼 위에서 시작한 터치는 둘러보기로 치지 않는다

        /// 쓰다듬기·던지기·유리 그림처럼 손가락이 다른 일을 하는 동안 둘러보기를 멈춘다 (TapInput 이 켠다)
        public static bool Locked;
        internal bool EggOwnsPointer { get; set; }

        /// 현재 자세를 새 정면으로 삼는다. 센서가 없어도 같은 자리에서 대시보드를 바라본다.
        public static void Recenter()
        {
            if (_instance == null) return;
            _instance.ResetGyroReference();
            _instance._state.yaw = _instance._state.pitch = 0;
            _instance._velocity = Vector2.zero;
            _instance._glanceAt = null;
            _instance._rideTo = _instance._rideRestore = null;
        }

        bool TryGyroTarget(out LookState target)
        {
            target = _state;
            if (!_gyro || !SystemInfo.supportsGyroscope || !Input.gyro.enabled) return false;
            var orientation = Screen.orientation;
            if (_orientation != orientation) { _orientation = orientation; ResetGyroReference(); }
            if (!LookMath.TryAttitude(Input.gyro.attitude, out var current)) return false;
            if (!_neutral.HasValue)
            {
                // 센서가 깨어나기 전에 Unity가 돌려주는 기본 자세는 정면으로 저장하지 않는다.
                if (Mathf.Abs(current.w) > .999999f && !(Input.gyro.gravity.sqrMagnitude >= .01f)) return false;
                _neutral = current;
            }
            target = LookMath.GyroTarget(_state, _neutral.Value, current);
            return true;
        }

        void Update()
        {
            if (_paused || _unfocused) return;
            if (!EggOwnsPointer && IntroTick()) return;
            if (_ui == null && AppSession.State != null) _ui = FindFirstObjectByType<AppUi>();
            if (EggOwnsPointer || CabinInteraction.IsCapturing || AppSession.StoryActive || StoryOverlay.CapturingInput ||
                (_ui != null && _ui.CabinGesturesBlocked))
            {
                _velocity = Vector2.zero;
                _lastPinch = null;
                _uiTouch = false;
                return;
            }
            var degPerPixel = 180f / Mathf.Max(1, Screen.width);
            var dragging = false;
            var gyroActive = TryGyroTarget(out var gyroTarget);
            if (gyroActive) _velocity = Vector2.zero;
            if (Input.touchCount == 1 && Input.GetTouch(0).phase == TouchPhase.Began)
                _uiTouch = UnityEngine.EventSystems.EventSystem.current != null &&
                           UnityEngine.EventSystems.EventSystem.current.IsPointerOverGameObject(Input.GetTouch(0).fingerId);
            if (Input.touchCount == 0) _uiTouch = false;
            if (!gyroActive && !_uiTouch && !Locked && Input.touchCount == 1 && Input.GetTouch(0).phase == TouchPhase.Moved)
            {
                var d = Input.GetTouch(0).deltaPosition * degPerPixel;
                Turn(new Vector2(-d.x, -d.y));
                dragging = true;
            }
            else if (Input.touchCount == 2)
            {
                var dist = Vector2.Distance(Input.GetTouch(0).position, Input.GetTouch(1).position);
                if (_lastPinch.HasValue)
                    _state = LookMath.Pinch(_state, (dist - _lastPinch.Value) / Mathf.Max(1, Screen.height));
                _lastPinch = dist;
                dragging = true;
            }
#if UNITY_EDITOR
            if (!gyroActive && Input.GetMouseButton(0) && !Locked)
            {
                var d = new Vector2(Input.GetAxis("Mouse X"), Input.GetAxis("Mouse Y")) * 6f;
                Turn(new Vector2(-d.x, -d.y));
                dragging = true;
            }
            _state = LookMath.Pinch(_state, Input.mouseScrollDelta.y * 0.05f);
#endif
            if (Input.touchCount < 2) _lastPinch = null;
            if (!dragging && _velocity.sqrMagnitude > 0.01f)
            {
                _state = LookMath.Drag(_state, _velocity * Time.deltaTime);
                _velocity = Vector2.Lerp(_velocity, Vector2.zero, Time.deltaTime / 0.3f);
            }
            if (gyroActive && !Locked && !_uiTouch) dragging = ApplyGyroLook(gyroTarget, dragging);
            GlanceTick(dragging);
            RideTick(dragging);
            Apply();
        }

        bool ApplyGyroLook(LookState target, bool dragging)
        {
            if (_glanceAt.HasValue || _rideRestore.HasValue || _rideTo.HasValue)
            {
                // 부화 연출은 가만히 보면 유지하고, 아이가 폰을 돌리면 드래그처럼 제어를 돌려준다.
                _gyroAtGlance ??= target;
                var from = _gyroAtGlance.Value;
                if (!dragging && Mathf.Abs(Mathf.DeltaAngle(from.yaw, target.yaw)) <= 5f &&
                    Mathf.Abs(from.pitch - target.pitch) <= 5f) return false;
                dragging = true;
            }
            else _gyroAtGlance = null;

            target.rail = _state.rail;
            var weight = 1f - Mathf.Exp(-12f * Mathf.Min(Time.unscaledDeltaTime, .05f));
            _state = LookMath.Blend(_state, target, weight);
            return dragging;
        }

        static CameraRig _instance;
        Vector3? _glanceAt;
        float _glanceT;
        LookState _glanceFrom;

        void Awake() => _instance = this;

        /// 그 점 쪽으로 천천히 고개를 돌린다 (알이 깨어날 때). 아이가 손가락으로 둘러보면 바로 멈춘다
        public static void Glance(Vector3 point)
        {
            if (_instance == null) return;
            _instance._glanceAt = point;
            _instance._glanceT = 0;
            _instance._glanceFrom = _instance._state;
            _instance._velocity = Vector2.zero;
        }

        float? _rideTo, _rideRestore;
        float _rideFrom, _rideT, _rideSeconds = 1f;

        /// 레일을 rail(0 뒷좌석 ~ 1 앞좌석)까지 seconds 동안 부드럽게 민다 (알이 깨어날 때 둥지 가까이). 아이가 손대면 멈춘다
        public static void Ride(float rail, float seconds)
        {
            if (_instance == null) return;
            var i = _instance;
            i._rideRestore ??= i._state.rail;
            i._rideFrom = i._state.rail; i._rideTo = Mathf.Clamp01(rail); i._rideT = 0; i._rideSeconds = Mathf.Max(0.1f, seconds);
        }

        /// Ride 전 자리로 되돌아간다
        public static void RideBack(float seconds)
        {
            if (_instance == null || _instance._rideRestore == null) return;
            var back = _instance._rideRestore.Value;
            Ride(back, seconds);
            _instance._rideRestore = null;
        }

        void RideTick(bool dragging)
        {
            if (dragging) { _rideTo = null; _rideRestore = null; return; }
            if (_rideTo == null) return;
            _rideT += Time.deltaTime / _rideSeconds;
            _state.rail = Mathf.Lerp(_rideFrom, _rideTo.Value, Mathf.SmoothStep(0, 1, _rideT));
            if (_rideT >= 1) _rideTo = null;
        }

        void GlanceTick(bool dragging)
        {
            if (_glanceAt == null) return;
            if (dragging) { _glanceAt = null; return; }
            _glanceT += Time.deltaTime / 0.9f;
            var to = LookMath.Toward(_glanceFrom, transform.position, _glanceAt.Value, _baseYaw);
            var look = LookMath.Blend(_glanceFrom, to, Mathf.SmoothStep(0, 1, _glanceT));
            _state.yaw = look.yaw;
            _state.pitch = look.pitch;
            if (_glanceT >= 1) _glanceAt = null;
        }

        void Turn(Vector2 deg)
        {
            _state = LookMath.Drag(_state, deg);
            _velocity = deg / Mathf.Max(Time.deltaTime, 1e-3f);
        }

        void Apply()
        {
            if (rearAnchor != null && frontAnchor != null)
                transform.position = LookMath.RailPosition(_state.rail, rearAnchor.position, frontAnchor.position);
            transform.rotation = Quaternion.Euler(-_state.pitch, _baseYaw + _state.yaw, 0);
        }
    }
}
