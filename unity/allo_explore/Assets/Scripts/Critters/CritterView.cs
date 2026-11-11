using UnityEngine;

namespace Allo.Critters
{
    /// 캐릭터 한 마리를 그린다: 카메라를 향한 2D 그림(빌보드) + 발밑 그림자.
    /// 걸을 땐 통통 튀고, 점프는 포물선, 구르기는 빙글, 잘 땐 숨 쉬듯 부풀었다 줄어든다.
    /// D 의 포즈 그림이 있으면 행동에 맞춰 바꾼다: 걷기·점프 move, 자기·웅크리기 sleep, 탭·먹이 뒤 잠깐 happy, 그 밖 idle.
    /// 3D 모델(CharacterModel)이 있으면 그림 대신 모델을 세운다: 가는 쪽을 보고 걷고, 서 있을 땐 아이 쪽을 본다.
    public sealed class CritterView : MonoBehaviour
    {
        public const float Height = 0.28f; // 미터. 큰 봉제 인형 정도
        const float NearLimit = 0.6f;     // 2D 그림을 카메라 쪽으로 당길 때 넘지 않는 거리 (m, 수평)

        CritterBrain _brain;
        Transform _body;
        Transform _shadow;
        Renderer _bodyRenderer;
        BoxCollider _col;
        float _t;
        float _facing = -1; // 움직이는 방향 (카메라 기준 오른쪽 +1). 처음엔 왼쪽
        float _cheer;       // happy 포즈 남은 시간
        Vector3 _last;
        CritterArt _art;
        ArtPose _shown = (ArtPose)(-1);
        CharacterModel _model; // 있으면 3D, 없으면 2D 그림
        float _yaw;            // 3D 모델이 보는 방향 (도)

        public bool Is3D => _model != null;

        public string Id { get; private set; }
        public CritterBrain Brain => _brain;

        public void Init(string id, CritterBrain brain, CritterArt art, Material baseMat, Material shadowMat, GameObject model = null)
        {
            Id = id;
            _brain = brain;
            if (model != null)
            {
                // 몸 가운데를 축으로 찌그러지고 구르도록 빈 축 아래에 모델을 발이 축보다 Height/2 아래 오게 둔다
                _body = new GameObject("Body").transform;
                _body.SetParent(transform, false);
                _model = CharacterModel.Spawn(model, _body, Height);
                _model.transform.localPosition = Vector3.down * Height / 2;
                _art = art;
            }
            else
            {
                _body = GameObject.CreatePrimitive(PrimitiveType.Quad).transform;
                _body.name = "Body";
                Kill(_body.GetComponent<Collider>());
                _body.SetParent(transform, false);
                _bodyRenderer = _body.GetComponent<Renderer>();
                _bodyRenderer.sharedMaterial = new Material(baseMat);
                SetArt(art);
                _bodyRenderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            }
            _shadow = GameObject.CreatePrimitive(PrimitiveType.Quad).transform;
            _shadow.name = "Shadow";
            Kill(_shadow.GetComponent<Collider>());
            _shadow.SetParent(transform, false);
            _shadow.localRotation = Quaternion.Euler(90, 0, 0);
            _shadow.GetComponent<Renderer>().sharedMaterial = shadowMat;
            _last = brain.Position;
            // 탭으로 고를 수 있게 몸 크기만 한 상자
            var col = _col = gameObject.AddComponent<BoxCollider>();
            col.center = Vector3.up * Height * 0.5f;
            col.size = Vector3.one * Height * 1.3f;
            if (_model != null)
            {
                var f = _model.footprint * _model.Scale;
                col.size = new Vector3(Mathf.Max(f.x, f.y), Height, Mathf.Max(f.x, f.y)) * 1.2f;
            }
            _yaw = Random.Range(0f, 360f);
        }

        /// 머리 위 (하트·음표가 뜨는 자리)
        public Vector3 Top => transform.position + Vector3.up * (Height * 1.05f);

        static void Kill(Object o)
        {
            if (Application.isPlaying) Destroy(o);
            else DestroyImmediate(o);
        }

        public void SetArt(CritterArt art)
        {
            _art = art;
            if (_model != null) return;
            _shown = (ArtPose)(-1);
            Show(ArtPose.Idle);
        }

        /// 잠깐 기뻐하는 얼굴 (탭·먹이)
        public void Cheer(float seconds = 1.4f) => _cheer = Mathf.Max(_cheer, seconds);

        public ArtPose Shown => _shown;

        void Show(ArtPose p)
        {
            if (_model != null || _art == null || p == _shown) return;
            _shown = p;
            _bodyRenderer.sharedMaterial.mainTexture = _art[p];
        }

        ArtPose PoseFor(CritterState s)
        {
            if (_cheer > 0 && s != CritterState.Sleep) return ArtPose.Happy;
            switch (s)
            {
                case CritterState.Walk:
                case CritterState.Jump: return ArtPose.Move;
                case CritterState.Tumble: return ArtPose.Happy;
                case CritterState.Sleep:
                case CritterState.Huddle: return ArtPose.Sleep;
                default: return ArtPose.Idle;
            }
        }

        void LateUpdate() => Pose(Camera.main, Time.deltaTime);

