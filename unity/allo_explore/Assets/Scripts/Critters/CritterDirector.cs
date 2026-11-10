using System.Collections;
using System.Collections.Generic;
using Allo.Bridge;
using UnityEngine;

namespace Allo.Critters
{
    /// cast 메시지로 캐릭터를 등장·퇴장시키고, scene·jolt 메시지를 분위기·반응으로 넘긴다.
    /// 걷는 면은 차 모델의 Walk_* 판 위치에서 읽는다.
    public sealed class CritterDirector : MonoBehaviour
    {
        public Transform cabin;

        [Tooltip("아이 눈 위치. 이 바로 아래 면(아이가 앉은 자리)에는 캐릭터가 올라가지 않는다")]
        public Transform childEye;
        public Material critterMaterial;
        public Material shadowMaterial;

        /// 장면을 만들 때(에디터) 미리 계산해 둔 걷는 면. 꺼 둔 렌더러의 크기는 앱 빌드에서 0 으로 읽혀서
        /// 실행 중에 계산하지 않는다 (AlloBuild.CreateExploreScene 이 채운다)
        [SerializeField] string[] surfaceNames = new string[0];
        [SerializeField] Vector3[] surfaceCenters = new Vector3[0];
        [SerializeField] Vector2[] surfaceSizes = new Vector2[0];

        public void Bake()
        {
            var names = new List<string>(); var centers = new List<Vector3>(); var sizes = new List<Vector2>();
            foreach (var r in cabin.GetComponentsInChildren<Renderer>(true))
            {
                if (!r.name.StartsWith("Walk_")) continue;
                var b = r.bounds;
                if (childEye != null && TooCloseToChild(r.name, b, childEye.position)) continue;
                names.Add(r.name);
                centers.Add(new Vector3(b.center.x, b.max.y, b.center.z));
                sizes.Add(new Vector2(b.size.x, b.size.z));
            }
            surfaceNames = names.ToArray(); surfaceCenters = centers.ToArray(); surfaceSizes = sizes.ToArray();
        }

        public WalkGraph BuildGraph()
        {
            var list = new List<WalkSurface>();
            for (var i = 0; i < surfaceNames.Length; i++) list.Add(new WalkSurface(surfaceNames[i], surfaceCenters[i], surfaceSizes[i]));
            return new WalkGraph(list);
        }

        WalkGraph _graph;
        readonly Dictionary<string, CritterView> _views = new();
        Mood _mood = new Mood { moving = true };
        int _seed = 1;
        bool _feeding;

        /// 동행 캐릭터 id (cast.companion). 없으면 null
        public string CompanionId { get; private set; }
        public CritterView Companion => CompanionId != null && _views.TryGetValue(CompanionId, out var v) ? v : null;

        /// 탭: 폴짝 + 하트. 동행 캐릭터면 Flutter 에 tap 을 알린다 (놀아주기 횟수는 Flutter 가 센다)
        public void Poke(CritterView v)
        {
            if (v == null) return;
            v.Brain.Poke();
            Fx.Burst(v.Top, Fx.Heart, critterMaterial, 4, 0.06f);
            if (v.Id == CompanionId) FlutterBridge.Send("tap", FlutterBridge.Field("id", v.Id));
        }

        /// 먹이: 동행 캐릭터 옆에 사과를 놓고, 걸어가 먹는다. 동행이 없거나 먹는 중이면 false
        public bool Feed()
        {
            var c = Companion;
            if (c == null || _feeding) return false;
            StartCoroutine(FeedRoutine(c));
            return true;
        }

        IEnumerator FeedRoutine(CritterView c)
        {
            _feeding = true;
            var rng = new System.Random(_seed++ * 31);
            var at = _graph.RandomPoint(c.Brain.Surface, rng);
            var apple = new GameObject("Apple").transform;
            apple.position = at;
            var red = Fruit(apple, new Color(0.9f, 0.25f, 0.2f), 0.065f);
            c.Brain.GoTo(at);
            var waited = 0f;
            while (c != null && !c.Brain.AtTarget && waited < 4f) { waited += Time.deltaTime; yield return null; }
            // 세 입에 먹는다
            for (var bite = 0; bite < 3 && c != null; bite++)
            {
                c.Brain.Poke();
                Fx.Burst(apple.position + Vector3.up * 0.08f, Fx.Heart, critterMaterial, 2, 0.045f, 0.05f);
                red.localScale *= 0.72f;
                yield return new WaitForSeconds(0.45f);
            }
            Destroy(apple.gameObject);
            if (c != null) Fx.Burst(c.Top, Fx.Heart, critterMaterial, 6, 0.07f);
            _feeding = false;
        }

