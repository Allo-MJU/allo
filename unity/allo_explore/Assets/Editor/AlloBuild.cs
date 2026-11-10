using System.Linq;
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using Allo.Bridge;
using UnityEngine;

/// 명령줄에서 부르는 장면 생성·Android 내보내기.
///   Unity -batchmode -quit -projectPath unity/allo_explore -executeMethod AlloBuild.CreateSpikeScene
///   Unity -batchmode -quit -projectPath unity/allo_explore -executeMethod AlloBuild.ExportAndroid
public static class AlloBuild
{
    const string ScenePath = "Assets/Scenes/Explore.unity";

    /// 차 내부 장면: Blender 로 만든 Cabin.fbx + 둘러보기 카메라 + FlutterBridge.
    /// 창밖(3D 풍경)은 다음 단계에서 붙인다. 지금은 하늘과 땅만 둔다.
    public static void CreateExploreScene()
    {
        // Blender 는 색을 linear 로 내보낸다. gamma 공간이면 모든 색이 어둡게 나온다
        PlayerSettings.colorSpace = ColorSpace.Linear;
        AssetDatabase.DeleteAsset("Assets/Models/CabinMaterials"); // 변환본을 먼저 지워야 FBX 가 이름으로 잘못 찾지 않는다
        AssetDatabase.DeleteAsset("Assets/Models/Materials"); // 예전 실행이 덮어쓴 원본 재질을 버리고
        AssetDatabase.ImportAsset("Assets/Models/Cabin.fbx", ImportAssetOptions.ForceUpdate); // FBX 에서 다시 읽는다
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var model = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Models/Cabin.fbx");
        if (model == null) throw new System.Exception("Assets/Models/Cabin.fbx 가 없습니다 (tools/blender/cabin.py --fbx)");
        var cabin = (GameObject)PrefabUtility.InstantiatePrefab(model);
        cabin.name = "Cabin";

        // FBX 재질을 광택을 조절한 Standard 재질 복사본으로 바꿔 끼운다 (Assets/Models/CabinMaterials)
        // Unity 가 FBX 원본 재질을 푸는 Materials 폴더와 겹치지 않게 다른 폴더에 둔다 (두 번 변환 방지)
        var matDir = "Assets/Models/CabinMaterials";
        AssetDatabase.CreateFolder("Assets/Models", "CabinMaterials");
        _fabric = null;
        var converted = new System.Collections.Generic.Dictionary<Material, Material>();
        foreach (var r in cabin.GetComponentsInChildren<Renderer>(true))
        {
            var mats = r.sharedMaterials;
            for (var i = 0; i < mats.Length; i++)
            {
                var src = mats[i];
                if (src == null) continue;
                if (!converted.TryGetValue(src, out var dst))
                {
                    dst = new Material(Shader.Find("Allo/Toon")) { name = "Cabin_" + src.name };
                    dst.SetFloat("_OutlineWidth", 0.004f);
                    // 차 안은 바깥보다 어둡다 (창밖이 밝게 보이게). 그림자는 따뜻한 갈색 쪽
                    dst.SetColor("_ShadowTint", new Color(0.52f, 0.47f, 0.5f));
                    dst.SetFloat("_RimStrength", 0.06f);
                    dst.SetFloat("_RampSoft", 0.1f);
                    var c = src.color;
                    // Linear 프로젝트에서 Material.color 는 이미 sRGB 값을 준다. 그대로 옮긴다
                    dst.color = new Color(c.r * 0.78f, c.g * 0.76f, c.b * 0.74f, 1);
                    // 질감: 좌석은 천, 문·대시보드는 가죽·플라스틱 결, 천장은 부드러운 펠트
                    var hex = src.name.Replace("M_", "").Split('_')[0];
                    var (tex, tile, gloss) = hex switch
                    {
                        "6E5C50" or "5A4A40" => (Fabric(), 3.5f, 0.05f),
                        "7A6553" or "5E4C3F" or "4A3D34" => (Grain(13, 0.07f), 4f, 0.2f),
                        "3E3631" or "4A403A" => (Grain(29, 0.05f), 8f, 0.25f),
                        "E4DACB" or "D8CBB7" or "B9AA96" => (Grain(41, 0.04f), 10f, 0.02f),
                        _ => (null, 1f, 0.35f),
                    };
                    if (tex != null)
                    {
                        dst.mainTexture = tex;
                        dst.mainTextureScale = new Vector2(tile, tile);
                    }
                    dst.SetFloat("_Glossiness", gloss);

                    AssetDatabase.CreateAsset(dst, $"{matDir}/Cabin_{src.name}.mat");
                    converted[src] = dst;
                }
                mats[i] = dst;
            }
            r.sharedMaterials = mats;
        }

        // 유리: 옅은 색 + 비 오면 빗방울 (Allo/Glass)
        var glassMat = new Material(Shader.Find("Allo/Glass")) { color = new Color(0.66f, 0.86f, 0.85f, 0.12f) };
        AssetDatabase.CreateAsset(glassMat, "Assets/Models/Glass.mat");
        foreach (var r in cabin.GetComponentsInChildren<Renderer>(true))
        {
            if (r.name.StartsWith("Walk_")) { r.enabled = false; continue; } // 걷는 면: 위치만 쓰고 보이지 않는다
            // 탭할 수 있는 물체 (TapInput): 유리는 빗방울, 나머지는 흔들림
            if (r.name.StartsWith("Glass_")) { r.sharedMaterial = glassMat; Tappable(r, null); }
            else if (r.name.StartsWith("Headrest") || r.name.StartsWith("RearHeadrest")) Tappable(r, (5, 0.04f));
            else if (r.name.StartsWith("Plush") || r.name.StartsWith("Cushion") || r.name.StartsWith("Bottle")) Tappable(r, (14, 0.12f));
            else if (r.name.StartsWith("GrabHandle")) Tappable(r, (18, 0.02f));
            else if (r.name.StartsWith("DomeLight") || r.name.StartsWith("Armrest")) Tappable(r, (3, 0.03f));
        }

        // 앞좌석 머리받침을 끝까지 내린다: 뒷좌석 가운데 아이 눈에 앞유리가 보이게 (천장이 낮아 눈을 더 올릴 수 없다)
        foreach (var t in cabin.GetComponentsInChildren<Transform>())
            if (t.name.StartsWith("Headrest_F") || t.name.StartsWith("HeadrestPost_F")) t.position += Vector3.down * 0.1f;
        Bounds B(string name) => Find(cabin.transform, name).GetComponent<Renderer>().bounds;
        var rear = B("RearSeat");
        var seatL = B("Seat_FL");
        var seatR = B("Seat_FR");
        var eyeY = rear.max.y + 0.45f;  // 뒷좌석 아이 눈높이 (옆 창 밖이 넓게 보이게)
        // 아이는 뒷좌석 가운데 가까이 앉는다 (머리받침 사이로 앞유리가 보이게). 양옆 자리와 팔걸이에서 캐릭터가 논다
        var rearAnchor = new GameObject("RearEye").transform;
        rearAnchor.position = new Vector3(rear.center.x - rear.size.x * 0.12f, eyeY, rear.center.z);
        var frontAnchor = new GameObject("FrontEye").transform;
        var between = (seatL.center + seatR.center) / 2 + (rear.center - (seatL.center + seatR.center) / 2) * 0.35f;
        frontAnchor.position = new Vector3(between.x, eyeY + 0.05f, between.z);

        var camGo = new GameObject("Main Camera") { tag = "MainCamera" };
        var cam = camGo.AddComponent<Camera>();
        cam.fieldOfView = 72;
        cam.nearClipPlane = 0.02f;
        cam.farClipPlane = 800;
        var rig = camGo.AddComponent<Allo.CameraRig.CameraRig>();
        rig.rearAnchor = rearAnchor;
        rig.frontAnchor = frontAnchor;
        rig.lookTarget = Find(cabin.transform, "Dashboard");
        camGo.transform.position = rearAnchor.position;
        camGo.transform.LookAt(rig.lookTarget);

        var sunGo = new GameObject("Sun");
        var sun = sunGo.AddComponent<Light>();
        sun.type = LightType.Directional;
        sun.intensity = 1.1f;
        sun.color = new Color(1f, 0.96f, 0.88f);
        sun.shadows = LightShadows.Hard;
        sunGo.transform.rotation = Quaternion.Euler(50, -30, 0);
        var fillGo = new GameObject("CabinFill");
        var fill = fillGo.AddComponent<Light>();
        fill.type = LightType.Point;
        fill.range = 3f;
        fill.intensity = 0.9f;
        fill.color = new Color(1f, 0.95f, 0.86f);
        fillGo.transform.position = (rearAnchor.position + frontAnchor.position) / 2 + Vector3.up * 0.25f;
        RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
        RenderSettings.ambientSkyColor = new Color(0.62f, 0.74f, 0.86f);
        RenderSettings.ambientEquatorColor = new Color(0.62f, 0.58f, 0.52f);
        RenderSettings.ambientGroundColor = new Color(0.3f, 0.27f, 0.24f);

        // 창밖 3D: 재질은 에셋으로 만들어 앱 빌드에 셰이더 변형이 빠지지 않게 한다
        var solid = new Material(Shader.Find("Allo/Toon")) { enableInstancing = true };
        solid.SetFloat("_OutlineWidth", 0.02f);
        solid.SetFloat("_OutlineDist", 0.1f);
        AssetDatabase.CreateAsset(solid, "Assets/Models/WorldSolid.mat");
        var glow = new Material(Shader.Find("Standard"));
        glow.EnableKeyword("_EMISSION");
        glow.SetColor("_EmissionColor", Color.white);
        glow.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
        AssetDatabase.CreateAsset(glow, "Assets/Models/WorldGlow.mat");
        var winTex = Allo.World.WorldDirector.WindowTexture();
        AssetDatabase.CreateAsset(winTex, "Assets/Models/WindowTex.asset");
        var windows = new Material(Shader.Find("Standard")) { mainTexture = winTex, mainTextureScale = new Vector2(1, 1) };
        windows.SetFloat("_Mode", 1);
        windows.SetFloat("_Cutoff", 0.5f);
        windows.EnableKeyword("_ALPHATEST_ON");
        windows.renderQueue = 2450;
        windows.SetOverrideTag("RenderType", "TransparentCutout");
        windows.EnableKeyword("_EMISSION");
        windows.SetTexture("_EmissionMap", winTex);
        windows.SetColor("_EmissionColor", Color.black);
        windows.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
        AssetDatabase.CreateAsset(windows, "Assets/Models/WorldWindows.mat");
        var wallGlass = new Material(Shader.Find("Legacy Shaders/Transparent/Diffuse")) { color = new Color(0.72f, 0.83f, 0.84f, 0.45f) };
        AssetDatabase.CreateAsset(wallGlass, "Assets/Models/SoundWall.mat");
        var rainShader = Shader.Find("Particles/Standard Unlit") ?? Shader.Find("Legacy Shaders/Particles/Alpha Blended");
        var rainMat = new Material(rainShader);
        rainMat.SetFloat("_Mode", 2);
        rainMat.EnableKeyword("_ALPHABLEND_ON");
        rainMat.renderQueue = 3000;
        AssetDatabase.CreateAsset(rainMat, "Assets/Models/Rain.mat");
        var skyMat = new Material(Shader.Find("Allo/SkyGradient"));
        var groundTex = GroundTexture();
        AssetDatabase.CreateAsset(groundTex, "Assets/Models/GroundTex.asset");
        var groundMat = new Material(Shader.Find("Allo/Toon")) { mainTexture = groundTex };
        groundMat.SetFloat("_WorldUV", 0.18f);
        groundMat.SetFloat("_RimStrength", 0);
        AssetDatabase.CreateAsset(groundMat, "Assets/Models/WorldGround.mat");
        AssetDatabase.CreateAsset(skyMat, "Assets/Models/Sky.mat");
        RenderSettings.skybox = skyMat;
        cam.clearFlags = CameraClearFlags.Skybox;
        cam.farClipPlane = 900;
        // 후처리 (블룸·색감). 재질을 에셋으로 두어 셰이더가 빌드에 들어가게 한다
        var postMat = new Material(Shader.Find("Hidden/Allo/Post"));
        AssetDatabase.CreateAsset(postMat, "Assets/Models/Post.mat");
        var post = camGo.AddComponent<Allo.AlloPost>();
        post.material = postMat;
        var floorY = Find(cabin.transform, "Shell").GetComponent<Renderer>().bounds.min.y; // Shell 이 바닥판이다 (cabin.py shell())
        var world = new GameObject("World").AddComponent<Allo.World.WorldDirector>();
        // 차체 축: 뒷좌석 가운데 → 앞좌석 사이
        var carAxis = between - rear.center;
        carAxis.y = 0;
        world.carCenter = (rear.center + between) / 2;
        world.forward = carAxis.normalized;
        world.roadY = floorY - 0.3f;
        world.solid = solid;
        world.glow = glow;
        world.windows = windows;
        world.glass = wallGlass;
        world.rain = rainMat;
        world.sky = skyMat;
        world.ground = groundMat;
        world.sun = sun;
        world.post = post;
        world.cabinGlass = glassMat;
        world.wipers = MakeWipers(cabin.transform, carAxis, rear.center);
        (world.props, world.propGlows) = BuildProps(glow);
        world.props = world.props.Concat(BuildThirdParty()).ToArray();

        new GameObject("FlutterBridge").AddComponent<FlutterBridge>();

        // 캐릭터: 투명 그림 재질(빛을 조금 받는다) + 발밑 그림자
        var critterMat = new Material(Shader.Find("Legacy Shaders/Transparent/Cutout/Diffuse"));
        critterMat.SetFloat("_Cutoff", 0.5f);
        AssetDatabase.CreateAsset(critterMat, "Assets/Models/Critter.mat");
        var shadowTex = new Texture2D(64, 64, TextureFormat.RGBA32, false);
        for (var y = 0; y < 64; y++)
        for (var x = 0; x < 64; x++)
        {
            var d = new Vector2(x - 31.5f, y - 31.5f).magnitude / 32f;
            shadowTex.SetPixel(x, y, new Color(0, 0, 0, Mathf.Clamp01(1 - d) * 0.45f));
        }
        shadowTex.Apply();
        AssetDatabase.CreateAsset(shadowTex, "Assets/Models/CritterShadow.asset");
        var shadowMat = new Material(Shader.Find("Legacy Shaders/Transparent/Diffuse")) { mainTexture = shadowTex };
        AssetDatabase.CreateAsset(shadowMat, "Assets/Models/CritterShadow.mat");
        var director = new GameObject("Critters").AddComponent<Allo.Critters.CritterDirector>();
        director.cabin = cabin.transform;
        director.childEye = rearAnchor;
        director.Bake();
        director.critterMaterial = critterMat;
        director.shadowMaterial = shadowMat;
        world.sprite = critterMat;

        // 화면 안 버튼(돌아가기·주행 종료·먹이·봤어!)과 탭 입력
        var hud = new GameObject("Hud").AddComponent<Allo.Hud>();
        hud.cam = cam;
        hud.critters = director;
        hud.world = world;
        var tap = camGo.AddComponent<Allo.TapInput>();
        tap.critters = director;
        tap.world = world;
        tap.cabinLight = fill;

        EditorSceneManager.SaveScene(scene, ScenePath);
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
        AssetDatabase.SaveAssets();
        Debug.Log($"[AlloBuild] scene saved. rear={rearAnchor.position} front={frontAnchor.position} dash={rig.lookTarget.position}");
    }

