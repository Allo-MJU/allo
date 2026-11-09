using Allo.Bridge;
using UnityEngine;

namespace Allo.CameraRig
{
    /// 손가락으로 차 안을 둘러보는 카메라.
    /// - 한 손가락 드래그: 장면을 손으로 잡아 끄는 방향. 왼쪽으로 끌면 오른쪽을, 위로 끌면 아래를 본다
    ///   (화면 너비 = 180도)
    /// - 두 손가락 핀치: 뒷좌석 ↔ 앞좌석 사이 레일
    /// - 자이로(설정): 손가락 조작에 조금 더한다
    /// - 손을 떼면 0.3초 동안 관성으로 부드럽게 멈춘다
    /// 에디터에서는 마우스 드래그·스크롤로 같은 동작을 한다.
    [RequireComponent(typeof(Camera))]
    public sealed class CameraRig : MonoBehaviour
    {
        [Tooltip("뒷좌석 아이 눈 위치")] public Transform rearAnchor;
        [Tooltip("앞좌석 사이 위치")] public Transform frontAnchor;
        [Tooltip("처음에 바라볼 곳 (대시보드)")] public Transform lookTarget;

        LookState _state;
        Vector2 _velocity;   // 도/초, 관성용
        float _baseYaw;      // 앞(대시보드)을 0도로 본다
        bool _gyro = true;
        float? _lastPinch;

        void OnEnable() => FlutterBridge.SettingsChanged += OnSettings;
        void OnDisable() => FlutterBridge.SettingsChanged -= OnSettings;

        void OnSettings(SettingsState s) => _gyro = s.gyro && !s.reducedMotion;

        void Start()
        {
            if (FlutterBridge.LastSettings != null) OnSettings(FlutterBridge.LastSettings);
            if (lookTarget != null && rearAnchor != null)
            {
                var dir = lookTarget.position - rearAnchor.position;
                _baseYaw = Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg;
            }
            if (SystemInfo.supportsGyroscope) Input.gyro.enabled = true;
            Apply();
        }

        void Update()
        {
            var degPerPixel = 180f / Mathf.Max(1, Screen.width);
            var dragging = false;
            if (Input.touchCount == 1 && Input.GetTouch(0).phase == TouchPhase.Moved)
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
            if (Input.GetMouseButton(0))
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
            if (_gyro && SystemInfo.supportsGyroscope)
            {
                var g = Input.gyro.rotationRateUnbiased * Mathf.Rad2Deg * Time.deltaTime;
                _state = LookMath.AddGyro(_state, new Vector2(-g.y, g.x), true);
            }
            Apply();
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
