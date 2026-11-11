using System.Collections;
using System.Collections.Generic;
using Allo.Bridge;
using UnityEngine;

namespace Allo.Critters
{
    /// cast 메시지로 캐릭터를 등장·퇴장시키고, scene·jolt 메시지를 분위기·반응으로 넘긴다.
    /// 걷는 면은 차 모델의 Walk_* 판 위치에서 읽는다.
    public sealed partial class CritterDirector : MonoBehaviour
    {
        public Transform cabin;

        [Tooltip("아이 눈 위치. 이 바로 아래 면(아이가 앉은 자리)에는 캐릭터가 올라가지 않는다")]
        public Transform childEye;

        [Tooltip("카메라 레일의 앞쪽 끝. 아이 눈이나 여기 중 한 곳에서라도 보이는 면만 걷는 면으로 쓴다")]
        public Transform frontEye;
        public Material critterMaterial;
        public Material shadowMaterial;

        /// 장면을 만들 때(에디터) 미리 계산해 둔 걷는 면. 꺼 둔 렌더러의 크기는 앱 빌드에서 0 으로 읽혀서
        /// 실행 중에 계산하지 않는다 (AlloBuild.CreateExploreScene 이 채운다)
        [SerializeField] string[] surfaceNames = new string[0];
        [SerializeField] Vector3[] surfaceCenters = new Vector3[0];
        [SerializeField] Vector2[] surfaceSizes = new Vector2[0];
        /// 면마다 9×9 보임 지도 ('1' = 잘 보이고 가려지지 않음). 검사한 영역(xMin, zMin, 폭, 깊이)과 함께
        [SerializeField] Vector4[] maskAreas = new Vector4[0];
        [SerializeField] string[] masks = new string[0];
        const int MaskN = 9;

        public void Bake()
        {
            var names = new List<string>(); var centers = new List<Vector3>(); var sizes = new List<Vector2>();
            var areas = new List<Vector4>(); var maskList = new List<string>();
            var colliders = childEye != null ? AddTempColliders() : new List<Collider>();
            try
            {
                foreach (var r in cabin.GetComponentsInChildren<Renderer>(true))
                {
                    if (!r.name.StartsWith("Walk_")) continue;
                    var b = r.bounds;
                    if (childEye != null && TooCloseToChild(r.name, b, childEye.position)) continue;
                    if (childEye != null && frontEye != null && ComfortShare(b, childEye.position, Forward) < 0.25f)
                    {
                        Debug.Log($"[Critters] {r.name} 은 아이가 정면을 볼 때 거의 안 보이거나 너무 가까워 빼요");
                        continue;
                    }
                    if (childEye != null && HiddenFromChild(b, childEye.position, colliders) && (frontEye == null || HiddenFromChild(b, frontEye.position, colliders)))
                    {
                        Debug.Log($"[Critters] {r.name} 은 카메라 어디서도 보이지 않아 빼요");
                        continue;
                    }
                    // 잘 보이고(편한 자리) 가려지지도 않는 부분만 남긴다 (창턱 앞쪽 끝은 앞좌석에, 계기판 일부는 머리받침에 가린다)
                    var keep = frontEye != null ? VisiblePart(b, childEye.position, Forward, colliders) : (Rect?)new Rect(b.min.x, b.min.z, b.size.x, b.size.z);
                    if (keep == null)
                    {
                        Debug.Log($"[Critters] {r.name} 은 잘 보이는 부분이 없어 빼요");
                        continue;
                    }
                    var k = keep.Value;
                    areas.Add(new Vector4(b.min.x, b.min.z, b.size.x, b.size.z));
                    maskList.Add(frontEye != null ? Mask(b, childEye.position, Forward, colliders) : new string('1', MaskN * MaskN));
                    names.Add(r.name);
                    centers.Add(new Vector3(k.center.x, b.max.y, k.center.y));
                    sizes.Add(new Vector2(k.width, k.height));
                    if (k.width < b.size.x - 0.01f || k.height < b.size.z - 0.01f)
                        Debug.Log($"[Critters] {r.name} 을 잘 보이는 부분으로 줄여요: {b.size.x:F2}×{b.size.z:F2} → {k.width:F2}×{k.height:F2}");
                }
            }
            finally
            {
                foreach (var c in _tempColliders) DestroyImmediate(c);
                _tempColliders.Clear();
            }
            surfaceNames = names.ToArray(); surfaceCenters = centers.ToArray(); surfaceSizes = sizes.ToArray();
            maskAreas = areas.ToArray(); masks = maskList.ToArray();
        }

