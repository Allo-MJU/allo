using System.Collections.Generic;
using Allo.Bridge;
using UnityEngine;
using static Allo.World.Kit;

namespace Allo.World
{
    /// 창밖 3D 세상. 차는 제자리에 있고 도로 조각(ChunkTrack)이 속도만큼 뒤로 흐른다.
    /// scene 메시지로 장면·밤·비·고속도로·속도를 받고, 하늘·안개·해·전조등·비·차량을 맞춘다.
    public sealed class WorldDirector : MonoBehaviour
    {
        [Header("차")]
        [Tooltip("차 가운데 (바닥 높이는 roadY 를 쓴다)")] public Vector3 carCenter;
        [Tooltip("차가 달리는 방향 (차체 축). 아이 눈은 한쪽 자리라 축 계산에 쓰지 않는다")] public Vector3 forward = Vector3.forward;
        [Tooltip("노면 높이 (차 바닥보다 조금 아래)")] public float roadY = -0.35f;

        [Header("재질 (장면 빌드가 채운다)")] public Material solid;
        public Material glow;
        public Material glass;
        public Material rain;
        public Material windows;
        public Material ground;
        public Material sky;
        public Light sun;
        [Tooltip("차 유리 재질 (Allo/Glass). 비 오면 빗방울을 켠다")] public Material cabinGlass;
        [Tooltip("캐릭터·창밖 친구 그림 재질")] public Material sprite;
        public Wipers wipers;
        public AlloPost post;

        [Header("Blender 물체 (Props.fbx 에서 장면 빌드가 채운다)")]
        public GameObject[] props = new GameObject[0];
        [Tooltip("밤에 켜지는 물체 재질 (전조등·가로등·등대)")] public Material[] propGlows = new Material[0];

        Kit _kit;
        ChunkTrack _track;
        Transform _root, _backdrop, _traffic;
        readonly Dictionary<int, Transform> _chunks = new();
        readonly Queue<ChunkInfo> _pending = new();

        /// 한 프레임에 만드는 조각 수. 장면이 바뀔 때 한꺼번에 만들면 화면이 멈춘다
        const int BuildsPerFrame = 2;
        Material _windows;
        SceneState _scene = new SceneState { kind = "road", moving = true, speedKph = 60 };
        string _builtBackdrop;
        ParticleSystem _rain;
        Light _headlights;
        float _trafficTimer = 2;
        readonly List<(Transform t, float speed)> _cars = new();
        Passersby _passersby;
        float _glassPulse, _rainLevel;

        /// 창밖에 보이는, 아직 안 본 친구 (HUD 의 "봤어!" 버튼)
        public Passerby Spottable => _passersby != null ? _passersby.Spottable : null;
        public bool Spot(Passerby p) => _passersby != null && _passersby.Spot(p);

        /// 유리창을 두드리면: 비 오면 빗방울이 튀고, 아니면 반짝인다
        public void TapGlass(Vector3 at)
        {
            var rainy = _scene.rain > 0 && _scene.kind != "tunnel";
            if (rainy) _glassPulse = 1;
            Fx.Burst(at, Fx.Spark, sprite, rainy ? 5 : 3, 0.05f, 0.06f);
        }

        public SceneState Scene => _scene;

        void Setup()
        {
            if (_kit != null) return;
            _kit = new Kit(solid, glow, props);
            _kit.SetGround(ground);
            _track = new ChunkTrack();
            var fwd = forward;
            fwd.y = 0;
            _root = new GameObject("WorldRoot").transform;
            _root.SetParent(transform, false);
            _root.position = new Vector3(carCenter.x, roadY, carCenter.z);
            _root.rotation = Quaternion.LookRotation(fwd.normalized, Vector3.up);
            _backdrop = new GameObject("Backdrop").transform;
            _backdrop.SetParent(_root, false);
            _traffic = new GameObject("Traffic").transform;
            _traffic.SetParent(_root, false);
            _windows = new Material(windows);
            MakeRain();
            MakeHeadlights();
            if (sprite != null)
            {
                _passersby = new GameObject("Passersby").AddComponent<Passersby>();
                _passersby.transform.SetParent(_root, false);
                _passersby.Init(_root, sprite);
            }
        }

        void OnEnable() => FlutterBridge.SceneChanged += OnScene;
        void OnDisable() => FlutterBridge.SceneChanged -= OnScene;

