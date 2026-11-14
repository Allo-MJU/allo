using System.Collections.Generic;
using Allo.Bridge;
using UnityEngine;
using static Allo.World.Kit;

namespace Allo.World
{
    /// 창밖 3D 세상. 차는 제자리에 있고 세상이 경로(ChunkTrack)를 따라 움직인다.
    /// 조각과 차량·친구는 트랙 공간(_trackT)에 두고, 매 프레임 차의 경로 자세의 역변환을 _trackT 에 걸어 회전·유턴 때 세상이 돌게 한다.
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
        Transform _root, _trackT, _backdrop, _traffic, _base;
        string _baseKind;
        Quaternion _sunBase;
        float _carYaw;
        readonly Dictionary<int, Transform> _chunks = new();
        /// 조각마다 남긴 길가 물체의 바닥 범위(트랙 공간). 나중에 생긴 도로가 이 위를 지나면 그 조각을 다시 짓는다
        readonly Dictionary<int, List<Bounds>> _foot = new();
        readonly Queue<ChunkInfo> _pending = new();

        /// 한 프레임에 만드는 조각 수. 장면이 바뀔 때 한꺼번에 만들면 화면이 멈춘다
        const int BuildsPerFrame = 2;
        Material _windows;
        SceneState _scene = new SceneState { kind = "road", moving = true, speedKph = 60 };
        string _builtBackdrop;
        ParticleSystem _rain;
        Light _headlights;
        float _trafficTimer = 2;
        readonly List<Car> _cars = new();

        /// 마주 오는 차: 경로 거리 d 에서 우리 쪽으로 다가온다
        sealed class Car { public Transform t; public float d, speed, x; }
        Passersby _passersby;
        float _glassPulse, _rainLevel;
        float _visKph; // 창밖이 흐르는 속도 (km/h)
        bool _inTunnel; // 차가 실제로 터널 조각 안에 있는지. 장면이 터널로 바뀌어도 입구에 닿기 전까지는 바깥 조명이다
        static readonly int WorldToRoot = Shader.PropertyToID("_AlloWorldToRoot"), Travel = Shader.PropertyToID("_AlloTravel");

        /// 창밖에 보이는, 아직 안 본 친구 (HUD 의 "봤어!" 버튼)
        public Passerby Spottable => _passersby != null ? _passersby.Spottable : null;
        public bool Spot(Passerby p) => _passersby != null && _passersby.Spot(p);

        /// 유리창을 두드리면: 비 오면 빗방울이 튀고, 아니면 반짝인다
        public void TapGlass(Vector3 at)
        {
            var rainy = _scene.rain > 0 && !_inTunnel;
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
            // 땅 무늬가 조각과 같이 흐르도록 (Allo/Toon 의 _WorldUV 참조)
            Shader.SetGlobalMatrix(WorldToRoot, _root.worldToLocalMatrix);
            Shader.SetGlobalFloat(Travel, 0);
            _trackT = new GameObject("Track").transform;
            _trackT.SetParent(_root, false);
            _backdrop = new GameObject("Backdrop").transform;
            _backdrop.SetParent(_root, false);
            _traffic = new GameObject("Traffic").transform;
            _traffic.SetParent(_trackT, false);
            if (sun != null) _sunBase = sun.transform.rotation;
            _windows = new Material(windows);
            MakeRain();
            MakeHeadlights();
            if (sprite != null)
            {
                _passersby = new GameObject("Passersby").AddComponent<Passersby>();
                _passersby.transform.SetParent(_trackT, false);
                _passersby.Init(_trackT, sprite, _track);
            }
        }

        void OnEnable()
        {
            FlutterBridge.SceneChanged += OnScene;
            FlutterBridge.RouteChanged += OnRoute;
        }

        void OnDisable()
        {
            FlutterBridge.SceneChanged -= OnScene;
            FlutterBridge.RouteChanged -= OnRoute;
        }

