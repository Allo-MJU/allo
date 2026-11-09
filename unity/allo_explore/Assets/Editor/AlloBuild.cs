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
                    dst.SetFloat("_Glossiness", 0.35f);
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
        sun.shadows = LightShadows.Soft;
        sunGo.transform.rotation = Quaternion.Euler(50, -30, 0);
        var fillGo = new GameObject("CabinFill");
        var fill = fillGo.AddComponent<Light>();
        fill.type = LightType.Point;
        fill.range = 3f;
        fill.intensity = 0.6f;
        fill.color = new Color(1f, 0.95f, 0.86f);
        fillGo.transform.position = (rearAnchor.position + frontAnchor.position) / 2 + Vector3.up * 0.25f;
        RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
        RenderSettings.ambientSkyColor = new Color(0.62f, 0.74f, 0.86f);
        RenderSettings.ambientEquatorColor = new Color(0.62f, 0.58f, 0.52f);
        RenderSettings.ambientGroundColor = new Color(0.3f, 0.27f, 0.24f);

        var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
        ground.name = "OutsideGround";
        ground.transform.position = new Vector3(0, -0.4f, 0);
        ground.transform.localScale = new Vector3(80, 1, 80);
        var gm = new Material(Shader.Find("Standard")) { color = new Color(0.55f, 0.75f, 0.4f) };
        AssetDatabase.CreateAsset(gm, "Assets/Models/Ground.mat");
        ground.GetComponent<Renderer>().sharedMaterial = gm;

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
        var list = new System.Collections.Generic.List<Allo.Critters.WalkSurface>();
        foreach (var r in dir2.cabin.GetComponentsInChildren<Renderer>(true))
            if (r.name.StartsWith("Walk_") && !Allo.Critters.CritterDirector.TooCloseToChild(r.name, r.bounds, dir2.childEye.position))
                list.Add(new Allo.Critters.WalkSurface(r.name, new Vector3(r.bounds.center.x, r.bounds.max.y, r.bounds.center.z), new Vector2(r.bounds.size.x, r.bounds.size.z)));
        var graph = new Allo.Critters.WalkGraph(list);
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