        public WalkGraph BuildGraph()
        {
            var list = new List<WalkSurface>();
            for (var i = 0; i < surfaceNames.Length; i++) list.Add(new WalkSurface(surfaceNames[i], surfaceCenters[i], surfaceSizes[i]));
            var g = new WalkGraph(list);
            if (childEye != null && frontEye != null)
            {
                var eye = childEye.position; var fwd = Forward;
                g.Comfortable = p => Comfortable(p, eye, fwd) && Unblocked(p);
            }
            return g;
        }

        Vector3 Forward
        {
            get
            {
                var f = frontEye.position - childEye.position;
                f.y = 0;
                return f.normalized;
            }
        }

        /// 아이가 정면을 볼 때 캐릭터가 편하게 보이는 자리인지: 눈에서 수평 MinView 이상, 정면에서 좌우 MaxYaw 안,
        /// 아래로 MaxPitch 보다 얕게 (몸 가운데 기준). 너무 가까우면 화면을 덮고, 옆·발밑이면 얼굴이 화면 밖으로 잘린다.
        /// 정면 화면은 아래로 36도(세로 화각 72도)까지라 앞좌석 사이 바닥(약 47도)은 고개를 조금 숙여야 보인다 (요청으로 남김)
        public const float MinView = 0.6f, MaxYaw = 60f, MaxPitch = 55f;

        public static bool Comfortable(Vector3 feet, Vector3 eye, Vector3 forward)
        {
            var body = feet + Vector3.up * CritterView.Height * 0.5f;
            var d = body - eye;
            var flat = new Vector3(d.x, 0, d.z);
            var dist = flat.magnitude;
            if (dist < MinView) return false;
            if (Vector3.Angle(flat, forward) > MaxYaw) return false;
            return Mathf.Atan2(-d.y, dist) * Mathf.Rad2Deg <= MaxPitch;
        }

        /// 면 위 9×9 점 가운데 편한 자리이면서 아이 눈에서 가려지지 않는 점들을 감싸는 사각형 (x, z). 없으면 null
        static Rect? VisiblePart(Bounds surface, Vector3 eye, Vector3 forward, ICollection<Collider> occluders)
        {
            const int n = 9;
            float minX = float.MaxValue, maxX = float.MinValue, minZ = float.MaxValue, maxZ = float.MinValue;
            var cx = surface.size.x / n; var cz = surface.size.z / n;
            var found = 0;
            for (var i = 0; i < n; i++)
            for (var j = 0; j < n; j++)
            {
                var p = new Vector3(surface.min.x + (i + 0.5f) * cx, surface.max.y, surface.min.z + (j + 0.5f) * cz);
                if (!Comfortable(p, eye, forward) || Blocked(p, eye, occluders)) continue;
                found++;
                minX = Mathf.Min(minX, p.x - cx / 2); maxX = Mathf.Max(maxX, p.x + cx / 2);
                minZ = Mathf.Min(minZ, p.z - cz / 2); maxZ = Mathf.Max(maxZ, p.z + cz / 2);
            }
            if (found < 2) return null;
            return new Rect(minX, minZ, maxX - minX, maxZ - minZ);
        }

        static string Mask(Bounds surface, Vector3 eye, Vector3 forward, ICollection<Collider> occluders)
        {
            var sb = new System.Text.StringBuilder(MaskN * MaskN);
            for (var j = 0; j < MaskN; j++)
            for (var i = 0; i < MaskN; i++)
            {
                var p = new Vector3(surface.min.x + (i + 0.5f) * surface.size.x / MaskN, surface.max.y,
                    surface.min.z + (j + 0.5f) * surface.size.z / MaskN);
                sb.Append(Comfortable(p, eye, forward) && !Blocked(p, eye, occluders) ? '1' : '0');
            }
            return sb.ToString();
        }