        /// 내비의 다음 회전들. 그 거리에 교차로·유턴 조각을 놓는다
        public void OnRoute(RouteState r)
        {
            Setup();
            var turns = new List<(string, float)>();
            if (r?.turns != null)
                foreach (var t in r.turns)
                    if (t != null && !string.IsNullOrEmpty(t.type)) turns.Add((t.type, t.inM));
            Sync(_track.SetTurns(turns), now: !Application.isPlaying);
            if (r != null && r.heading >= 0) Steer(r.heading);
        }

        float? _headingOrigin; // 트랙 yaw 0 에 해당하는 실제 진행 방향

        /// 실제 진행 방향(도)에 맞춰 앞길을 휜다. 교차로·유턴을 지나는 동안은 그 조각이 이미 돌려 주므로 건드리지 않고,
        /// 지난 뒤 기준을 다시 맞춘다 (내비 회전 각도와 실제 각도가 조금 달라도 쌓이지 않게)
        void Steer(float heading)
        {
            var car = _track.CarPose.yaw;
            var near = _track.NextTurnStart(_track.Offset - 40);
            var inTurn = near < _track.Offset + 25;
            if (_headingOrigin == null || inTurn)
            {
                _headingOrigin = heading - car;
                return;
            }
            var desired = heading - _headingOrigin.Value;
            // 차가 실제로 도는 중(지금 앞길과 30도 넘게 차이)이면 내비 회전을 기다린다
            if (Mathf.Abs(Mathf.DeltaAngle(car, desired)) > 30) return;
            var res = _track.SteerTo(desired);
            if (res == null) return;
            var (bent, moved) = res.Value;
            if (_chunks.TryGetValue(bent.index, out var bt))
            {
                Drop(bt);
                _chunks.Remove(bent.index);
                _foot.Remove(bent.index);
            }
            if (Application.isPlaying) _pending.Enqueue(bent); else Build(bent);
            foreach (var c in moved)
            {
                if (!_chunks.TryGetValue(c.index, out var t)) continue;
                t.localPosition = c.geom.pos;
                t.localRotation = c.geom.Rot;
                _foot.Remove(c.index); // 옮긴 조각의 바닥 범위는 더 이상 맞지 않는다
            }
        }

        void Start()
        {
            Setup();
            Apply(FlutterBridge.LastScene ?? _scene);
            if (FlutterBridge.LastRoute != null) OnRoute(FlutterBridge.LastRoute);
        }

        void OnScene(SceneState s)
        {
            Setup();
            Apply(s);
        }

        static string Key(SceneState s) => s.kind == "tunnel" ? "tunnel" : s.highway ? "highway" : s.kind;

        /// 장면을 바로 맞춘다. reset 이면 지난 장면 조각을 모두 지운다 (에디터 캡처용).
        /// 촬영 모드(FilmMode)가 정한 배경. 있으면 차량 신호 대신 맑은 낮의 이 배경을 쓴다
        public static string FilmKind;

        public void Apply(SceneState s, bool reset = false)
        {
            if (!string.IsNullOrEmpty(FilmKind) && s != null)
            {
                // 촬영 중에는 늘 달린다 (서 있다가 천천히 출발하지 않게 보이는 속도도 바로 맞춘다)
                s = new SceneState { kind = FilmKind == "highway" ? "road" : FilmKind, highway = FilmKind == "highway", speedKph = Mathf.Max(s.speedKph, 50), moving = true };
                _visKph = Mathf.Max(_visKph, s.speedKph);
            }
            Setup();
            if (reset)
            {
                foreach (var t in _chunks.Values) Drop(t);
                _chunks.Clear();
                _foot.Clear();
                _pending.Clear();
                _track = new ChunkTrack();
                if (_passersby != null) _passersby.Init(_trackT, sprite, _track);
            }
            _scene = s;
            Sync(_track.SetScene(Key(s)), now: reset || !Application.isPlaying);
            // 터널 장면은 배경을 새로 만들지 않는다. 입구까지는 지금 배경이 보이고, 터널 안에서는 배경을 숨긴다
            if (Key(s) != "tunnel" && _builtBackdrop != Key(s)) BuildBackdrop(Key(s));
            foreach (var r in _backdrop.GetComponentsInChildren<Renderer>())
                if (r.name.StartsWith("Cloud")) r.enabled = !s.night; // 밤에는 구름을 숨긴다
            _inTunnel = _track.KindAt(0) == "tunnel";
            _backdrop.gameObject.SetActive(!_inTunnel);
            BaseGround(Key(s));
            Atmosphere(s);
            Follow();
        }

