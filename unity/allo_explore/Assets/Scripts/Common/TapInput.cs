using Allo.Critters;
using Allo.World;
using UnityEngine;
using UnityEngine.EventSystems;

namespace Allo
{
    /// 짧게 탭하면 (끌지 않고 0.4초 안에 떼면) 그 자리의 물체에 반응한다.
    /// - 캐릭터: 폴짝 + 하트, 동행이면 Flutter 에 tap (놀아주기)
    /// - 창밖 친구: 발견 ("봤어!" 버튼과 같다)
    /// - 머리받침·쿠션·인형·물병·손잡이: 흔들림. 천장등: 실내등 켜고 끄기
    /// - 유리창: 비 오면 빗방울이 튀고, 아니면 반짝
    /// 둘러보기 드래그(CameraRig)와 UI 버튼은 건드리지 않는다.
    [RequireComponent(typeof(Camera))]
    public sealed class TapInput : MonoBehaviour
    {
        public CritterDirector critters;
        public WorldDirector world;
        public Light cabinLight;

        Camera _cam;
        Vector2 _down;
        float _downTime;
        bool _tracking, _overUi;

        void Awake() => _cam = GetComponent<Camera>();

        void Update()
        {
#if UNITY_EDITOR
            if (Input.GetMouseButtonDown(0)) Begin(Input.mousePosition, -1);
            if (Input.GetMouseButtonUp(0)) End(Input.mousePosition);
#endif
            if (Input.touchCount == 1)
            {
                var t = Input.GetTouch(0);
                if (t.phase == TouchPhase.Began) Begin(t.position, t.fingerId);
                else if (t.phase == TouchPhase.Ended) End(t.position);
                else if (t.phase == TouchPhase.Canceled) _tracking = false;
            }
            else if (Input.touchCount > 1) _tracking = false;
        }

        void Begin(Vector2 p, int finger)
        {
            _tracking = true;
            _down = p;
            _downTime = Time.unscaledTime;
            _overUi = EventSystem.current != null && EventSystem.current.IsPointerOverGameObject(finger);
        }

        void End(Vector2 p)
        {
            if (!_tracking) return;
            _tracking = false;
            if (_overUi) return;
            if ((p - _down).magnitude > Screen.height * 0.03f || Time.unscaledTime - _downTime > 0.4f) return;
            Tap(p);
        }

        void Tap(Vector2 screen)
        {
            if (!Physics.Raycast(_cam.ScreenPointToRay(screen), out var hit, 80f)) return;
            var critter = hit.collider.GetComponentInParent<CritterView>();
            if (critter != null) { critters?.Poke(critter); return; }
            var friend = hit.collider.GetComponentInParent<Passerby>();
            if (friend != null) { world?.Spot(friend); return; }
            var wobble = hit.collider.GetComponentInParent<Wobble>();
            if (wobble != null)
            {
                wobble.Punch();
                if (hit.collider.name.StartsWith("DomeLight") && cabinLight != null) cabinLight.enabled = !cabinLight.enabled;
                else if (hit.collider.name.StartsWith("Plush") || hit.collider.name.StartsWith("Cushion"))
                    Fx.Burst(hit.point + Vector3.up * 0.05f, Fx.Heart, critters != null ? critters.critterMaterial : null, 2, 0.05f, 0.04f);
                return;
            }
            if (hit.collider.name.StartsWith("Glass_")) world?.TapGlass(hit.point);
        }
    }
}