        /// 장면 빌드 때 구운 보임 지도로 p 가 가려지지 않는 자리인지 (지도가 없으면 true)
        bool Unblocked(Vector3 p)
        {
            for (var k = 0; k < masks.Length && k < maskAreas.Length && k < surfaceCenters.Length; k++)
            {
                if (Mathf.Abs(p.y - surfaceCenters[k].y) > 0.05f) continue;
                var a = maskAreas[k];
                var u = (p.x - a.x) / Mathf.Max(1e-4f, a.z);
                var v = (p.z - a.y) / Mathf.Max(1e-4f, a.w);
                if (u < 0 || u > 1 || v < 0 || v > 1) continue;
                var i = Mathf.Min(MaskN - 1, (int)(u * MaskN));
                var j = Mathf.Min(MaskN - 1, (int)(v * MaskN));
                return masks[k][j * MaskN + i] == '1';
            }
            return true;
        }

        /// 캐릭터 몸 가운데가 눈에서 큰 물체에 가리는지
        static bool Blocked(Vector3 feet, Vector3 eye, ICollection<Collider> occluders)
        {
            var p = feet + Vector3.up * CritterView.Height * 0.6f;
            var d = p - eye;
            foreach (var hit in Physics.RaycastAll(eye, d.normalized, d.magnitude - 0.02f))
                if (occluders.Contains(hit.collider)) return true;
            return false;
        }

        /// 면 위 점(5×5) 가운데 편하게 보이는 비율
        public static float ComfortShare(Bounds surface, Vector3 eye, Vector3 forward)
        {
            var ok = 0;
            for (var i = 0; i < 5; i++)
            for (var j = 0; j < 5; j++)
            {
                var p = new Vector3(Mathf.Lerp(surface.min.x, surface.max.x, (i + 0.5f) / 5), surface.max.y,
                    Mathf.Lerp(surface.min.z, surface.max.z, (j + 0.5f) / 5));
                if (Comfortable(p, eye, forward)) ok++;
            }
            return ok / 25f;
        }

        WalkGraph _graph;
        readonly Dictionary<string, CritterView> _views = new();
        Mood _mood = new Mood { moving = true };
        int _seed = 1;

        /// 동행 캐릭터 id (cast.companion). 없으면 null
        public string CompanionId { get; private set; }
        public CritterView Companion => CompanionId != null && _views.TryGetValue(CompanionId, out var v) ? v : null;

        /// 탭: 폴짝 + 하트. 동행 캐릭터면 Flutter 에 tap 을 알린다 (놀아주기 횟수는 Flutter 가 센다)
        public void Poke(CritterView v)
        {
            if (v == null) return;
            v.Brain.Poke();
            v.Cheer();
            Fx.Burst(v.Top, Fx.Heart, critterMaterial, 4, 0.06f);
            if (v.Id == CompanionId) FlutterBridge.Send("tap", FlutterBridge.Field("id", v.Id));
        }

        void Awake()
        {
            _graph = BuildGraph();
            Debug.Log($"[Critters] walk surfaces: {_graph.Surfaces.Count}");
        }

        /// 걷는 면(Walk_*)이 아닌 차 안의 큰 물체에 잠깐 충돌체를 붙인다 (가림 검사용, Bake 가 끝나면 지운다).
        /// 유리, 그리고 룸미러·장식 끈처럼 가늘거나 작은 물체(두 번째로 긴 변 0.12m 미만)는 캐릭터를 다 가리지 못하므로 넣지 않는다
        /// 가림 검사에 쓰는 큰 물체의 충돌체. 탭용 충돌체가 이미 있으면(좌석·머리받침) 그것을 쓰고, 없으면 잠깐 붙인다
        readonly List<Collider> _tempColliders = new();