        static Transform Fruit(Transform parent, Color color, float d)
        {
            var body = GameObject.CreatePrimitive(PrimitiveType.Sphere).transform;
            Destroy(body.GetComponent<Collider>());
            body.SetParent(parent, false);
            body.localPosition = Vector3.up * d * 0.5f;
            body.localScale = new Vector3(d, d * 0.92f, d);
            var m = new Material(Shader.Find("Allo/Toon")) { color = color };
            m.SetFloat("_OutlineWidth", 0.003f);
            m.SetFloat("_HiSize", 0.25f);
            body.GetComponent<Renderer>().sharedMaterial = m;
            var stem = GameObject.CreatePrimitive(PrimitiveType.Cylinder).transform;
            Destroy(stem.GetComponent<Collider>());
            stem.SetParent(body, false);
            stem.localPosition = new Vector3(0, 0.5f, 0);
            stem.localScale = new Vector3(0.08f, 0.16f, 0.08f);
            stem.GetComponent<Renderer>().sharedMaterial = new Material(Shader.Find("Allo/Toon")) { color = new Color(0.35f, 0.22f, 0.12f) };
            return body;
        }

        void Awake()
        {
            _graph = BuildGraph();
            Debug.Log($"[Critters] walk surfaces: {_graph.Surfaces.Count}");
        }

        /// 아이가 앉은 자리와 바로 옆 창턱은 캐릭터가 화면을 가리므로 쓰지 않는다
        public static bool TooCloseToChild(string name, Bounds surface, Vector3 eye)
        {
            var p = new Vector3(eye.x, surface.center.y, eye.z);
            if (surface.SqrDistance(p) < 0.2f * 0.2f) return true;
            return name.Contains("DoorSill") && Mathf.Abs(surface.center.x - eye.x) < 0.4f;
        }

        void OnEnable()
        {
            FlutterBridge.CastChanged += OnCast;
            FlutterBridge.SceneChanged += OnScene;
            FlutterBridge.Jolted += OnJolt;
        }

        void OnDisable()
        {
            FlutterBridge.CastChanged -= OnCast;
            FlutterBridge.SceneChanged -= OnScene;
            FlutterBridge.Jolted -= OnJolt;
        }

        void Start()
        {
            if (FlutterBridge.LastScene != null) OnScene(FlutterBridge.LastScene);
            if (FlutterBridge.LastCast != null) OnCast(FlutterBridge.LastCast);
#if UNITY_EDITOR
            // 에디터에서 Flutter 없이 볼 때: 임시 캐릭터 셋
            if (FlutterBridge.LastCast == null)
                OnCast(new CastState
                {
                    companion = new CastMember { id = "editor_a", attribute = "water" },
                    friends = new[] { new CastMember { id = "editor_b", attribute = "normal" }, new CastMember { id = "editor_c", attribute = "dark" } },
                });
#endif
        }

        void Update()
        {
            foreach (var v in _views.Values) v.Brain.Tick(Time.deltaTime, _mood);
        }

        void OnScene(SceneState s) => _mood = new Mood
        {
            night = s.night,
            rain = s.rain > 0,
            tunnel = s.kind == "tunnel",
            moving = s.moving,
        };

        void OnJolt(string kind)
        {
            foreach (var v in _views.Values) v.Brain.Jolt();
        }

        void OnCast(CastState cast)
        {
            if (_graph.Surfaces.Count == 0) return;
            CompanionId = cast.companion != null && !string.IsNullOrEmpty(cast.companion.id) ? cast.companion.id : null;
            var (add, remove) = CastDiff.Compute(_views.Keys, cast);
            foreach (var id in remove)
            {
                Destroy(_views[id].gameObject);
                _views.Remove(id);
            }
            var start = Mathf.Max(0, _graph.IndexOf("Walk_Armrest"));
            foreach (var m in CastDiff.Members(cast))
            {
                if (!add.Contains(m.id)) continue;
                var go = new GameObject($"Critter_{m.id}");
                go.transform.SetParent(transform, false);
                var view = go.AddComponent<CritterView>();
                var seed = _seed++;
                view.Init(m.id, new CritterBrain(_graph, start, seed * 7919), PlaceholderFace.Make(m.attribute, seed),
                    critterMaterial, shadowMaterial);
                _views[m.id] = view;
                if (!string.IsNullOrEmpty(m.sprite)) StartCoroutine(SpriteLoader.Load(m.sprite, tex => { if (view != null) view.SetTexture(tex); }));
            }
        }

    }
}
