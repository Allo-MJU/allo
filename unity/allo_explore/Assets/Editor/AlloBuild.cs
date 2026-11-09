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
                    dst = new Material(Shader.Find("Standard")) { name = "Cabin_" + src.name };
                    var c = src.color;
                    // Linear 프로젝트에서 Material.color 는 이미 sRGB 값을 준다. 그대로 옮긴다
                    dst.color = new Color(c.r, c.g, c.b, 1);
                    // 질감: 좌석은 천, 문·대시보드는 가죽·플라스틱 결, 천장은 부드러운 펠트
                    var hex = src.name.Replace("M_", "").Split('_')[0];
                    var (tex, tile, gloss) = hex switch
                    {
                        "6E5C50" or "5A4A40" => (Fabric(), 6f, 0.05f),
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

        foreach (var r in cabin.GetComponentsInChildren<Renderer>(true))
        {
            if (r.name.StartsWith("Walk_")) r.enabled = false; // 걷는 면: 위치만 쓰고 보이지 않는다
            else if (r.name.StartsWith("Glass_"))
            {
                var glass = new Material(Shader.Find("Legacy Shaders/Transparent/Diffuse"));
                glass.color = new Color(0.66f, 0.86f, 0.85f, 0.12f);
                r.sharedMaterial = glass;
            }
        }
        AssetDatabase.CreateAsset(new Material(Shader.Find("Legacy Shaders/Transparent/Diffuse")) { color = new Color(0.66f, 0.86f, 0.85f, 0.12f) }, "Assets/Models/Glass.mat");
        foreach (var r in cabin.GetComponentsInChildren<Renderer>(true))
            if (r.name.StartsWith("Glass_")) r.sharedMaterial = AssetDatabase.LoadAssetAtPath<Material>("Assets/Models/Glass.mat");

        Bounds B(string name) => Find(cabin.transform, name).GetComponent<Renderer>().bounds;
        var rear = B("RearSeat");
        var seatL = B("Seat_FL");
        var seatR = B("Seat_FR");
        var eyeY = rear.max.y + 0.55f;  // 카시트에 앉은 아이 눈높이
        // 아이는 뒷좌석 한쪽에 앉는다. 가운데·반대쪽 자리와 팔걸이에서 캐릭터가 논다
        var rearAnchor = new GameObject("RearEye").transform;
        rearAnchor.position = new Vector3(rear.center.x - rear.size.x * 0.3f, eyeY, rear.center.z);
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
        var solid = new Material(Shader.Find("Standard")) { enableInstancing = true };
        solid.SetFloat("_Glossiness", 0.15f);
        AssetDatabase.CreateAsset(solid, "Assets/Models/WorldSolid.mat");
        var glow = new Material(Shader.Find("Standard"));
        glow.EnableKeyword("_EMISSION");
        glow.SetColor("_EmissionColor", Color.white);
        glow.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
        AssetDatabase.CreateAsset(glow, "Assets/Models/WorldGlow.mat");
        var winTex = Allo.World.WorldDirector.WindowTexture();
        AssetDatabase.CreateAsset(winTex, "Assets/Models/WindowTex.asset");
        var windows = new Material(Shader.Find("Standard")) { mainTexture = winTex, mainTextureScale = new Vector2(3, 4) };
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
        var skyMat = new Material(Shader.Find("Skybox/Procedural"));
        AssetDatabase.CreateAsset(skyMat, "Assets/Models/Sky.mat");
        RenderSettings.skybox = skyMat;
        cam.clearFlags = CameraClearFlags.Skybox;
        cam.farClipPlane = 900;
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
        world.sun = sun;
        (world.props, world.propGlows) = BuildProps(glow);

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
            foreach (var (view, yaw, pitch) in new[] { ("front", 0f, 2f), ("side", 70f, 0f) })
            {
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

    /// Props.fbx 의 물체마다 프리팹을 만든다. 재질은 Standard 로 바꾸고, Glow_ 재질은 빛나게 한다
    static (GameObject[], Material[]) BuildProps(Material glowBase)
    {
        const string fbx = "Assets/Models/Props.fbx";
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
                        dst = isGlow ? new Material(glowBase) : new Material(Shader.Find("Standard"));
                        dst.name = "Prop_" + m.name;
                        dst.color = new Color(m.color.r, m.color.g, m.color.b, 1);
                        dst.enableInstancing = true;
                        if (isGlow)
                        {
                            dst.EnableKeyword("_EMISSION");
                            dst.SetColor("_EmissionColor", dst.color);
                            glows.Add(dst);
                        }
                        else dst.SetFloat("_Glossiness", m.name.StartsWith("Car") || m.name == "Glass" ? 0.55f : 0.12f);
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

    static Texture2D _fabric;

    /// 좌석 천: 가는 씨실·날실 무늬 + 얼룩. 색은 재질 색에 곱해진다 (흰색 = 그대로)
    static Texture2D Fabric()
    {
        if (_fabric != null) return _fabric;
        const int n = 128;
        var t = new Texture2D(n, n, TextureFormat.RGB24, true) { wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 4 };
        var rng = new System.Random(3);
        for (var y = 0; y < n; y++)
        for (var x = 0; x < n; x++)
        {
            var weave = ((x / 2 + y / 2) % 2 == 0 ? 0.06f : -0.04f) + (x % 2 == 0 ? 0.02f : 0) + (y % 2 == 0 ? 0.02f : 0);
            var blot = Mathf.PerlinNoise(x * 0.05f, y * 0.05f) * 0.08f;
            var v = 0.9f + weave + blot + (float)rng.NextDouble() * 0.03f;
            t.SetPixel(x, y, new Color(v, v, v));
        }
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