    /// 장면을 열어 카메라를 앞·왼쪽·뒤·오른쪽으로 돌려 PNG 로 찍는다 (빌드 없이 배치 확인).
    ///   Unity -batchmode -quit -projectPath unity/allo_explore -executeMethod AlloBuild.CaptureViews
    public static void CaptureViews()
    {
        EditorSceneManager.OpenScene(ScenePath);
        var cam = Camera.main;
        var rig = cam.GetComponent<Allo.CameraRig.CameraRig>();
        var dir = rig.lookTarget.position - rig.rearAnchor.position;
        var baseYaw = Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg;
        var outDir = Path.GetFullPath(Path.Combine(Application.dataPath, "../../../docs/work-results/explore"));
        Directory.CreateDirectory(outDir);
        // 캐릭터 3마리를 걷는 면 위에 세워 둔다 (Play 없이 확인)
        var dir2 = Object.FindFirstObjectByType<Allo.Critters.CritterDirector>();
        var graph = dir2.BuildGraph();
        var views = new System.Collections.Generic.List<Allo.Critters.CritterView>();
        var spots = new[] { ("Walk_RearSeat_L", "water"), ("Walk_RearSeat_R", "water"), ("Walk_Armrest", "normal"), ("Walk_Dashboard", "dark"), ("Walk_DoorSill_L", "water") };
        for (var k = 0; k < spots.Length; k++)
        {
            var idx = graph.IndexOf(spots[k].Item1);
            if (idx < 0) continue;
            var go = new GameObject("CaptureCritter" + k);
            var v = go.AddComponent<Allo.Critters.CritterView>();
            v.Init("c" + k, new Allo.Critters.CritterBrain(graph, idx, 11 + k), Allo.Critters.PlaceholderFace.Make(spots[k].Item2, k + 1), dir2.critterMaterial, dir2.shadowMaterial);
            views.Add(v);
        }
        var rt = new RenderTexture(1600, 720, 24);
        cam.targetTexture = rt;
        var shots = new (string name, float yaw, float pitch, float rail)[]
        {
            ("unity_front", 0, -12, 0), ("unity_left", -90, -10, 0), ("unity_back", 180, 5, 0),
            ("unity_right", 90, -20, 0), ("unity_front_rail", 0, -15, 1), ("unity_down", 60, -30, 0),
        };
        foreach (var (name, yaw, pitch, rail) in shots)
        {
            cam.transform.position = Vector3.Lerp(rig.rearAnchor.position, rig.frontAnchor.position, rail);
            cam.transform.rotation = Quaternion.Euler(-pitch, baseYaw + yaw, 0);
            foreach (var v in views) v.Pose(cam, 0.3f);
            cam.Render();
            RenderTexture.active = rt;
            var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
            tex.Apply();
            File.WriteAllBytes(Path.Combine(outDir, name + ".png"), tex.EncodeToPNG());
        }
        cam.targetTexture = null;
        RenderTexture.active = null;
        Debug.Log($"[AlloBuild] captured views to {outDir}");
    }