        float _fpsT; int _fpsN;

        void Update()
        {
            if (_kit == null) return;
            // 10초마다 평균 프레임 시간을 남긴다 (성능 확인용, 로그 한 줄)
            _fpsT += Time.unscaledDeltaTime; _fpsN++;
            if (_fpsT >= 10) { Debug.Log($"[World] {_fpsN / _fpsT:F1} fps, chunks={_chunks.Count}, pending={_pending.Count}, cars={_cars.Count}, scene={Key(_scene)}"); _fpsT = 0; _fpsN = 0; }
            // 교차로·유턴에서는 천천히 돈다 (실제 차도 속도를 줄인다)
            // 보이는 속도는 목표(차 속도, 교차로 앞 감속 곡선)를 향해 천천히 바뀐다: 가속 2m/s², 감속 3m/s²
            var target = _scene.moving ? Mathf.Min(_scene.speedKph, _track.SpeedCapAt(_track.Offset)) : 0;
            var step = (target > _visKph ? 2f : 3f) * 3.6f * Time.deltaTime;
            _visKph = Mathf.MoveTowards(_visKph, target, step);
            var meters = _visKph / 3.6f * Time.deltaTime;
            var swu = System.Diagnostics.Stopwatch.StartNew();
            Sync(_track.Advance(meters));
            if (swu.ElapsedMilliseconds > 80) Debug.Log($"[World] slow advance {swu.ElapsedMilliseconds}ms offset={_track.Offset:F0} live={_track.Live.Count}");
            // 터널 입구·출구를 지나는 순간 조명을 바꾼다
            var inTunnel = _track.KindAt(0) == "tunnel";
            if (inTunnel != _inTunnel)
            {
                _inTunnel = inTunnel;
                _backdrop.gameObject.SetActive(!inTunnel);
                Atmosphere(_scene);
            }
            for (var n = 0; n < BuildsPerFrame && _pending.Count > 0; n++) Build(_pending.Dequeue());
            Follow();
            Traffic(meters);
            if (_passersby != null) _passersby.Tick(meters, _scene, _inTunnel, Camera.main);
            if (_glassPulse > 0 && cabinGlass != null)
            {
                _glassPulse = Mathf.MoveTowards(_glassPulse, 0, Time.deltaTime * 1.5f);
                cabinGlass.SetFloat("_Rain", Mathf.Clamp01(_rainLevel + _glassPulse * 0.6f));
            }
            _backdrop.localRotation = Quaternion.Euler(0, -_carYaw + Time.time * 0.15f, 0); // 차가 돌면 먼 배경도 돌고, 구름은 천천히 흐른다
        }

        /// 진입 연출(CameraRig.Intro): 실내 모델을 밖에서 볼 때 차로 보이게 바퀴·차대·미등을 단다.
        /// width·length 는 실내 크기, along 은 차 가운데에서 실내 가운데까지 앞쪽 거리, floor 는 노면에서 실내 바닥까지 높이.
        /// 실내에 들어오면 부르는 쪽이 지운다
        public Transform MakeIntroShell(float width, float length, float along, float floor)
        {
            Setup();
            var t = new GameObject("IntroShell").transform;
            t.SetParent(_root, false);
            var r = Mathf.Max(0.3f, floor + 0.06f);
            foreach (var x in new[] { -1f, 1f })
            {
                foreach (var z in new[] { -0.3f, 0.3f })
                    _kit.Wheel(t, new Vector3(x * (width / 2 - 0.08f), r, along + z * length), r, 0.24f);
                _kit.GlowBox(t, new Vector3(x * width * 0.36f, floor + 0.35f, along - length / 2 - 0.02f), new Vector3(0.3f, 0.16f, 0.05f), Kit.C("#E2463A"));
            }
            _kit.Box(t, new Vector3(0, 0.14f, along), new Vector3(width * 0.94f, Mathf.Max(0.05f, floor - 0.12f), length * 0.98f), Kit.C("#3A3531"));
            return t;
        }