        void Start()
        {
            Setup();
            Apply(FlutterBridge.LastScene ?? _scene);
        }

        void OnScene(SceneState s)
        {
            Setup();
            Apply(s);
        }

        static string Key(SceneState s) => s.kind == "tunnel" ? "tunnel" : s.highway ? "highway" : s.kind;

        /// 장면을 바로 맞춘다. reset 이면 지난 장면 조각을 모두 지운다 (에디터 캡처용).
        public void Apply(SceneState s, bool reset = false)
        {
            Setup();
            if (reset)
            {
                foreach (var t in _chunks.Values) Drop(t);
                _chunks.Clear();
                _pending.Clear();
                _track = new ChunkTrack();
            }
            _scene = s;
            Sync(_track.SetScene(Key(s)), now: reset || !Application.isPlaying);
            if (_builtBackdrop != Key(s)) BuildBackdrop(Key(s));
            foreach (var r in _backdrop.GetComponentsInChildren<Renderer>())
                if (r.name.StartsWith("Cloud")) r.enabled = !s.night && s.kind != "tunnel"; // 밤에는 구름을 숨긴다
            Atmosphere(s);
        }

        float _fpsT; int _fpsN;

        void Update()
        {
            if (_kit == null) return;
            // 10초마다 평균 프레임 시간을 남긴다 (성능 확인용, 로그 한 줄)
            _fpsT += Time.unscaledDeltaTime; _fpsN++;
            if (_fpsT >= 10) { Debug.Log($"[World] {_fpsN / _fpsT:F1} fps, chunks={_chunks.Count}, pending={_pending.Count}, cars={_cars.Count}, scene={Key(_scene)}"); _fpsT = 0; _fpsN = 0; }
            var meters = _scene.moving ? _scene.speedKph / 3.6f * Time.deltaTime : 0;
            Sync(_track.Advance(meters));
            for (var n = 0; n < BuildsPerFrame && _pending.Count > 0; n++) Build(_pending.Dequeue());
            foreach (var (i, t) in _chunks) t.localPosition = new Vector3(0, 0, _track.StartOf(i));
            Traffic(meters);
            if (_passersby != null) _passersby.Tick(meters, _scene, Camera.main);
            if (_glassPulse > 0 && cabinGlass != null)
            {
                _glassPulse = Mathf.MoveTowards(_glassPulse, 0, Time.deltaTime * 1.5f);
                cabinGlass.SetFloat("_Rain", Mathf.Clamp01(_rainLevel + _glassPulse * 0.6f));
            }
            _backdrop.localRotation = Quaternion.Euler(0, Time.time * 0.15f, 0); // 구름이 천천히 흐른다
        }

        void Sync((List<ChunkInfo> spawn, List<int> despawn) d, bool now = false)
        {
            foreach (var i in d.despawn)
                if (_chunks.TryGetValue(i, out var t))
                {
                    Drop(t);
                    _chunks.Remove(i);
                }
            if (d.despawn.Count > 0)
            {
                var keep = new List<ChunkInfo>(_pending);
                _pending.Clear();
                foreach (var c in keep)
                    if (!d.despawn.Contains(c.index)) _pending.Enqueue(c);
            }
            // 가까운 조각부터 만든다
            d.spawn.Sort((a, b) => Mathf.Abs(a.index).CompareTo(Mathf.Abs(b.index)));
            foreach (var c in d.spawn)
                if (now) Build(c);
                else _pending.Enqueue(c);
        }

        void Build(ChunkInfo c)
        {
            if (!_track.Live.TryGetValue(c.index, out var live) || live != c) return; // 그사이 바뀐 조각
            var t = new GameObject($"Chunk_{c.index}_{c.kind}").transform;
            t.SetParent(_root, false);
            t.localPosition = new Vector3(0, 0, _track.StartOf(c.index));
            ChunkBuilder.Build(_kit, t, c, _track.ChunkLength, _windows);
            foreach (var r in t.GetComponentsInChildren<Renderer>())
                if (r.name == "SoundWall") r.sharedMaterial = glass;
            Combine(t);
            _chunks[c.index] = t;
        }