    /// 장면마다 창밖을 만들어 앞·옆을 찍는다 (빌드 없이 확인)
    ///   Unity -batchmode -quit -projectPath unity/allo_explore -executeMethod AlloBuild.CaptureWorld
    public static void CaptureWorld()
    {
        EditorSceneManager.OpenScene(ScenePath);
        var cam = Camera.main;
        var rig = cam.GetComponent<Allo.CameraRig.CameraRig>();
        var world = Object.FindFirstObjectByType<Allo.World.WorldDirector>();
        var dir = rig.lookTarget.position - rig.rearAnchor.position;
        var baseYaw = Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg;
        var outDir = Path.GetFullPath(Path.Combine(Application.dataPath, "../../../docs/work-results/explore"));
        var rt = new RenderTexture(1600, 720, 24);
        cam.targetTexture = rt;
        var cabinGo = GameObject.Find("Cabin"); // 숨기면 Find 로 다시 못 찾으니 한 번만 찾는다
        var scenes = new (string name, Allo.Bridge.SceneState s)[]
        {
            ("road", new Allo.Bridge.SceneState { kind = "road", moving = true, speedKph = 60 }),
            ("coast", new Allo.Bridge.SceneState { kind = "coast", moving = true, speedKph = 60 }),
            ("mountain", new Allo.Bridge.SceneState { kind = "mountain", moving = true, speedKph = 60 }),
            ("city", new Allo.Bridge.SceneState { kind = "city", moving = true, speedKph = 40 }),
            ("city_night", new Allo.Bridge.SceneState { kind = "city", night = true, moving = true, speedKph = 40 }),
            ("highway_rain", new Allo.Bridge.SceneState { kind = "road", highway = true, rain = 3, moving = true, speedKph = 90 }),
            ("tunnel", new Allo.Bridge.SceneState { kind = "tunnel", moving = true, speedKph = 60 }),
        };
        foreach (var (name, s) in scenes)
        {
            world.Apply(s, reset: true);
            var named = Object.FindObjectsByType<Transform>(FindObjectsSortMode.None).Where(t => t.name.StartsWith("Animal_")).GroupBy(t => t.name).Select(g => $"{g.Key}×{g.Count()}");
            Debug.Log($"[AlloBuild] {name} animals: {string.Join(", ", named)}");
            // 들판: 목장이 오른쪽 창 앞(6~12m)에 올 때까지 달려서 옆 창을 찍는다
            if (name == "road")
                for (var k = 0; k < 20; k++)
                {
                    var near = Object.FindObjectsByType<Transform>(FindObjectsSortMode.None).Count(t => t.name.StartsWith("Animal_")
                        && Vector3.Distance(t.position, rig.rearAnchor.position) < 16 && Vector3.Dot(t.position - rig.rearAnchor.position, Quaternion.Euler(0, baseYaw + 70, 0) * Vector3.forward) > 3);
                    if (near >= 2)
                    {
                        if (cabinGo != null) cabinGo.SetActive(true);
                        cam.transform.position = rig.rearAnchor.position;
                        cam.transform.rotation = Quaternion.Euler(0, baseYaw + 70, 0);
                        cam.Render();
                        RenderTexture.active = rt;
                        var pt = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
                        pt.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
                        pt.Apply();
                        File.WriteAllBytes(Path.Combine(outDir, "world_road_pasture_side.png"), pt.EncodeToPNG());
                        Debug.Log($"[AlloBuild] pasture after {k * 15}m, animals near={near}");
                        break;
                    }
                    world.EditorStep(15);
                }
            // 동물 가까이에서 한 장 (모양·색 확인용)
            var pet = Object.FindObjectsByType<Transform>(FindObjectsSortMode.None).Where(t => t.name.StartsWith("Animal_")).OrderBy(t => t.position.sqrMagnitude).FirstOrDefault();
            if (pet != null)
            {
                if (cabinGo != null) cabinGo.SetActive(false);
                var b = pet.GetComponentInChildren<Renderer>().bounds;
                cam.transform.position = b.center + new Vector3(-1, 0.5f, -1).normalized * Mathf.Max(2.5f, b.size.magnitude * 2.2f);
                cam.transform.LookAt(b.center);
                cam.Render();
                RenderTexture.active = rt;
                var ptex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
                ptex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
                ptex.Apply();
                File.WriteAllBytes(Path.Combine(outDir, $"world_{name}_animal.png"), ptex.EncodeToPNG());
                if (cabinGo != null) cabinGo.SetActive(true);
            }
            // 도시는 차 실내를 숨기고 건물이 다 보이게 올려다본 사진도 찍는다 (에셋·셰이더 비교용)
            var views = name.StartsWith("city") ? new[] { ("front", 0f, 2f), ("side", 70f, 0f), ("out_right", 80f, 18f), ("out_left", -80f, 18f), ("out_ahead", 0f, 10f) } : new[] { ("front", 0f, 2f), ("side", 70f, 0f) };
            foreach (var (view, yaw, pitch) in views)
            {
                if (cabinGo != null) cabinGo.SetActive(!view.StartsWith("out"));
                cam.transform.position = rig.rearAnchor.position;
                cam.transform.rotation = Quaternion.Euler(-pitch, baseYaw + yaw, 0);
                cam.Render();
                RenderTexture.active = rt;
                var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
                tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
                tex.Apply();
                File.WriteAllBytes(Path.Combine(outDir, $"world_{name}_{view}.png"), tex.EncodeToPNG());
            }
        }
        cam.targetTexture = null;
        RenderTexture.active = null;
        Debug.Log($"[AlloBuild] captured world to {outDir}");
    }