        /// 에디터 캡처용: meters 만큼 달린 것으로 치고 조각을 바로 짓는다 (Update 가 돌지 않는 배치 모드)
        public void EditorStep(float meters)
        {
            Setup();
            Sync(_track.Advance(meters), now: true);
            while (_pending.Count > 0) Build(_pending.Dequeue());
            Follow();
            var inTunnel = _track.KindAt(0) == "tunnel";
            if (inTunnel != _inTunnel) { _inTunnel = inTunnel; Atmosphere(_scene); }
        }

        /// 달린 경로 거리와 다음 교차로 시작 거리 (캡처 위치를 정할 때 쓴다)
        public float Travelled => _track.Offset;
        public float NextTurnStart => _track.NextTurnStart(_track.Offset);
        public float NextFeatureStart => _track.NextFeatureStart(_track.Offset);
        public float SpeedCapNow => _track.SpeedCapAt(_track.Offset);

        /// 차의 경로 자세를 원점·정면으로 오게 트랙을 옮긴다. 땅 무늬·해·먼 배경도 같이 돈다
        void Follow()
        {
            var pose = _track.CarPose;
            _carYaw = pose.yaw;
            var rot = Quaternion.Euler(0, -pose.yaw, 0);
            _trackT.localRotation = rot;
            _trackT.localPosition = -(rot * pose.pos);
            // 땅 무늬는 트랙 좌표에 붙인다 (Allo/Toon 의 _WorldUV). 트랙이 움직이므로 달린 거리를 따로 더하지 않는다
            Shader.SetGlobalMatrix(WorldToRoot, _trackT.worldToLocalMatrix);
            Shader.SetGlobalFloat(Travel, 0);
            if (sun != null)
            {
                var rr = _root.rotation;
                sun.transform.rotation = rr * rot * Quaternion.Inverse(rr) * _sunBase;
                if (sky != null) sky.SetVector("_SunDir", -sun.transform.forward);
            }
            if (_base != null) _base.localPosition = new Vector3(0, _base.localPosition.y, 0);
        }

        /// 조각 사이·회전 모서리에 구멍이 보이지 않게 차 아래에 넓은 바닥을 깐다 (조각의 땅보다 조금 낮게)
        void BaseGround(string key)
        {
            if (_baseKind == key) return;
            _baseKind = key;
            if (_base != null) Kill(_base.gameObject);
            var (c, y) = key switch
            {
                "city" => (C("#9A9890"), -0.07f),
                "coast" => (C("#6CB847"), -0.35f),  // 바다(윗면 -0.3)보다 아래
                "mountain" or "highway" => (C("#549E3A"), -0.07f),
                _ => (C("#6CB847"), -0.07f),
            };
            // 안개가 꼭짓점마다 계산되므로 큰 판 하나로 깔면 판 전체가 안개색이 된다. 25m 격자로 나눈다
            _baseMesh ??= GridMesh(1600, 64);
            var go = new GameObject("BaseGround");
            go.transform.SetParent(_root, false);
            go.transform.localPosition = new Vector3(0, y, 0);
            go.AddComponent<MeshFilter>().sharedMesh = _baseMesh;
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterial = _kit.GroundMaterial(c);
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            _base = go.transform;
        }

        static Mesh _baseMesh;

