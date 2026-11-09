using System.Collections.Generic;
using Allo.Bridge;
using Allo.Critters;
using UnityEngine;

namespace Allo.World
{
    /// 창밖에 가끔 나타나는 친구(모은 종). 길가에 서서 차가 지나가길 기다리고, 아이가 "봤어!" 를 누르면 폴짝 뛰며 반짝인다.
    /// 판정은 하지 않는다. 발견을 Flutter 에 spotted 로 알리기만 한다 (lookOut 횟수는 Flutter 가 센다).
    public sealed class Passerby : MonoBehaviour
    {
        public string id;
        public bool spotted;
        public float z;          // 차 기준 앞(+) 거리 m
        public Transform body;
        public float hop;        // 폴짝 남은 시간
        public float t;
    }

    public sealed class Passersby : MonoBehaviour
    {
        const float Height = 1.3f;

        Transform _root;
        Material _mat;
        readonly List<CastMember> _friends = new();
        readonly Dictionary<string, Texture2D> _tex = new();
        readonly List<Passerby> _live = new();
        float _timer = 14;
        int _next;
        System.Random _rng = new(3);

        /// 보이는 거리 안에 있고 아직 안 본 친구. 없으면 null (HUD 가 "봤어!" 버튼을 보인다)
        public Passerby Spottable { get; private set; }

        public void Init(Transform root, Material spriteMat)
        {
            _root = root;
            _mat = spriteMat;
        }

        void OnEnable() => FlutterBridge.CastChanged += OnCast;
        void OnDisable() => FlutterBridge.CastChanged -= OnCast;

        void Start()
        {
            if (FlutterBridge.LastCast != null) OnCast(FlutterBridge.LastCast);
        }

        void OnCast(CastState c)
        {
            _friends.Clear();
            if (c?.friends == null) return;
            var seed = 100;
            foreach (var f in c.friends)
            {
                if (f == null || string.IsNullOrEmpty(f.id)) continue;
                _friends.Add(f);
                if (!_tex.ContainsKey(f.id))
                {
                    _tex[f.id] = PlaceholderFace.Make(f.attribute, seed++);
                    var id = f.id;
                    StartCoroutine(SpriteLoader.Load(f.sprite, tex =>
                    {
                        _tex[id] = tex;
                        foreach (var p in _live) if (p.id == id && p.body != null) p.body.GetComponent<Renderer>().sharedMaterial.mainTexture = tex;
                    }));
                }
            }
        }

        /// 매 프레임. meters 는 이번 프레임에 차가 간 거리
        public void Tick(float meters, SceneState s, Camera cam)
        {
            var dt = Time.deltaTime;
            _timer -= dt;
            var ok = _friends.Count > 0 && s.kind != "tunnel" && s.moving;
            if (_timer <= 0 && ok)
            {
                _timer = 18 + (float)_rng.NextDouble() * 18;
                Spawn(s);
            }
            Spottable = null;
            for (var i = _live.Count - 1; i >= 0; i--)
            {
                var p = _live[i];
                p.z -= meters;
                p.t += dt;
                if (p.z < -30 || s.kind == "tunnel")
                {
                    Destroy(p.gameObject);
                    _live.RemoveAt(i);
                    continue;
                }
                var lp = p.transform.localPosition;
                p.transform.localPosition = new Vector3(lp.x, lp.y, p.z);
                // 서서 손 흔들듯 좌우로 살짝, 발견되면 폴짝
                var sway = Mathf.Sin(p.t * 2.2f) * 4f;
                var lift = 0f;
                var sy = 1f;
                if (p.hop > 0)
                {
                    p.hop -= dt;
                    var k = 1 - Mathf.Clamp01(p.hop / 0.5f);
                    lift = Mathf.Sin(k * Mathf.PI) * 0.45f;
                    sy = k < 0.2f ? 0.85f : 1.1f;
                }
                if (p.body != null && cam != null)
                {
                    var world = p.transform.position + Vector3.up * (Height * sy / 2 + lift);
                    p.body.position = world;
                    var fwd = world - cam.transform.position;
                    fwd.y = 0;
                    if (fwd.sqrMagnitude > 1e-4f) p.body.rotation = Quaternion.LookRotation(fwd) * Quaternion.Euler(0, 0, sway);
                    p.body.localScale = new Vector3(Height * (2 - sy), Height * sy, 1);
                }
                // 앞 3~45m 사이, 카메라가 그쪽을 보고 있으면 발견 가능
                if (!p.spotted && p.z > 3 && p.z < 45 && cam != null)
                {
                    var dir = p.transform.position - cam.transform.position;
                    if (Vector3.Dot(cam.transform.forward, dir.normalized) > 0.35f && Spottable == null) Spottable = p;
                }
            }
        }

        void Spawn(SceneState s)
        {
            var f = _friends[_next++ % _friends.Count];
            var go = new GameObject($"Passerby_{f.id}");
            go.transform.SetParent(_root, false);
            var p = go.AddComponent<Passerby>();
            p.id = f.id;
            p.z = 110;
            // 오른쪽 길가(인도·모래밭)에 선다. 고속도로는 방음벽 너머 멀리
            var x = s.highway ? 7.5f : s.kind == "city" ? 4.6f : s.kind == "coast" ? 5.5f : 4.2f;
            go.transform.localPosition = new Vector3(x + (float)_rng.NextDouble() * 1.5f, 0, p.z);
            var body = GameObject.CreatePrimitive(PrimitiveType.Quad).transform;
            Destroy(body.GetComponent<Collider>());
            body.name = "Body";
            body.SetParent(go.transform, false);
            var r = body.GetComponent<Renderer>();
            r.sharedMaterial = new Material(_mat) { mainTexture = _tex.TryGetValue(f.id, out var t) ? t : PlaceholderFace.Make(f.attribute, 7) };
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            p.body = body;
            var col = go.AddComponent<BoxCollider>();
            col.center = Vector3.up * Height * 0.5f;
            col.size = new Vector3(Height * 1.2f, Height * 1.2f, Height * 1.2f);
            _live.Add(p);
        }

        /// "봤어!" — 친구가 폴짝 뛰며 반짝이고 Flutter 에 알린다. 이미 본 친구면 아무 일도 없다
        public bool Spot(Passerby p)
        {
            if (p == null || p.spotted) return false;
            p.spotted = true;
            p.hop = 0.5f;
            Fx.Burst(p.transform.position + Vector3.up * Height * 1.1f, Fx.Spark, _mat, 7, 0.35f, 0.5f);
            FlutterBridge.Send("spotted", FlutterBridge.Field("id", p.id));
            if (Spottable == p) Spottable = null;
            return true;
        }
    }
}