    /// 체험 투어를 에디터에서 흉내 내 단계별 시간을 잰다 (멈춤·느려짐 찾기). 가짜 피드와 같은 경로·장면 순서
    public static void SimTour()
    {
        EditorSceneManager.OpenScene(ScenePath);
        var world = Object.FindFirstObjectByType<Allo.World.WorldDirector>();
        var kinds = new[] { ("road", false), ("coast", false), ("mountain", false), ("city", false), ("tunnel", false), ("city", false), ("road", true) };
        var route = new (string t, float at)[] { ("right", 220), ("left", 560), ("uturn", 900), ("keepRight", 1200), ("left", 1500) };
        const float loop = 1800;
        float road = 0, prevScene = -1;
        var sw = new System.Diagnostics.Stopwatch();
        world.Apply(new Allo.Bridge.SceneState { kind = "road", moving = true, speedKph = 70 }, reset: true);
        for (var sec = 0; sec < 110; sec++)
        {
            var stage = (sec / 15) % kinds.Length;
            if (stage != prevScene)
            {
                prevScene = stage;
                world.Apply(new Allo.Bridge.SceneState { kind = kinds[stage].Item1, highway = kinds[stage].Item2, moving = true, speedKph = 70 });
            }
            var turns = new System.Collections.Generic.List<Allo.Bridge.TurnInfo>();
            var lap = Mathf.FloorToInt(road / loop);
            for (var l = lap; l <= lap + 1 && turns.Count < 3; l++)
                foreach (var (t, at) in route)
                {
                    var inM = l * loop + at - road;
                    if (inM >= 0 && turns.Count < 3) turns.Add(new Allo.Bridge.TurnInfo { type = t, inM = Mathf.Round(inM) });
                }
            var heading = (12 * Mathf.Sin(2 * Mathf.PI * road / 700) + 3600) % 360;
            sw.Restart();
            world.OnRoute(new Allo.Bridge.RouteState { turns = turns.ToArray(), heading = heading });
            var tRoute = sw.ElapsedMilliseconds;
            sw.Restart();
            // 1초를 20 프레임으로 나눠 달린다 (Unity 쪽 감속은 EditorStep 이 하지 않으므로 70km/h 그대로)
            for (var f = 0; f < 20; f++) world.EditorStep(70 / 3.6f / 20);
            var tStep = sw.ElapsedMilliseconds;
            road += 70 / 3.6f;
            if (tRoute + tStep > 300 || sec % 10 == 0) Debug.Log($"[Sim] t={sec}s road={road:F0} route={tRoute}ms steps={tStep}ms scene={kinds[stage].Item1}");
        }
        Debug.Log("[Sim] done");
    }

    /// 회전 하나를 차 안에서 0.5초마다 찍는다 (감속·도는 모습이 자연스러운지). ALLO_STRIP=right|left|uturn, 결과는 scratch 폴더
    public static void CaptureTurnStrip()
    {
        EditorSceneManager.OpenScene(ScenePath);
        var turn = System.Environment.GetEnvironmentVariable("ALLO_STRIP") ?? "right";
        var outDir = System.Environment.GetEnvironmentVariable("ALLO_STRIP_OUT") ?? "/tmp";
        Directory.CreateDirectory(outDir);
        var cam = Camera.main;
        var rig = cam.GetComponent<Allo.CameraRig.CameraRig>();
        var world = Object.FindFirstObjectByType<Allo.World.WorldDirector>();
        var dir = rig.lookTarget.position - rig.rearAnchor.position;
        var baseYaw = Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg;
        var rt = new RenderTexture(800, 360, 24);
        cam.targetTexture = rt;
        world.Apply(new Allo.Bridge.SceneState { kind = "city", moving = true, speedKph = 70 }, reset: true);
        world.OnRoute(new Allo.Bridge.RouteState { turns = new[] { new Allo.Bridge.TurnInfo { type = turn, inM = 150 } } });
        float kph = 70;
        for (var i = 0; i < 40; i++)
        {
            // 0.5초 = 10 프레임. WorldDirector 와 같은 규칙으로 속도를 바꾼다
            for (var f = 0; f < 10; f++)
            {
                var target = Mathf.Min(70, world.SpeedCapNow);
                kph = Mathf.MoveTowards(kph, target, (target > kph ? 2f : 3f) * 3.6f * 0.05f);
                world.EditorStep(kph / 3.6f * 0.05f);
            }
            cam.transform.position = rig.rearAnchor.position;
            cam.transform.rotation = Quaternion.Euler(-2, baseYaw + 25, 0);
            cam.Render();
            RenderTexture.active = rt;
            var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
            tex.Apply();
            File.WriteAllBytes(Path.Combine(outDir, $"f_{i * 0.5f:000.0}.jpg"), tex.EncodeToJPG(70));
            Debug.Log($"[Strip] {i * 0.5f:F1}s kph={kph:F0} travelled={world.Travelled:F0}");
        }
        cam.targetTexture = null;
        RenderTexture.active = null;
    }