        /// size m 정사각형을 n×n 칸으로 나눈 위를 보는 판
        static Mesh GridMesh(float size, int n)
        {
            var v = new Vector3[(n + 1) * (n + 1)];
            var uv = new Vector2[v.Length];
            for (var z = 0; z <= n; z++)
            for (var x = 0; x <= n; x++)
            {
                v[z * (n + 1) + x] = new Vector3((x / (float)n - 0.5f) * size, 0, (z / (float)n - 0.5f) * size);
                uv[z * (n + 1) + x] = new Vector2(x / (float)n, z / (float)n);
            }
            var tri = new int[n * n * 6];
            var t = 0;
            for (var z = 0; z < n; z++)
            for (var x = 0; x < n; x++)
            {
                var i = z * (n + 1) + x;
                tri[t++] = i; tri[t++] = i + n + 1; tri[t++] = i + 1;
                tri[t++] = i + 1; tri[t++] = i + n + 1; tri[t++] = i + n + 2;
            }
            var m = new Mesh { name = "BaseGrid", vertices = v, uv = uv, triangles = tri };
            m.RecalculateNormals();
            m.RecalculateBounds();
            return m;
        }

        void Sync((List<ChunkInfo> spawn, List<int> despawn) d, bool now = false)
        {
            foreach (var i in d.despawn)
                if (_chunks.TryGetValue(i, out var t))
                {
                    _chunks.Remove(i);
                    // 유턴 뒤 이 조각을 되짚는 조각이 살아 있으면 물체를 넘겨준다 (다시 짓지 않는다)
                    var heir = -1;
                    foreach (var c in _track.Live.Values)
                        if (c.reuseOf == i && !_chunks.ContainsKey(c.index)) { heir = c.index; break; }
                    if (heir >= 0)
                    {
                        _chunks[heir] = t;
                        if (_foot.TryGetValue(i, out var f)) _foot[heir] = f;
                    }
                    else Drop(t);
                    _foot.Remove(i);
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
            Recheck(d.spawn, now);
        }

        /// 새로 놓인 조각의 도로가 이미 지은 조각의 길가 물체를 지나면 그 조각을 다시 짓는다 (차 바로 밑 조각은 튀어 보여 두고)
        void Recheck(List<ChunkInfo> spawned, bool now)
        {
            if (spawned.Count == 0 || _foot.Count == 0) return;
            var redo = new List<int>();
            foreach (var (idx, feet) in _foot)
            {
                if (!_track.Live.TryGetValue(idx, out var b) || b.kind == "tunnel") continue;
                if (b.start <= _track.Offset + 15 && b.End >= _track.Offset - 5) continue;
                foreach (var n in spawned)
                {
                    if (n.index == idx || n.reuseOf == idx || b.reuseOf == n.index) continue;
                    if (HitsRoad(feet, n)) { redo.Add(idx); break; }
                }
            }
            foreach (var idx in redo)
            {
                if (!_chunks.TryGetValue(idx, out var t)) continue;
                Drop(t);
                _chunks.Remove(idx);
                _foot.Remove(idx);
                var c = _track.Live[idx];
                if (now) Build(c); else _pending.Enqueue(c);
            }
        }

        bool HitsRoad(List<Bounds> feet, ChunkInfo n)
        {
            foreach (var (at, r) in ChunkBuilder.RoadRects(n, _track.ChunkLength))
            {
                var g = n.geom.Apply(at.pos, at.yaw);
                foreach (var f in feet)
                    if (Overlaps(f, g, r)) return true;
            }
            return false;
        }

        /// 트랙 공간 바닥 범위 f(xz)와 조각 로컬 직사각형 r 이 겹치는지 (모서리 포함 검사로 어림)
        static bool Overlaps(Bounds f, Pose2 g, Vector4 r)
        {
            var inv = Quaternion.Inverse(g.Rot);
            Vector3 Local(Vector3 p) => inv * (p - g.pos);
            bool InRect(Vector3 l) => l.x > r.x && l.x < r.y && l.z > r.z && l.z < r.w;
            var pts = new[] { f.center, new Vector3(f.min.x, 0, f.min.z), new Vector3(f.max.x, 0, f.min.z), new Vector3(f.min.x, 0, f.max.z), new Vector3(f.max.x, 0, f.max.z) };
            foreach (var p in pts) if (InRect(Local(new Vector3(p.x, 0, p.z)))) return true;
            foreach (var (x, z) in new[] { (r.x, r.z), (r.y, r.z), (r.x, r.w), (r.y, r.w) })
            {
                var w = g.pos + g.Rot * new Vector3(x, 0, z);
                if (w.x > f.min.x && w.x < f.max.x && w.z > f.min.z && w.z < f.max.z) return true;
            }
            return false;
        }

        /// 조각 로컬 위치가 휜 길(bend) 가운데에서 오른쪽으로 얼마나 떨어져 있는지
        static float Lateral(Vector3 lp, float bend, float L)
        {
            if (Mathf.Abs(bend) < 0.01f) return lp.x;
            var pose = ChunkTrack.LocalPose(null, lp.z, L, bend);
            pose = ChunkTrack.LocalPose(null, lp.z + Vector3.Dot(lp - pose.pos, pose.Forward), L, bend);
            return Vector3.Dot(lp - pose.pos, pose.Right);
        }

        /// 이 조각의 길가 물체 중 다른 조각의 도로 위에 놓인 것을 지우고, 남은 물체의 바닥 범위를 기억한다
        void ClearRoads(Transform chunk, ChunkInfo c)
        {
            var feet = new List<Bounds>();
            _foot[c.index] = feet;
            if (c.kind == "tunnel") return;
            var others = new List<(Pose2 g, Vector4 r)>();
            foreach (var o in _track.Live.Values)
            {
                if (o.index == c.index || o.reuseOf == c.index || c.reuseOf == o.index) continue;
                if (o.reuseOf >= 0 && c.reuseOf >= 0) continue; // 유턴 뒤 되짚는 조각끼리는 원래 이어진 길이다
                foreach (var (at, r) in ChunkBuilder.RoadRects(o, _track.ChunkLength)) others.Add((o.geom.Apply(at.pos, at.yaw), r));
            }
            // 자기 도로 띠 안(아스팔트·차선·맨홀)과 교차로가 직접 놓은 가로 도로·횡단보도·신호등은 검사하지 않는다
            var (bandL, bandR) = c.kind == "highway" ? (-10.0f, 4.8f) : (-6.0f, 3.2f);
            // 가까운(90m 안) 다른 조각에 이미 놓인 큰 물체(건물·나무)의 바닥 범위
            var bigOthers = new List<Bounds>();
            foreach (var (idx, feetOf) in _foot)
            {
                if (idx == c.index || !_track.Live.TryGetValue(idx, out var o)) continue;
                if (o.reuseOf == c.index || c.reuseOf == idx) continue;
                if ((o.geom.pos - c.geom.pos).sqrMagnitude > 90 * 90) continue;
                foreach (var f in feetOf)
                    if (f.size.x * f.size.z > 3) bigOthers.Add(f);
            }
            var items = new List<Transform>();
            void Collect(Transform p, bool scene)
            {
                foreach (Transform t in p)
                {
                    if (t.name == "Approach" || t.name.StartsWith("Ahead")) { Collect(t, true); continue; }
                    if (!scene) continue;
                    if (t.name == "Cube" && (t.localScale.x > 50 || t.localScale.z > 50)) continue; // 땅 띠
                    // 휜 조각은 휜 길 기준 좌우 거리로 본다
                    var x = scene && p == chunk ? Lateral(t.localPosition, c.bend, _track.ChunkLength) : t.localPosition.x;
                    if (x > bandL && x < bandR) continue;
                    items.Add(t);
                }
            }
            Collect(chunk, c.turn == null);
            foreach (var t in items)
            {
                var rs = t.GetComponentsInChildren<Renderer>();
                if (rs.Length == 0) continue;
                var wb = rs[0].bounds;
                foreach (var r in rs) wb.Encapsulate(r.bounds);
                var tb = new Bounds(_trackT.InverseTransformPoint(wb.center), Vector3.zero);
                for (var k = 0; k < 8; k++)
                    tb.Encapsulate(_trackT.InverseTransformPoint(new Vector3((k & 1) == 0 ? wb.min.x : wb.max.x, (k & 2) == 0 ? wb.min.y : wb.max.y, (k & 4) == 0 ? wb.min.z : wb.max.z)));
                var hit = false;
                foreach (var (g, r) in others)
                    if (Overlaps(tb, g, r)) { hit = true; break; }
                if (!hit && tb.size.x * tb.size.z > 3)
                    foreach (var o in bigOthers)
                        if (tb.min.x + 0.3f < o.max.x && tb.max.x - 0.3f > o.min.x && tb.min.z + 0.3f < o.max.z && tb.max.z - 0.3f > o.min.z) { hit = true; break; }
                if (hit) Remove(t.gameObject);
                else feet.Add(tb);
            }
        }

        void Build(ChunkInfo c)
        {
            if (!_track.Live.TryGetValue(c.index, out var live) || live != c) return; // 그사이 바뀐 조각
            if (_chunks.ContainsKey(c.index)) return;
            // 유턴 뒤 되짚는 조각: 지나온 조각이 아직 있으면 그 물체가 곧 이 조각이다
            if (c.reuseOf >= 0 && _chunks.ContainsKey(c.reuseOf)) return;
            var t = new GameObject($"Chunk_{c.index}_{c.kind}{(c.turn != null ? "_" + c.turn : "")}").transform;
            t.SetParent(_trackT, false);
            t.localPosition = c.geom.pos;
            t.localRotation = c.geom.Rot;
            var sw = System.Diagnostics.Stopwatch.StartNew();
            // 회전 안쪽을 비우지 않는다. 지나온 조각과 겹치는 큰 물체는 ClearRoads 가 뺀다
            ChunkBuilder.Build(_kit, t, c, _track.ChunkLength, _windows);
            var tb = sw.ElapsedMilliseconds;
            ClearRoads(t, c);
            var tc = sw.ElapsedMilliseconds - tb;
            if (sw.ElapsedMilliseconds > 80) Debug.Log($"[World] slow build {c.index} {c.kind} turn={c.turn} bend={c.bend:F1} build={tb}ms clear={tc}ms kids={t.childCount}");
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
            var tunnel = _inTunnel;
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
            // 마주 오는 차: 왼쪽 차로로 경로를 거슬러 다가와 스쳐 지나간다. 다음 교차로 너머에서는 나오지 않는다
            _trafficTimer -= Time.deltaTime;
            var now = _track.Offset;
            if (_trafficTimer <= 0 && _scene.moving)
            {
                _trafficTimer = Random.Range(2.5f, 7f);
                var d = Mathf.Min(now + 320, _track.NextTurnStart(now) - 5);
                if (d > now + 40)
                {
                    var t = new GameObject("Oncoming").transform;
                    t.SetParent(_traffic, false);
                    _kit.Car(t, Vector3.zero, C(new[] { "#E9E4DA", "#7FA6C9", "#C8654F", "#59615E", "#F2C14E", "#3F7D5A" }[Random.Range(0, 6)]), true, Random.Range(0, 9));
                    _cars.Add(new Car { t = t, d = d, speed = Random.Range(40f, 80f) / 3.6f, x = _scene.highway ? -7 : -3.5f });
                }
            }
            for (var i = _cars.Count - 1; i >= 0; i--)
            {
                var car = _cars[i];
                if (car.t == null) { _cars.RemoveAt(i); continue; }
                car.d -= car.speed * Time.deltaTime;
                if (car.d < now - 55 || _scene.kind == "tunnel" && car.d - now > 140)
                {
                    Kill(car.t.gameObject);
                    _cars.RemoveAt(i);
                    continue;
                }
                var pose = _track.PoseAt(car.d);
                car.t.localPosition = pose.pos + pose.Right * car.x;
                car.t.localRotation = Quaternion.Euler(0, pose.yaw + 180, 0);
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