        /// 조각 안 물체 수백 개를 재질별로 하나의 메시로 합친다 (그리기 호출·Transform 수를 크게 줄인다)
        static void Combine(Transform chunk)
        {
            var groups = new Dictionary<Material, List<CombineInstance>>();
            var parts = new List<GameObject>();
            var custom = new List<Mesh>(); // 건물 창문 판처럼 코드로 만든 메시는 합친 뒤 지운다
            var toLocal = chunk.worldToLocalMatrix;
            foreach (var mf in chunk.GetComponentsInChildren<MeshFilter>())
            {
                // Blender 물체는 한 메시에 재질이 여러 개다 (줄기·잎). 재질 칸마다 따로 모은다
                var mats = mf.GetComponent<MeshRenderer>().sharedMaterials;
                for (var sub = 0; sub < mf.sharedMesh.subMeshCount && sub < mats.Length; sub++)
                {
                    var m = mats[sub];
                    if (!groups.TryGetValue(m, out var list)) groups[m] = list = new List<CombineInstance>();
                    list.Add(new CombineInstance { mesh = mf.sharedMesh, subMeshIndex = sub, transform = toLocal * mf.transform.localToWorldMatrix });
                }
                parts.Add(mf.gameObject);
                if (mf.sharedMesh.name == "Facade") custom.Add(mf.sharedMesh);
            }
            foreach (var g in parts) Kill(g);
            foreach (var (m, list) in groups)
            {
                var mesh = new Mesh { indexFormat = UnityEngine.Rendering.IndexFormat.UInt32, name = m.name };
                mesh.CombineMeshes(list.ToArray(), true, true);
                var go = new GameObject(m.name);
                go.transform.SetParent(chunk, false);
                go.AddComponent<MeshFilter>().sharedMesh = mesh;
                var r = go.AddComponent<MeshRenderer>();
                r.sharedMaterial = m;
                r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                r.receiveShadows = false;
            }
            foreach (var m in custom) Kill(m);
        }

        /// 조각을 지울 때 합친 메시도 같이 지운다 (메모리 누수 방지)
        static void Drop(Transform chunk)
        {
            foreach (var mf in chunk.GetComponentsInChildren<MeshFilter>()) Kill(mf.sharedMesh);
            Kill(chunk.gameObject);
        }

        /// 멀리 있어 움직이지 않는 배경 (산맥·섬·도시 윤곽). 안개가 푸르게 바래게 한다
        void BuildBackdrop(string key)
        {
            _builtBackdrop = key;
            for (var i = _backdrop.childCount - 1; i >= 0; i--) Kill(_backdrop.GetChild(i).gameObject);
            var r = new System.Random(key.GetHashCode());
            if (key == "tunnel") return;
            // 하늘의 뭉게구름: 아주 멀리 있어 차가 달려도 거의 안 움직인다 (천천히 흐르게만 한다)
            for (var i = 0; i < 16; i++)
            {
                var a = Rand(r, 0, Mathf.PI * 2);
                var d = Rand(r, 240, 420);
                _kit.Prop("Cloud", _backdrop, new Vector3(Mathf.Cos(a) * d, Rand(r, 55, 120), Mathf.Sin(a) * d), Rand(r, 0, 360), Rand(r, 2.5f, 5f));
            }
            var hill = key == "mountain" ? C("#4F7A5A") : C("#6E9A6A");
            var count = key == "mountain" ? 26 : key == "city" ? 0 : 14;
            for (var i = 0; i < count; i++)
            {
                var a = Rand(r, 0, Mathf.PI * 2);
                var d = Rand(r, 260, 420);
                var h = key == "mountain" ? Rand(r, 90, 220) : Rand(r, 30, 70);
                var w = h * Rand(r, 1.6f, 2.6f);
                if (key == "coast" && Mathf.Cos(a) > -0.2f) { h *= 0.35f; w *= 0.7f; } // 바다 쪽은 낮은 섬
                _kit.Ball(_backdrop, new Vector3(Mathf.Cos(a) * d, -h * 0.3f, Mathf.Sin(a) * d), new Vector3(w, h, w), hill);
            }
            if (key == "city")
                for (var i = 0; i < 70; i++)
                {
                    var a = Rand(r, 0, Mathf.PI * 2);
                    var d = Rand(r, 200, 380);
                    var h = Rand(r, 30, 110);
                    _kit.Box(_backdrop, new Vector3(Mathf.Cos(a) * d, 0, Mathf.Sin(a) * d), new Vector3(Rand(r, 14, 30), h, Rand(r, 14, 30)), C("#8DA2B6"));
                }
        }