        /// 현재 행동에 맞게 위치·모양을 잡는다. 에디터 캡처에서도 직접 부른다.
        public void Pose(Camera cam, float dt)
        {
            if (_brain == null) return;
            _t += dt;
            _cheer -= dt;
            Show(PoseFor(_brain.State));
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
                    lift = Mathf.Sin(k * Mathf.PI) * (0.18f + _brain.JumpBoost + Mathf.Max(0, _brain.Target.y - _brain.JumpFrom.y));
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
            if (_model != null)
            {
                Pose3D(cam, dt, p, move, lift, sx, sy, roll);
                return;
            }
            if (cam != null && move.sqrMagnitude > 1e-6f)
            {
                var side = Vector3.Dot(move, cam.transform.right);
                if (Mathf.Abs(side) > 1e-4f) _facing = Mathf.Sign(side);
            }
            _last = p;
            transform.position = p;
            _body.position = p + Vector3.up * (lift + Height * sy / 2);
            // 납작한 그림이 뒤쪽 의자·머리받침에 파묻히지 않게 카메라 쪽으로 몸 반 너비만큼 당긴다.
            // 아이 바로 옆 자리처럼 이미 가까우면 더 크게 보이기만 하므로 눈에서 NearLimit 안으로는 당기지 않는다
            if (cam != null)
            {
                var toCam = cam.transform.position - _body.position;
                toCam.y = 0;
                var pull = Mathf.Clamp(toCam.magnitude - NearLimit, 0, Height * 0.5f);
                if (toCam.sqrMagnitude > 1e-6f) _body.position += toCam.normalized * pull;
            }
            if (cam != null)
            {
                var fwd = _body.position - cam.transform.position;
                fwd.y = 0;
                if (fwd.sqrMagnitude > 1e-6f) _body.rotation = Quaternion.LookRotation(fwd) * Quaternion.Euler(0, 0, roll);
            }
            // 그림이 왼쪽을 보면 오른쪽으로 갈 때 뒤집는다 (Allo/Sprite 는 뒷면도 그린다)
            var aspect = _art?.Aspect ?? 1;
            var flip = _art != null && _art.FacesLeft ? -_facing : _facing;
            _body.localScale = new Vector3(Height * aspect * sx * flip, Height * sy, 1);
            // 탭·쓰다듬기 상자를 보이는 그림에 맞춘다 (그림은 카메라 쪽으로 당겨지고 날개가 넓다)
            if (_col != null)
            {
                _col.center = transform.InverseTransformPoint(_body.position);
                var w = Height * Mathf.Max(1, aspect) * 1.1f; // 루트는 돌지 않으므로 어느 쪽에서 봐도 덮이게 x·z 같게
                _col.size = new Vector3(w, Height * 1.2f, w);
            }
            var shrink = 1 - Mathf.Clamp01(lift / 0.4f) * 0.5f;
            _shadow.position = p + Vector3.up * 0.003f;
            _shadow.localScale = new Vector3(Height * Mathf.Min(aspect, 1.3f) * 0.8f * shrink, Height * 0.45f * shrink, 1);
        }

        /// 3D 모델: 가는 쪽을 보고 걷고(앞으로 살짝 숙이고 뒤뚱), 서 있거나 기쁠 땐 아이 쪽을, 창 밖을 볼 땐 창 쪽을 본다.
        /// 점프는 오를 때 뒤로·내릴 때 앞으로 기울고, 구르기는 앞으로 두 바퀴, 잘 땐 고개를 숙이고 숨 쉰다.
        void Pose3D(Camera cam, float dt, Vector3 p, Vector3 move, float lift, float sx, float sy, float roll)
        {
            _last = p;
            var state = _brain.State;
            var toCam = cam != null ? cam.transform.position - p : Vector3.back;
            toCam.y = 0;
            float? want = null;
            if (move.sqrMagnitude > 1e-7f && (state == CritterState.Walk || state == CritterState.Jump))
                want = Mathf.Atan2(move.x, move.z) * Mathf.Rad2Deg;
            else if (state == CritterState.Peek && toCam.sqrMagnitude > 1e-6f)
                want = Mathf.Atan2(-toCam.x, -toCam.z) * Mathf.Rad2Deg; // 아이 반대쪽(창)
            else if ((state == CritterState.Idle || _cheer > 0) && toCam.sqrMagnitude > 1e-6f)
                want = Mathf.Atan2(toCam.x, toCam.z) * Mathf.Rad2Deg;
            if (want.HasValue) _yaw = Mathf.MoveTowardsAngle(_yaw, want.Value, (state == CritterState.Idle ? 160 : 420) * dt);

            var pitch = 0f;
            var bank = 0f;
            switch (state)
            {
                case CritterState.Walk:
                    pitch = 7;
                    bank = Mathf.Sin(_t * 12) * 6;
                    break;
                case CritterState.Jump:
                    pitch = Mathf.Lerp(-12, 14, _brain.Progress);
                    break;
                case CritterState.Tumble:
                    pitch = roll; // 앞으로 두 바퀴
                    break;
                case CritterState.Sleep:
                    pitch = 14;
                    break;
                case CritterState.Huddle:
                    pitch = 6;
                    break;
            }
            if (_cheer > 0) bank = Mathf.Sin(_t * 18) * 9;

            transform.position = p;
            _body.position = p + Vector3.up * (lift + Height * sy / 2);
            _body.rotation = Quaternion.Euler(0, _yaw, 0) * Quaternion.Euler(pitch, 0, bank);
            _body.localScale = new Vector3(sx, sy, sx);
            var f = _model.footprint * _model.Scale;
            var shrink = 1 - Mathf.Clamp01(lift / 0.4f) * 0.5f;
            _shadow.position = p + Vector3.up * 0.003f;
            _shadow.rotation = Quaternion.Euler(90, _yaw, 0);
            _shadow.localScale = new Vector3(f.x * 1.05f * shrink, f.y * 1.05f * shrink, 1);
        }
    }
}
