using System.Collections;
using System.Collections.Generic;
using Allo.Bridge;
using UnityEngine;
using UnityEngine.Networking;

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
                if (!string.IsNullOrEmpty(m.sprite)) StartCoroutine(LoadSprite(view, m.sprite));
            }
        }

        /// Flutter 에셋은 같은 APK 안 assets/flutter_assets/ 에 있다. D 그림이 있으면 바꿔 끼운다.
        IEnumerator LoadSprite(CritterView view, string sprite)
        {
            var url = $"{Application.streamingAssetsPath}/flutter_assets/assets/{sprite}";
            using var req = UnityWebRequestTexture.GetTexture(url);
            yield return req.SendWebRequest();
            if (req.result == UnityWebRequest.Result.Success && view != null)
                view.SetTexture(DownloadHandlerTexture.GetContent(req));
        }
    }
}