    /// 회전·유턴 확인 사진: 교차로 앞(40m), 도는 중, 돈 뒤 30m 에서 앞·옆을 찍는다
    public static void CaptureTurns()
    {
        EditorSceneManager.OpenScene(ScenePath);
        var cam = Camera.main;
        var rig = cam.GetComponent<Allo.CameraRig.CameraRig>();
        var world = Object.FindFirstObjectByType<Allo.World.WorldDirector>();
        var dir = rig.lookTarget.position - rig.rearAnchor.position;
        var baseYaw = Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg;
        var outDir = Path.GetFullPath(Path.Combine(Application.dataPath, "../../../docs/work-results/explore"));
        var rt = new RenderTexture(1600, 720, 24);
        cam.targetTexture = rt;
        void Shot(string file, float yaw, float pitch)
        {
            cam.transform.position = rig.rearAnchor.position;
            cam.transform.rotation = Quaternion.Euler(-pitch, baseYaw + yaw, 0);
            cam.Render();
            RenderTexture.active = rt;
            var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
            tex.Apply();
            File.WriteAllBytes(Path.Combine(outDir, file), tex.EncodeToPNG());
        }
        // late: 경로가 늦게 바뀌어 교차로 자리가 60m 당겨진 경우 (이미 지은 조각과 겹치는지)
        var cases = new (string kind, string turn, bool late)[] { ("road", "right", false), ("road", "left", false), ("road", "uturn", false), ("city", "right", false), ("city", "left", false), ("city", "right", true), ("city", "left", true), ("highway", "keepRight", false), ("road", "keepLeft", false), ("road", "steer", false) };
        foreach (var (kind0, turn, late) in cases)
        {
            var kind = kind0;
            world.Apply(new Allo.Bridge.SceneState { kind = kind, moving = true, speedKph = 40 }, reset: true);
            if (turn == "steer")
            {
                // 차가 오른쪽으로 20도 꺾었다고 알려 준다 (처음 방향 0도)
                world.OnRoute(new Allo.Bridge.RouteState { turns = new Allo.Bridge.TurnInfo[0], heading = 0 });
                world.OnRoute(new Allo.Bridge.RouteState { turns = new Allo.Bridge.TurnInfo[0], heading = 20 });
            }
            else world.OnRoute(new Allo.Bridge.RouteState { turns = new[] { new Allo.Bridge.TurnInfo { type = turn, inM = 160 } } });
            if (late)
            {
                world.EditorStep(20);
                world.OnRoute(new Allo.Bridge.RouteState { turns = new[] { new Allo.Bridge.TurnInfo { type = turn, inM = 80 } } });
                kind += "_late";
            }
            var start = world.NextFeatureStart;
            if (float.IsInfinity(start)) { Debug.LogWarning($"[AlloBuild] {kind}/{turn}: 교차로가 놓이지 않았다"); continue; }
            var len = turn.StartsWith("keep") ? 60 : turn == "steer" ? 30 : Allo.World.ChunkTrack.TurnLength(turn);
            var stops = new (string tag, float at)[] { ("before", start - 40), ("mid", start + len * 0.5f), ("after", start + len + 30) };
            foreach (var (tag, at) in stops)
            {
                world.EditorStep(at - world.Travelled);
                Shot($"turn_{kind}_{turn}_{tag}_front.png", 0, 2);
                Shot($"turn_{kind}_{turn}_{tag}_side.png", 70, 0);
                var cabin = GameObject.Find("Cabin");
                if (cabin != null) cabin.SetActive(false);
                Shot($"turn_{kind}_{turn}_{tag}_out.png", 30, -25);
                if (tag == "before")
                {
                    // 위에서 내려다본 교차로 (도로 위에 건물·나무가 걸치는지)
                    cam.transform.position = rig.rearAnchor.position + Vector3.up * 70 + Quaternion.Euler(0, baseYaw, 0) * Vector3.forward * 45;
                    cam.transform.rotation = Quaternion.Euler(90, baseYaw, 0);
                    cam.Render();
                    RenderTexture.active = rt;
                    var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
                    tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
                    tex.Apply();
                    File.WriteAllBytes(Path.Combine(outDir, $"turn_{kind}_{turn}_top.png"), tex.EncodeToPNG());
                }
                if (cabin != null) cabin.SetActive(true);
            }
        }
        cam.targetTexture = null;
        RenderTexture.active = null;
        Debug.Log($"[AlloBuild] captured turns to {outDir}");
    }

    /// Props.fbx 의 물체마다 프리팹을 만든다. 재질은 Standard 로 바꾸고, Glow_ 재질은 빛나게 한다
    static (GameObject[], Material[]) BuildProps(Material glowBase)
    {
        const string fbx = "Assets/Models/Props.fbx";
        // 조각을 합칠 때(WorldDirector.Combine) 메시를 읽어야 한다. 기기 빌드에서는 Read/Write 를 켜 둔 메시만 읽힌다
        if (AssetImporter.GetAtPath(fbx) is ModelImporter importer && !importer.isReadable)
        {
            importer.isReadable = true;
            importer.SaveAndReimport();
        }
        var src = AssetDatabase.LoadAssetAtPath<GameObject>(fbx);
        if (src == null) return (new GameObject[0], new Material[0]);
        AssetDatabase.DeleteAsset("Assets/Models/Props");
        AssetDatabase.CreateFolder("Assets/Models", "Props");
        var converted = new System.Collections.Generic.Dictionary<string, Material>();
        var glows = new System.Collections.Generic.List<Material>();
        var prefabs = new System.Collections.Generic.List<GameObject>();
        foreach (Transform child in src.transform)
        {
            var go = Object.Instantiate(child.gameObject);
            go.name = child.name;
            go.transform.position = Vector3.zero;
            foreach (var r in go.GetComponentsInChildren<Renderer>())
            {
                var mats = r.sharedMaterials;
                for (var i = 0; i < mats.Length; i++)
                {
                    var m = mats[i];
                    if (m == null) continue;
                    if (!converted.TryGetValue(m.name, out var dst))
                    {
                        var isGlow = m.name.StartsWith("Glow_");
                        dst = isGlow ? new Material(glowBase) : new Material(Shader.Find("Allo/Toon"));
                        if (!isGlow)
                        {
                            dst.SetFloat("_OutlineWidth", m.name.StartsWith("Cloud") ? 0 : m.name.StartsWith("Grass") || m.name.StartsWith("Petal") ? 0 : 0.025f);
                            dst.SetFloat("_OutlineDist", 0.1f);
                        }
                        dst.name = "Prop_" + m.name;
                        dst.color = new Color(m.color.r, m.color.g, m.color.b, 1);
                        dst.enableInstancing = true;
                        if (isGlow)
                        {
                            dst.EnableKeyword("_EMISSION");
                            dst.SetColor("_EmissionColor", dst.color);
                            glows.Add(dst);
                        }
                        else if (m.name.StartsWith("Cloud"))
                        {
                            // 구름: 그림자 2단 또렷하게 + 윗면 하이라이트 한 단
                            dst.SetColor("_ShadowTint", new Color(0.74f, 0.8f, 0.96f));
                            dst.SetFloat("_RimStrength", 0.5f);
                            dst.SetFloat("_RampSoft", 0.02f);
                            dst.SetFloat("_HiSize", 0.5f);
                            dst.SetFloat("_HiStrength", 0.45f);
                        }
                        else if (m.name.StartsWith("Car") || m.name.StartsWith("Chrome") || m.name.StartsWith("Bus")) { dst.SetFloat("_HiSize", 0.14f); dst.SetFloat("_HiStrength", 0.7f); }
                        else if (m.name.StartsWith("Glass")) { dst.SetFloat("_HiSize", 0.25f); dst.SetFloat("_HiStrength", 0.8f); }
                        AssetDatabase.CreateAsset(dst, $"Assets/Models/Props/Prop_{m.name}.mat");
                        converted[m.name] = dst;
                    }
                    mats[i] = dst;
                }
                r.sharedMaterials = mats;
            }
            prefabs.Add(PrefabUtility.SaveAsPrefabAsset(go, $"Assets/Models/Props/{go.name}.prefab"));
            Object.DestroyImmediate(go);
        }
        return (prefabs.ToArray(), glows.ToArray());
    }

