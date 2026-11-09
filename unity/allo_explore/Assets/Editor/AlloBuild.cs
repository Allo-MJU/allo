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

    public static void CreateSpikeScene()
    {
        var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);
        var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
        cube.name = "SpikeCube";
        cube.transform.position = new Vector3(0, 1, 0);
        cube.AddComponent<Spin>();
        cube.AddComponent<SpikeSceneTint>();
        var bridge = new GameObject("FlutterBridge");
        bridge.AddComponent<FlutterBridge>();
        EditorSceneManager.SaveScene(scene, ScenePath);
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
        AssetDatabase.SaveAssets();
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
