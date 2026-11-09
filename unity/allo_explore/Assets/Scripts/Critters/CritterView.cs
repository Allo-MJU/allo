using UnityEngine;

namespace Allo.Critters
{
    /// 캐릭터 한 마리를 그린다: 카메라를 향한 2D 그림(빌보드) + 발밑 그림자.
    /// 걸을 땐 통통 튀고, 점프는 포물선, 구르기는 빙글, 잘 땐 숨 쉬듯 부풀었다 줄어든다.
    public sealed class CritterView : MonoBehaviour
    {
        public const float Height = 0.28f; // 미터. 큰 봉제 인형 정도

        CritterBrain _brain;
        Transform _body;
        Transform _shadow;
        Renderer _bodyRenderer;
        float _t;
        float _facing = 1;
        Vector3 _last;

        public string Id { get; private set; }
        public CritterBrain Brain => _brain;

        public void Init(string id, CritterBrain brain, Texture2D tex, Material baseMat, Material shadowMat)
        {
            Id = id;
            _brain = brain;
            _body = GameObject.CreatePrimitive(PrimitiveType.Quad).transform;
            _body.name = "Body";
            Kill(_body.GetComponent<Collider>());
            _body.SetParent(transform, false);
            _bodyRenderer = _body.GetComponent<Renderer>();
            _bodyRenderer.sharedMaterial = new Material(baseMat) { mainTexture = tex };
            _bodyRenderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            _shadow = GameObject.CreatePrimitive(PrimitiveType.Quad).transform;
            _shadow.name = "Shadow";
            Kill(_shadow.GetComponent<Collider>());
            _shadow.SetParent(transform, false);
            _shadow.localRotation = Quaternion.Euler(90, 0, 0);
            _shadow.GetComponent<Renderer>().sharedMaterial = shadowMat;
            _last = brain.Position;
        }

        static void Kill(Object o)
        {
            if (Application.isPlaying) Destroy(o);
            else DestroyImmediate(o);
        }

        public void SetTexture(Texture2D tex) => _bodyRenderer.sharedMaterial.mainTexture = tex;

        void LateUpdate() => Pose(Camera.main, Time.deltaTime);

        /// 현재 행동에 맞게 위치·모양을 잡는다. 에디터 캡처에서도 직접 부른다.
        public void Pose(Camera cam, float dt)
        {
            if (_brain == null) return;
            _t += dt;
            var p = _brain.Position;
            var lift = 0f;
            var sx = 1f; var sy = 1f; var roll = 0f;
            switch (_brain.State)
            {
                case CritterState.Walk:
                    lift = Mathf.Abs(Mathf.Sin(_t * 12)) * 0.025f;
                    sy = 1 + Mathf.Sin(_t * 24) * 0.05f; sx = 2 - sy;
                    break;
                case CritterState.Jump:
                {
                    var k = _brain.Progress;
                    p = Vector3.Lerp(_brain.JumpFrom, _brain.Target, k);
                    lift = Mathf.Sin(k * Mathf.PI) * (0.18f + Mathf.Max(0, _brain.Target.y - _brain.JumpFrom.y));
                    sy = k < 0.15f ? 0.8f : k > 0.85f ? 0.85f : 1.15f; sx = 2 - sy;
                    break;
                }
                case CritterState.Tumble:
                    roll = _brain.Progress * 720;
                    lift = Mathf.Sin(_brain.Progress * Mathf.PI) * 0.05f;
                    break;
                case CritterState.Sleep:
                    sy = 0.9f + Mathf.Sin(_t * 1.6f) * 0.04f; sx = 1.12f;
                    break;
                case CritterState.Huddle:
                    sy = 0.85f; sx = 1.1f;
                    break;
                case CritterState.Peek:
                    lift = Mathf.Abs(Mathf.Sin(_t * 3)) * 0.01f;
                    break;
                default:
                    sy = 1 + Mathf.Sin(_t * 2.5f) * 0.025f; sx = 2 - sy;
                    break;
            }
            var move = p - _last;
            if (cam != null && move.sqrMagnitude > 1e-6f)
            {
                var side = Vector3.Dot(move, cam.transform.right);
                if (Mathf.Abs(side) > 1e-4f) _facing = Mathf.Sign(side);
            }
            _last = p;
            transform.position = p;
            _body.position = p + Vector3.up * (lift + Height * sy / 2);
            if (cam != null)
            {
                var fwd = _body.position - cam.transform.position;
                fwd.y = 0;
                if (fwd.sqrMagnitude > 1e-6f) _body.rotation = Quaternion.LookRotation(fwd) * Quaternion.Euler(0, 0, roll);
            }
            _body.localScale = new Vector3(Height * sx * _facing, Height * sy, 1);
            var shrink = 1 - Mathf.Clamp01(lift / 0.4f) * 0.5f;
            _shadow.position = p + Vector3.up * 0.003f;
            _shadow.localScale = new Vector3(Height * 0.9f * shrink, Height * 0.45f * shrink, 1);
        }
    }
}