        void Atmosphere(SceneState s)
        {
            var tunnel = s.kind == "tunnel";
            var rainy = s.rain > 0 && !tunnel;
            Color horizon, ambientSky, ambientGround;
            float sunI;
            if (tunnel)
            {
                horizon = C("#2B2420"); ambientSky = C("#7A5A3A"); ambientGround = C("#2A2420"); sunI = 0;
            }
            else if (s.night)
            {
                horizon = C("#26345E"); ambientSky = C("#34406A"); ambientGround = C("#141A2C"); sunI = 0.12f;
            }
            else if (rainy)
            {
                horizon = C("#A9B3BC"); ambientSky = C("#8E9AA6"); ambientGround = C("#5A5E5E"); sunI = 0.45f;
            }
            else
            {
                horizon = C("#DDEBEF"); ambientSky = C("#8FB4D6"); ambientGround = C("#6E6658"); sunI = 1.0f;
            }
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogColor = horizon;
            RenderSettings.fogStartDistance = tunnel ? 10 : rainy ? 25 : 60;
            RenderSettings.fogEndDistance = tunnel ? 140 : rainy ? 260 : 460;
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = ambientSky;
            RenderSettings.ambientEquatorColor = Color.Lerp(ambientSky, ambientGround, 0.5f);
            RenderSettings.ambientGroundColor = ambientGround;
            if (sky != null)
            {
                RenderSettings.skybox = sky;
                var (top, hor) = tunnel ? (C("#1A1612"), C("#2B2420"))
                    : s.night ? (C("#0B1438"), C("#2E3F78"))
                    : rainy ? (C("#7C8996"), C("#B9C2C9"))
                    : (C("#2F86E8"), C("#BFE4FF"));
                sky.SetColor("_Top", top);
                sky.SetColor("_Horizon", hor);
                sky.SetColor("_Bottom", Color.Lerp(hor, ambientGround, 0.5f));
                sky.SetColor("_SunColor", s.night ? C("#E8EEFF") * 0.8f : rainy ? Color.black : C("#FFF4D6"));
                sky.SetFloat("_SunSize", s.night ? 0.006f : 0.012f);
                if (sun != null) sky.SetVector("_SunDir", -sun.transform.forward);
                horizon = hor;
                RenderSettings.fogColor = hor;
            }
            if (sun != null)
            {
                sun.intensity = sunI;
                sun.color = s.night ? C("#9FB0E0") : C("#FFF4E0");
            }
            var glowBoost = s.night || tunnel ? 1.6f : 0.35f;
            foreach (var m in _kit.Glows) m.SetColor("_EmissionColor", m.color / 0.6f * glowBoost);
            foreach (var m in propGlows) m.SetColor("_EmissionColor", m.color * glowBoost * 1.6f);
            _windows.SetColor("_EmissionColor", s.night ? C("#FFD98A") * 0.9f : Color.black);
            _windows.color = s.night ? C("#3A4660") : C("#9FB4C8");
            if (_headlights != null) _headlights.enabled = s.night || tunnel;
            if (_rain != null)
            {
                var e = _rain.emission;
                e.rateOverTime = rainy ? 120 * s.rain : 0;
                if (rainy && !_rain.isPlaying) _rain.Play();
            }
            _rainLevel = rainy ? s.rain / 3f : 0;
            if (cabinGlass != null) cabinGlass.SetFloat("_Rain", _rainLevel);
            if (wipers != null) wipers.SetRain(rainy ? s.rain : 0);
            if (post != null)
            {
                // 밤·터널은 불빛이 번지게, 낮은 쨍하게
                if (tunnel) { post.bloom = 0.9f; post.threshold = 0.55f; post.saturation = 1.05f; post.contrast = 1.08f; post.lift = new Color(0.02f, 0.01f, 0); }
                else if (s.night) { post.bloom = 1.4f; post.threshold = 0.42f; post.saturation = 1.1f; post.contrast = 1.1f; post.lift = new Color(0, 0.004f, 0.02f); }
                else if (rainy) { post.bloom = 0.3f; post.threshold = 0.85f; post.saturation = 0.95f; post.contrast = 1.05f; post.lift = new Color(0, 0.008f, 0.016f); }
                else { post.bloom = 0.28f; post.threshold = 0.88f; post.saturation = 1.22f; post.contrast = 1.08f; post.lift = new Color(0.014f, 0.008f, 0); }
                post.vignette = 0.16f;
            }
            if (Camera.main != null)
            {
                Camera.main.clearFlags = CameraClearFlags.Skybox;
                Camera.main.farClipPlane = 900;
            }
        }

