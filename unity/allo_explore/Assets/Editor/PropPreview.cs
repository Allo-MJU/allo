using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

/// 프리팹 몇 개를 빈 장면에 세워 PNG 로 찍는다 (에셋 확인용).
///   Unity -batchmode -quit -projectPath unity/allo_explore -executeMethod PropPreview.Run
///   대상: 환경변수 ALLO_PREVIEW = "K_tree_palm,K_tree_palmShort" , 결과: ALLO_PREVIEW_OUT (기본 /tmp/prop_preview.png)
public static class PropPreview
{
    public static void Run()
    {
        EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects);
        var names = (System.Environment.GetEnvironmentVariable("ALLO_PREVIEW") ?? "K_tree_palm").Split(',');
        var x = 0f;
        foreach (var n in names)
        {
            var src = AssetDatabase.LoadAssetAtPath<GameObject>($"Assets/Models/ThirdParty/{n.Trim()}.prefab");
            if (src == null) { Debug.Log($"[PropPreview] missing {n}"); continue; }
            var go = Object.Instantiate(src);
            go.transform.position = new Vector3(x, 0, 0);
            go.transform.localScale = Vector3.one * 4;
            x += 5;
        }
        var cam = Camera.main;
        cam.transform.position = new Vector3((x - 5) / 2, 1.2f, -9);
        cam.transform.rotation = Quaternion.Euler(-12, 0, 0);
        cam.backgroundColor = new Color(0.6f, 0.75f, 0.9f);
        cam.clearFlags = CameraClearFlags.SolidColor;
        var rt = new RenderTexture(1200, 600, 24);
        cam.targetTexture = rt;
        cam.Render();
        RenderTexture.active = rt;
        var tex = new Texture2D(1200, 600, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, 1200, 600), 0, 0);
        File.WriteAllBytes(System.Environment.GetEnvironmentVariable("ALLO_PREVIEW_OUT") ?? "/tmp/prop_preview.png", tex.EncodeToPNG());
    }
}