    /// 외부 무료 에셋(Assets/ThirdParty, Kenney CC0 등)의 FBX 마다 프리팹 "K_파일명" 을 만든다.
    /// 바닥 가운데를 원점으로, 높이를 1m 로 맞춰서 Kit.Prop 의 scale 이 곧 높이(m)가 되게 한다.
    /// 재질은 Allo/Toon 으로 바꾸고(색·텍스처 유지), 이름과 텍스처가 같은 재질은 하나로 묶는다(조각 합치기 때 배칭)
    static GameObject[] BuildThirdParty()
    {
        const string outDir = "Assets/Models/ThirdParty";
        AssetDatabase.DeleteAsset(outDir);
        AssetDatabase.CreateFolder("Assets/Models", "ThirdParty");
        var converted = new System.Collections.Generic.Dictionary<string, Material>();
        var prefabs = new System.Collections.Generic.List<GameObject>();
        // Kenney (CC0): FBX, 높이 1m 로 맞춘다
        if (AssetDatabase.IsValidFolder("Assets/ThirdParty"))
            foreach (var guid in AssetDatabase.FindAssets("t:Model", new[] { "Assets/ThirdParty" }))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                if (path.Contains("/Quaternius/")) continue; // 동물은 BuildAnimals 가 애니메이션을 살려 따로 만든다
                MakeReadable(path);
                var p = MakeThirdParty(AssetDatabase.LoadAssetAtPath<GameObject>(path), "K_" + Path.GetFileNameWithoutExtension(path), true, false, outDir, converted);
                if (p != null) prefabs.Add(p);
            }
        // ithappy Cartoon City FREE (Asset Store EULA): 프리팹, 원래 크기(m) 그대로. 밤 조명판(NightLight)·바퀴 조각은 뺀다.
        // ALLO_CC_ORIGINAL=1 이면 원래 재질(Standard)을 그대로 쓴다 (툰 셰이더와 비교용)
        const string cc = "Assets/ithappy/Cartoon_City_Free";
        if (AssetDatabase.IsValidFolder(cc))
        {
            foreach (var guid in AssetDatabase.FindAssets("t:Model", new[] { cc + "/Meshes" })) MakeReadable(AssetDatabase.GUIDToAssetPath(guid));
            var keep = System.Environment.GetEnvironmentVariable("ALLO_CC_ORIGINAL") == "1";
            foreach (var folder in new[] { "Buildings", "Props", "Vegetation", "Billboards" })
                foreach (var guid in AssetDatabase.FindAssets("t:Prefab", new[] { $"{cc}/Prefabs/{folder}" }))
                {
                    var path = AssetDatabase.GUIDToAssetPath(guid);
                    var name = Path.GetFileNameWithoutExtension(path);
                    if (name.Contains("NightLight") || name.Contains("Wheel")) continue;
                    var p = MakeThirdParty(AssetDatabase.LoadAssetAtPath<GameObject>(path), "C_" + name, false, keep, outDir, converted);
                    if (p != null) prefabs.Add(p);
                }
        }
        prefabs.AddRange(BuildAnimals(outDir, converted));
        Debug.Log($"[AlloBuild] third-party props: {prefabs.Count}, materials: {converted.Count}");
        return prefabs.ToArray();
    }

    /// 동물 실제 높이(m). 프리팹 이름은 A_이름
    static readonly (string name, float height)[] AnimalHeights =
    {
        ("Horse", 1.6f), ("Deer", 1.3f), ("Dog", 0.6f), ("Kitty", 0.32f), ("Chicken", 0.4f), ("Pinguin", 0.6f), ("Tiger", 1.0f),
        ("Cow", 1.4f), ("Sheep", 0.9f), ("Pig", 0.7f), ("Llama", 1.8f), ("Pug", 0.35f), ("Zebra", 1.5f),
    };

    /// 동물: ithappy Animals FREE(Asset Store EULA, 프리팹·Animator 포함)와 Quaternius Farm Animals(CC0, FBX).
    /// 걷기·서 있기 애니메이션을 살리고(메시 합치기 대상이 아닌 SkinnedMesh), 재질만 Allo/Toon 으로 바꾼다
    static System.Collections.Generic.List<GameObject> BuildAnimals(string outDir, System.Collections.Generic.Dictionary<string, Material> converted)
    {
        var list = new System.Collections.Generic.List<GameObject>();
        const string ih = "Assets/ithappy/Animals_FREE/Prefabs";
        if (AssetDatabase.IsValidFolder(ih))
            foreach (var guid in AssetDatabase.FindAssets("t:Prefab", new[] { ih }))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                var name = Path.GetFileNameWithoutExtension(path).Split('_')[0];
                var p = MakeAnimal(AssetDatabase.LoadAssetAtPath<GameObject>(path), name, null, outDir, converted);
                if (p != null) list.Add(p);
            }
        const string q = "Assets/ThirdParty/Quaternius/FarmAnimals";
        if (AssetDatabase.IsValidFolder(q))
            foreach (var guid in AssetDatabase.FindAssets("t:Model", new[] { q }))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                var name = Path.GetFileNameWithoutExtension(path);
                if (list.Any(a => a.name == "A_" + name)) continue; // 같은 종(말)은 ithappy 것을 쓴다
                if (AssetImporter.GetAtPath(path) is ModelImporter imp && (imp.animationType != ModelImporterAnimationType.Generic || !imp.importAnimation))
                {
                    imp.animationType = ModelImporterAnimationType.Generic;
                    imp.importAnimation = true;
                    imp.SaveAndReimport();
                }
                var clips = AssetDatabase.LoadAllAssetsAtPath(path).OfType<AnimationClip>().Where(c => !c.name.StartsWith("__preview")).ToArray();
                // 서 있기 > 천천히 걷기. (이름에 eat 이 든 Death 를 고르지 않게 이름 끝으로 찾는다)
                var clip = clips.FirstOrDefault(c => c.name.EndsWith("|Idle")) ?? clips.FirstOrDefault(c => c.name.EndsWith("|WalkSlow")) ?? clips.FirstOrDefault(c => !c.name.Contains("Death"));
                Debug.Log($"[AlloBuild] {name} clips: {string.Join(", ", clips.Select(c => c.name))} → {clip?.name}");
                RuntimeAnimatorController ctrl = null;
                if (clip != null)
                {
                    var settings = AnimationUtility.GetAnimationClipSettings(clip);
                    if (!settings.loopTime) { settings.loopTime = true; AnimationUtility.SetAnimationClipSettings(clip, settings); }
                    ctrl = UnityEditor.Animations.AnimatorController.CreateAnimatorControllerAtPathWithClip($"{outDir}/A_{name}.controller", clip);
                }
                var p = MakeAnimal(AssetDatabase.LoadAssetAtPath<GameObject>(path), name, ctrl, outDir, converted);
                if (p != null) list.Add(p);
            }
        Debug.Log($"[AlloBuild] animals: {string.Join(", ", list.Select(a => a.name))}");
        return list;
    }

    static GameObject MakeAnimal(GameObject src, string name, RuntimeAnimatorController ctrl, string outDir,
        System.Collections.Generic.Dictionary<string, Material> converted)
    {
        if (src == null) return null;
        var h = AnimalHeights.FirstOrDefault(a => a.name == name).height;
        if (h <= 0) return null;
        var model = Object.Instantiate(src);
        model.transform.position = Vector3.zero;
        model.transform.rotation = Quaternion.identity;
        // 키보드·카메라로 움직이게 하는 팩 스크립트는 뗀다 (Animator 기본 상태가 서 있기)
        foreach (var mb in model.GetComponentsInChildren<MonoBehaviour>(true)) Object.DestroyImmediate(mb);
        foreach (var cc in model.GetComponentsInChildren<CharacterController>(true)) Object.DestroyImmediate(cc);
        foreach (var rb in model.GetComponentsInChildren<Rigidbody>(true)) Object.DestroyImmediate(rb);
        foreach (var col in model.GetComponentsInChildren<Collider>(true)) Object.DestroyImmediate(col);
        var anim = model.GetComponentInChildren<Animator>();
        if (anim == null && ctrl != null) anim = model.AddComponent<Animator>();
        if (anim != null)
        {
            if (ctrl != null) anim.runtimeAnimatorController = ctrl;
            anim.applyRootMotion = false;
            anim.cullingMode = AnimatorCullingMode.CullCompletely; // 안 보이면 계산하지 않는다
        }
        var rs = model.GetComponentsInChildren<Renderer>();
        if (rs.Length == 0) { Object.DestroyImmediate(model); return null; }
        var b = rs[0].bounds;
        foreach (var r in rs) b.Encapsulate(r.bounds);
        var root = new GameObject("A_" + name);
        var s = h / Mathf.Max(0.01f, b.size.y);
        model.transform.SetParent(root.transform, false);
        model.transform.localScale *= s;
        model.transform.localPosition = new Vector3(-b.center.x, -b.min.y, -b.center.z) * s;
        foreach (var r in rs)
        {
            if (r is SkinnedMeshRenderer smr) smr.updateWhenOffscreen = false;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            var mats = r.sharedMaterials;
            for (var i = 0; i < mats.Length; i++)
            {
                var m = mats[i];
                if (m == null) continue;
                var tex = m.HasProperty("_MainTex") ? m.mainTexture : m.HasProperty("_BaseMap") ? m.GetTexture("_BaseMap") : null;
                var col = m.HasProperty("_BaseColor") ? m.GetColor("_BaseColor") : m.color;
                var key = "animal|" + m.name + "|" + (tex != null ? AssetDatabase.GetAssetPath(tex) : ColorUtility.ToHtmlStringRGB(col));
                if (!converted.TryGetValue(key, out var dst))
                {
                    dst = new Material(Shader.Find("Allo/Toon")) { name = "T_" + m.name };
                    dst.color = tex != null ? Color.white : new Color(col.r, col.g, col.b, 1);
                    if (tex != null) dst.mainTexture = tex;
                    dst.SetFloat("_OutlineWidth", 0.02f);
                    dst.SetFloat("_OutlineDist", 0.1f);
                    AssetDatabase.CreateAsset(dst, $"{outDir}/T_{converted.Count:000}_{Sanitize(m.name)}.mat");
                    converted[key] = dst;
                }
                mats[i] = dst;
            }
            r.sharedMaterials = mats;
        }
        var prefab = PrefabUtility.SaveAsPrefabAsset(root, $"{outDir}/A_{name}.prefab");
        Debug.Log($"[AlloBuild] A_{name} size={b.size * s}");
        Object.DestroyImmediate(root);
        return prefab;
    }

    static void MakeReadable(string path)
    {
        if (AssetImporter.GetAtPath(path) is ModelImporter imp && (!imp.isReadable || imp.importAnimation))
        {
            imp.isReadable = true; // 조각 합치기(WorldDirector.Combine)에서 메시를 읽는다
            imp.importAnimation = false;
            imp.SaveAndReimport();
        }
    }

    /// 바닥 가운데를 원점으로 옮긴 프리팹을 만든다. unitHeight 면 높이 1m 로 맞춘다.
    /// keepMats 가 아니면 재질을 Allo/Toon 으로 바꾼다(색·텍스처 유지, 이름·텍스처가 같으면 하나로 묶어 배칭)
    static GameObject MakeThirdParty(GameObject src, string name, bool unitHeight, bool keepMats, string outDir,
        System.Collections.Generic.Dictionary<string, Material> converted)
    {
        if (src == null) return null;
        var model = Object.Instantiate(src);
        model.transform.position = Vector3.zero;
        model.transform.rotation = Quaternion.identity;
        var rs = model.GetComponentsInChildren<Renderer>();
        if (rs.Length == 0 || rs[0].bounds.size.y <= 0) { Object.DestroyImmediate(model); return null; }
        var b = rs[0].bounds;
        foreach (var r in rs) b.Encapsulate(r.bounds);
        var root = new GameObject(name);
        var s = unitHeight ? 1f / b.size.y : 1f;
        model.transform.SetParent(root.transform, false);
        model.transform.localScale *= s;
        model.transform.localPosition = new Vector3(-b.center.x, -b.min.y, -b.center.z) * s;
        foreach (var lod in model.GetComponentsInChildren<LODGroup>()) Object.DestroyImmediate(lod);
        if (!keepMats)
            foreach (var r in rs)
            {
                var mats = r.sharedMaterials;
                for (var i = 0; i < mats.Length; i++)
                {
                    var m = mats[i];
                    if (m == null) continue;
                    var tex = m.HasProperty("_MainTex") ? m.mainTexture : null;
                    // 팩마다 텍스처 이름이 같아(colormap) 경로로 구분한다. 텍스처가 없으면 색까지 본다
                    var key = m.name + "|" + (tex != null ? AssetDatabase.GetAssetPath(tex) : ColorUtility.ToHtmlStringRGB(m.color));
                    if (!converted.TryGetValue(key, out var dst))
                    {
                        dst = new Material(Shader.Find("Allo/Toon")) { name = "T_" + m.name, enableInstancing = true };
                        dst.color = KenneyPalette.TryGetValue(m.name, out var hex) && ColorUtility.TryParseHtmlString(hex, out var pc)
                            ? pc : new Color(m.color.r, m.color.g, m.color.b, 1);
                        if (tex != null) dst.mainTexture = tex;
                        var thin = m.name.Contains("grass") || m.name.Contains("flower") || m.name.Contains("petal");
                        dst.SetFloat("_OutlineWidth", thin ? 0 : 0.025f);
                        dst.SetFloat("_OutlineDist", 0.1f);
                        if (m.name.ToLower().Contains("leaf")) dst.SetFloat("_Cull", 0); // 야자수 잎처럼 얇은 판은 아래에서도 보이게
                        AssetDatabase.CreateAsset(dst, $"{outDir}/T_{converted.Count:000}_{Sanitize(m.name)}.mat");
                        converted[key] = dst;
                    }
                    mats[i] = dst;
                }
                r.sharedMaterials = mats;
            }
        var prefab = PrefabUtility.SaveAsPrefabAsset(root, $"{outDir}/{name}.prefab");
        if (name.StartsWith("C_")) Debug.Log($"[AlloBuild] {name} size={b.size}");
        Object.DestroyImmediate(root);
        return prefab;
    }

    /// Kenney Nature Kit 기본색(청록 잎·분홍 줄기)을 창밖 팔레트(ChunkBuilder 의 풀색·Blender 나무)에 맞춘다
    static readonly System.Collections.Generic.Dictionary<string, string> KenneyPalette = new()
    {
        ["leafsGreen"] = "#5FA845", ["leafsDark"] = "#3F7D3A", ["grass"] = "#6CB847",
        ["wood"] = "#7A5A40", ["woodBark"] = "#6B4A35", ["woodBarkDark"] = "#5B4434", ["woodDark"] = "#5B4434",
        ["woodInner"] = "#D9B98A", ["dirt"] = "#8A6A4C", ["colorTan"] = "#E8C89A", ["stone"] = "#B9B6AC", ["stoneDark"] = "#8F8C84",
    };

    static string Sanitize(string s)
    {
        foreach (var c in Path.GetInvalidFileNameChars()) s = s.Replace(c, '_');
        return s.Replace(' ', '_');
    }

    /// 땅 무늬: 풀잎 같은 짧은 획과 얼룩. 흰색 기준이라 재질 색(풀·모래·아스팔트)이 곱해진다
    static Texture2D GroundTexture()
    {
        const int n = 256;
        var t = new Texture2D(n, n, TextureFormat.RGB24, true) { wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 8 };
        var px = new Color[n * n];
        for (var y = 0; y < n; y++)
        for (var x = 0; x < n; x++)
        {
            var v = 0.92f + (Mathf.PerlinNoise(x * 0.02f, y * 0.02f) - 0.5f) * 0.16f + (Mathf.PerlinNoise(x * 0.11f + 7, y * 0.11f) - 0.5f) * 0.08f;
            px[y * n + x] = new Color(v, v, v);
        }
        var rng = new System.Random(9);
        for (var k = 0; k < 2600; k++)
        {
            int x0 = rng.Next(n), y0 = rng.Next(n), len = 3 + rng.Next(5);
            var bright = rng.NextDouble() < 0.5 ? 1.12f : 0.8f;
            for (var j = 0; j < len; j++)
            {
                var i = ((y0 + j) % n) * n + (x0 + j / 3) % n;
                px[i] = px[i] * bright;
            }
        }
        t.SetPixels(px);
        t.Apply();
        return t;
    }

    static Texture2D _fabric;

    /// 좌석 천: 가는 씨실·날실 무늬 + 큰 얼룩 + 드문 올 자국. 색은 재질 색에 곱해진다 (흰색 = 그대로).
    /// 256px 한 장을 3.5번만 반복해 같은 무늬가 눈에 띄게 되풀이되지 않는다
    static Texture2D Fabric()
    {
        if (_fabric != null) return _fabric;
        const int n = 256;
        var t = new Texture2D(n, n, TextureFormat.RGB24, true) { wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 4 };
        var rng = new System.Random(3);
        var px = new Color[n * n];
        for (var y = 0; y < n; y++)
        for (var x = 0; x < n; x++)
        {
            var weave = ((x / 2 + y / 2) % 2 == 0 ? 0.05f : -0.035f) + (x % 2 == 0 ? 0.015f : 0) + (y % 2 == 0 ? 0.015f : 0);
            // 큰 얼룩 두 겹 (타일 경계가 안 보이게 주기를 타일에 맞춘다: 좌표를 원 위로 보낸다)
            var ax = x / (float)n * Mathf.PI * 2; var ay = y / (float)n * Mathf.PI * 2;
            var blot = Mathf.PerlinNoise(3 + Mathf.Cos(ax) * 1.2f + Mathf.Sin(ay) * 0.7f, 7 + Mathf.Sin(ax) * 1.2f + Mathf.Cos(ay) * 0.7f) * 0.09f
                     + Mathf.PerlinNoise(11 + Mathf.Cos(ax) * 3.1f, 13 + Mathf.Sin(ay) * 3.1f) * 0.04f;
            var v = 0.88f + weave + blot + (float)rng.NextDouble() * 0.025f;
            px[y * n + x] = new Color(v, v, v);
        }
        // 올 자국: 가로로 짧게 밝거나 어두운 줄
        for (var k = 0; k < 90; k++)
        {
            int x0 = rng.Next(n), y0 = rng.Next(n), len = 6 + rng.Next(18);
            var d = rng.NextDouble() < 0.5 ? 0.05f : -0.05f;
            for (var j = 0; j < len; j++)
            {
                var i = y0 * n + (x0 + j) % n;
                px[i] = new Color(px[i].r + d, px[i].g + d, px[i].b + d);
            }
        }
        t.SetPixels(px);
        t.Apply();
        AssetDatabase.CreateAsset(t, "Assets/Models/CabinMaterials/Fabric.asset");
        return _fabric = t;
    }

    /// 가죽·플라스틱 결: 잔 얼룩 노이즈
    static Texture2D Grain(int seed, float amount)
    {
        const int n = 128;
        var t = new Texture2D(n, n, TextureFormat.RGB24, true) { wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear };
        var rng = new System.Random(seed);
        for (var y = 0; y < n; y++)
        for (var x = 0; x < n; x++)
        {
            var v = 1 - amount + Mathf.PerlinNoise(x * 0.12f + seed, y * 0.12f) * amount + (float)rng.NextDouble() * amount * 0.6f;
            t.SetPixel(x, y, new Color(v, v, v));
        }
        t.Apply();
        AssetDatabase.CreateAsset(t, $"Assets/Models/CabinMaterials/Grain{seed}.asset");
        return t;
    }

    /// 탭할 수 있는 물체: 메시 크기만 한 상자 충돌체 (+ 흔들림)
    static void Tappable(Renderer r, (float angle, float scale)? wobble)
    {
        var mf = r.GetComponent<MeshFilter>();
        if (mf == null || mf.sharedMesh == null) return;
        var b = mf.sharedMesh.bounds;
        var col = r.gameObject.AddComponent<BoxCollider>();
        col.center = b.center;
        col.size = Vector3.Max(b.size, Vector3.one * 0.03f);
        if (wobble.HasValue)
        {
            var w = r.gameObject.AddComponent<Allo.Wobble>();
            w.angle = wobble.Value.angle;
            w.scale = wobble.Value.scale;
        }
    }

    /// 앞유리 아래 가장자리에 와이퍼 두 개. 유리 평면의 기울기는 바운드(높이·깊이)에서 읽는다.
    /// 날개 pivot 의 로컬 +y 는 유리면을 따라 위, +z 는 유리 바깥쪽 법선 (Wipers 가 z 축으로 돌린다)
    static Allo.World.Wipers MakeWipers(Transform cabin, Vector3 carAxis, Vector3 cabinCenter)
    {
        var glassT = Find(cabin, "Glass_Front");
        var glass = glassT != null ? glassT.GetComponent<Renderer>() : null;
        if (glass == null) return null;
        var b = glass.bounds;
        var f = carAxis.normalized;
        var right = Vector3.Cross(Vector3.up, f);
        var depth = Mathf.Abs(Vector3.Dot(b.size, f));
        var bottom = b.center - Vector3.up * b.size.y / 2 - f * depth / 2; // 아래 가장자리는 차 안쪽
        var along = (Vector3.up * b.size.y + f * depth).normalized;      // 유리면을 따라 위로
        var normal = Vector3.Cross(right, along).normalized;
        if (Vector3.Dot(normal, b.center - cabinCenter) < 0) normal = -normal; // 바깥쪽
        var root = new GameObject("Wipers");
        root.transform.SetParent(cabin, true);
        var w = root.AddComponent<Allo.World.Wipers>();
        var dark = new Material(Shader.Find("Allo/Toon")) { color = new Color(0.12f, 0.12f, 0.13f) };
        AssetDatabase.CreateAsset(dark, "Assets/Models/Wiper.mat");
        Transform Blade(string name, float side)
        {
            var baseT = new GameObject(name + "Base").transform;
            baseT.SetParent(root.transform, true);
            baseT.position = bottom + right * side * 0.34f + normal * 0.012f + along * 0.04f;
            baseT.rotation = Quaternion.LookRotation(normal, along);
            var pivot = new GameObject(name).transform;
            pivot.SetParent(baseT, false);
            foreach (var (len, wid, off) in new[] { (0.46f, 0.016f, 0f), (0.5f, 0.03f, 0.012f) })
            {
                var part = GameObject.CreatePrimitive(PrimitiveType.Cube).transform;
                Object.DestroyImmediate(part.GetComponent<Collider>());
                part.SetParent(pivot, false);
                part.localPosition = new Vector3(0, len / 2, off);
                part.localScale = new Vector3(wid, len, 0.01f);
                var r = part.GetComponent<Renderer>();
                r.sharedMaterial = dark;
                r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            }
            return pivot;
        }
        w.left = Blade("WiperL", -1);
        w.right = Blade("WiperR", 1);
        w.Pose(0);
        return w;
    }

    static Transform Find(Transform root, string name)
    {
        if (root.name == name) return root;
        foreach (Transform c in root)
        {
            var f = Find(c, name);
            if (f != null) return f;
        }
        return null;
    }

    public static void ExportAndroid()
    {
        var root = Path.GetFullPath(Path.Combine(Application.dataPath, "../../../phone/unity/export"));
        if (Directory.Exists(root)) Directory.Delete(root, true);

        EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android);
        EditorUserBuildSettings.exportAsGoogleAndroidProject = true;
        PlayerSettings.SetScriptingBackend(BuildTargetGroup.Android, ScriptingImplementation.IL2CPP);
        PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
        PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel24;
        // GameActivity 에서는 예전 입력(Input.touches)이 들어오지 않아 일반 Activity 로 띄운다
        PlayerSettings.Android.applicationEntry = AndroidApplicationEntry.Activity;
        PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
        PlayerSettings.allowedAutorotateToPortrait = false;
        PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
        PlayerSettings.allowedAutorotateToLandscapeLeft = true;
        PlayerSettings.allowedAutorotateToLandscapeRight = true;
        PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.Android, "ai.allo.explore");

        var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
        {
            scenes = new[] { ScenePath },
            locationPathName = root,
            target = BuildTarget.Android,
            options = BuildOptions.None,
        });
        if (report.summary.result != UnityEditor.Build.Reporting.BuildResult.Succeeded)
        {
            Debug.LogError($"[AlloBuild] export failed: {report.summary.result}");
            EditorApplication.Exit(1);
        }
        Debug.Log($"[AlloBuild] exported to {root}");
    }
}
