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
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var model = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Models/Cabin.fbx");
        if (model == null) throw new System.Exception("Assets/Models/Cabin.fbx 가 없습니다 (tools/blender/cabin.py --fbx)");
        var cabin = (GameObject)PrefabUtility.InstantiatePrefab(model);
        cabin.name = "Cabin";

        // Blender 는 FBX 에 linear 색을 적는데 Unity 는 sRGB 로 읽어 모든 색이 어둡게 나온다.
        // 재질마다 색을 sRGB 로 바꾼 복사본을 만들어 끼운다 (Assets/Models/Materials)
        var matDir = "Assets/Models/Materials";
        if (!AssetDatabase.IsValidFolder(matDir)) AssetDatabase.CreateFolder("Assets/Models", "Materials");
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
                    dst = new Material(Shader.Find("Standard")) { name = src.name };
                    var c = src.color;
                    dst.color = new Color(c.r, c.g, c.b, 1).gamma;
                    dst.SetFloat("_Glossiness", 0.35f);
                    AssetDatabase.CreateAsset(dst, $"{matDir}/{src.name}.mat");
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
        var eyeY = rear.max.y + 0.6f;  // 카시트에 앉은 아이 눈높이
        var rearAnchor = new GameObject("RearEye").transform;
        rearAnchor.position = new Vector3(rear.center.x, eyeY, rear.center.z);
        var frontAnchor = new GameObject("FrontEye").transform;
        var between = (seatL.center + seatR.center) / 2;
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
        var rt = new RenderTexture(1600, 720, 24);
        cam.targetTexture = rt;
        var shots = new (string name, float yaw, float pitch, float rail)[]
        {
            ("unity_front", 0, -5, 0), ("unity_left", -90, -5, 0), ("unity_back", 180, 10, 0),
            ("unity_right", 90, -5, 0), ("unity_front_rail", 0, -15, 1),
        };
        foreach (var (name, yaw, pitch, rail) in shots)
        {
            cam.transform.position = Vector3.Lerp(rig.rearAnchor.position, rig.frontAnchor.position, rail);
            cam.transform.rotation = Quaternion.Euler(-pitch, baseYaw + yaw, 0);
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