        List<Collider> AddTempColliders()
        {
            var list = new List<Collider>();
            _tempColliders.Clear();
            foreach (var f in cabin.GetComponentsInChildren<MeshFilter>(true))
            {
                // 유리는 투명해서 가리지 않는다
                if (f.name.StartsWith("Walk_") || f.name.StartsWith("Glass") || f.sharedMesh == null) continue;
                var r = f.GetComponent<Renderer>();
                if (r == null || SecondLongest(r.bounds.size) < 0.12f) continue; // 머리받침(0.15)은 넣고 룸미러(0.07)·장식 끈은 뺀다
                var existing = f.GetComponent<Collider>();
                if (existing != null) { list.Add(existing); continue; }
                var c = f.gameObject.AddComponent<MeshCollider>();
                c.sharedMesh = f.sharedMesh;
                list.Add(c);
                _tempColliders.Add(c);
            }
            Physics.SyncTransforms();
            return list;
        }

        static float SecondLongest(Vector3 v)
        {
            var a = new[] { v.x, v.y, v.z };
            System.Array.Sort(a);
            return a[1];
        }

        /// 면 위 9개 점에 캐릭터가 서 있다고 보고(몸 가운데 높이) 아이 눈에서 절반 넘게 가려지면 true.
        /// 캐릭터는 면 안 아무 데나 서므로, 일부만 보이는 면은 자주 가려진 자리에 선다
        /// 예: 뒷유리 아래 선반은 아이가 기댄 등받이에 가려진다
        /// 탭용으로 이미 붙어 있는 충돌체(유리 등)는 세지 않고 occluders 에 맞은 것만 가린 것으로 본다
        public static bool HiddenFromChild(Bounds surface, Vector3 eye, ICollection<Collider> occluders)
        {
            var lift = CritterView.Height * 0.6f;
            var hidden = 0;
            for (var i = 0; i <= 2; i++)
            for (var j = 0; j <= 2; j++)
            {
                var p = new Vector3(Mathf.Lerp(surface.min.x, surface.max.x, 0.15f + 0.35f * i), surface.max.y + lift,
                    Mathf.Lerp(surface.min.z, surface.max.z, 0.15f + 0.35f * j));
                var d = p - eye;
                var blocked = false;
                foreach (var hit in Physics.RaycastAll(eye, d.normalized, d.magnitude - 0.02f))
                    if (occluders.Contains(hit.collider)) { blocked = true; break; }
                if (blocked) hidden++;
            }
            return hidden > 4;
        }

        int FirstOf(params string[] names)
        {
            foreach (var n in names)
            {
                var i = _graph.IndexOf(n);
                if (i >= 0) return i;
            }
            return 0;
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
            var m = _mood;
            m.night |= _lightsOff; // 실내등을 끄면 밤처럼 존다
            foreach (var v in _views.Values) v.Brain.Tick(Time.deltaTime, m);
            PlayTick(Time.deltaTime);
        }

        void OnScene(SceneState s)
        {
            _scene = s.kind;
            _mood = new Mood
        {
            night = s.night,
            rain = s.rain > 0,
            tunnel = s.kind == "tunnel",
            moving = s.moving,
        };
        }

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
            var start = Mathf.Max(0, FirstOf("Walk_DoorSill_R", "Walk_DoorSill_L", "Walk_Floor")); // 정면에서 잘 보이는 창턱에서 나타난다
            foreach (var m in CastDiff.Members(cast))
            {
                if (!add.Contains(m.id)) continue;
                var go = new GameObject($"Critter_{m.id}");
                go.transform.SetParent(transform, false);
                var view = go.AddComponent<CritterView>();
                var seed = _seed++;
                view.Init(m.id, new CritterBrain(_graph, start, seed * 7919), CritterArt.Placeholder(m.attribute, seed),
                    critterMaterial, shadowMaterial, CharacterModel.Find(m.id));
                _views[m.id] = view;
                if (!string.IsNullOrEmpty(m.sprite)) StartCoroutine(SpriteLoader.Load(m.sprite, art => { if (view != null) view.SetArt(art); }));
            }
        }

    }
}