        void Traffic(float meters)
        {
            // 마주 오는 차: 왼쪽 차로로 다가와 스쳐 지나간다
            _trafficTimer -= Time.deltaTime;
            if (_trafficTimer <= 0 && _scene.moving)
            {
                _trafficTimer = Random.Range(2.5f, 7f);
                var t = new GameObject("Oncoming").transform;
                t.SetParent(_traffic, false);
                var x = _scene.highway ? -7 : -3.5f;
                t.localPosition = new Vector3(x, 0, 320);
                t.localRotation = Quaternion.Euler(0, 180, 0);
                _kit.Car(t, Vector3.zero, C(new[] { "#E9E4DA", "#7FA6C9", "#C8654F", "#59615E", "#F2C14E", "#3F7D5A" }[Random.Range(0, 6)]), true, Random.Range(0, 9));
                _cars.Add((t, Random.Range(40f, 80f) / 3.6f));
            }
            for (var i = _cars.Count - 1; i >= 0; i--)
            {
                var (t, v) = _cars[i];
                if (t == null) { _cars.RemoveAt(i); continue; }
                t.localPosition -= new Vector3(0, 0, meters + v * Time.deltaTime);
                if (t.localPosition.z < -60 || _scene.kind == "tunnel" && t.localPosition.z > 140)
                {
                    Kill(t.gameObject);
                    _cars.RemoveAt(i);
                }
            }
        }

        void MakeRain()
        {
            var go = new GameObject("Rain");
            go.transform.SetParent(_root, false);
            go.transform.localPosition = new Vector3(0, 14, 12);
            _rain = go.AddComponent<ParticleSystem>();
            _rain.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = _rain.main;
            main.startSpeed = 18;
            main.startLifetime = 0.9f;
            main.startSize = 0.03f;
            main.maxParticles = 500;
            main.startColor = new Color(0.85f, 0.9f, 1f, 0.55f);
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            var shape = _rain.shape;
            shape.shapeType = ParticleSystemShapeType.Box;
            shape.scale = new Vector3(36, 0.1f, 50);
            go.transform.localRotation = Quaternion.Euler(90, 0, 0);
            var em = _rain.emission;
            em.rateOverTime = 0;
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.renderMode = ParticleSystemRenderMode.Stretch;
            r.lengthScale = 6;
            r.sharedMaterial = rain;
        }

        void MakeHeadlights()
        {
            var go = new GameObject("Headlights");
            go.transform.SetParent(_root, false);
            go.transform.localPosition = new Vector3(0, 0.8f, 2.5f);
            go.transform.localRotation = Quaternion.Euler(6, 0, 0);
            _headlights = go.AddComponent<Light>();
            _headlights.type = LightType.Spot;
            _headlights.spotAngle = 60;
            _headlights.range = 60;
            _headlights.intensity = 1.6f;
            _headlights.color = C("#FFF2D0");
            _headlights.enabled = false;
        }

        /// 건물 창문 무늬: 가로 3 × 세로 4 칸이 반복된다. 밤에는 일부 칸이 노랗게 켜진다
        public static Texture2D WindowTexture()
        {
            const int n = 128;
            var t = new Texture2D(n, n, TextureFormat.RGBA32, true) { wrapMode = TextureWrapMode.Repeat };
            var rng = new System.Random(5);
            var cells = new bool[4, 4];
            for (var i = 0; i < 4; i++) for (var j = 0; j < 4; j++) cells[i, j] = rng.NextDouble() < 0.5;
            for (var y = 0; y < n; y++)
            for (var x = 0; x < n; x++)
            {
                var cx = x % 32; var cy = y % 32;
                var inWin = cx > 6 && cx < 26 && cy > 5 && cy < 27;
                var lit = cells[x / 32, y / 32];
                t.SetPixel(x, y, inWin ? (lit ? new Color(1, 1, 1, 1) : new Color(0.55f, 0.6f, 0.68f, 1)) : new Color(0.0f, 0.0f, 0.0f, 0));
            }
            t.Apply();
            return t;
        }
    }
}
