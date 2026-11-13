using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

/// 소품 3D 모델(Tripo FBX → tools/blender/character.py 로 실제 크기·발밑 원점까지 정리)을 프리팹으로 바꾼다.
///   원본: Assets/Props/Source/{ID}/{ID}.fbx (+ 텍스처). scripts/import_props.sh 가 복사한다
///   결과: Assets/Resources/Props/P_{ID}.prefab — 크기는 FBX 그대로(m), 원점도 그대로(대개 바닥 가운데, egg_top 은 금 높이)
///   Unity -batchmode -quit -projectPath unity/allo_explore -executeMethod PropImport.Run
/// 프리팹이 있으면 Toys.Make 가 도형 대신 쓰고, 장면 빌드(AlloBuild)가 차 안 인형·쿠션을 바꾼다
public static class PropImport
{
    const string SourceRoot = "Assets/Props/Source";
    const string MatRoot = "Assets/Props/Materials";
    public const string OutRoot = "Assets/Resources/Props";

    public static void Run()
    {
        if (!AssetDatabase.IsValidFolder(SourceRoot)) { Debug.Log("[Props] 원본 폴더가 없어요: " + SourceRoot); return; }
        Ensure(MatRoot);
        Ensure(OutRoot);
        foreach (var dir in AssetDatabase.GetSubFolders(SourceRoot))
        {
            var id = Path.GetFileName(dir);
            var fbx = AssetDatabase.FindAssets("t:Model", new[] { dir }).Select(AssetDatabase.GUIDToAssetPath).FirstOrDefault();
            if (fbx == null) { Debug.LogWarning($"[Props] {id}: FBX 가 없어요"); continue; }
            Prepare(fbx);
            var prefab = Make(id, AssetDatabase.LoadAssetAtPath<GameObject>(fbx));
            Debug.Log(prefab != null ? $"[Props] {id} → {AssetDatabase.GetAssetPath(prefab)}" : $"[Props] {id}: 실패");
        }
        AssetDatabase.SaveAssets();
    }

    static void Ensure(string path)
    {
        if (AssetDatabase.IsValidFolder(path)) return;
        Ensure(Path.GetDirectoryName(path).Replace('\\', '/'));
        AssetDatabase.CreateFolder(Path.GetDirectoryName(path).Replace('\\', '/'), Path.GetFileName(path));
    }

    /// 애니메이션·리그 없이 메시만, 크기는 파일 단위 그대로(Blender 에서 m 로 맞춰 둠)
    static void Prepare(string fbx)
    {
        var imp = (ModelImporter)AssetImporter.GetAtPath(fbx);
        var changed = false;
        if (imp.animationType != ModelImporterAnimationType.None) { imp.animationType = ModelImporterAnimationType.None; changed = true; }
        if (imp.importAnimation) { imp.importAnimation = false; changed = true; }
        if (imp.materialImportMode != ModelImporterMaterialImportMode.ImportStandard) { imp.materialImportMode = ModelImporterMaterialImportMode.ImportStandard; changed = true; }
        if (!Mathf.Approximately(imp.globalScale, 1)) { imp.globalScale = 1; changed = true; }
        if (changed) imp.SaveAndReimport();
    }

    static GameObject Make(string id, GameObject src)
    {
        if (src == null) return null;
        var root = new GameObject("P_" + id);
        var model = Object.Instantiate(src, root.transform, false);
        model.name = "Model";
        foreach (var c in model.GetComponentsInChildren<Component>(true))
            if (c is MonoBehaviour || c is Collider || c is Animator || c is Animation) Object.DestroyImmediate(c);
        var rs = model.GetComponentsInChildren<Renderer>();
        if (rs.Length == 0) { Object.DestroyImmediate(root); return null; }
        var k = 0;
        foreach (var r in rs)
        {
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            var mats = r.sharedMaterials;
            for (var i = 0; i < mats.Length; i++)
                if (mats[i] != null) mats[i] = CharacterImport.Toon(mats[i], $"{MatRoot}/{id}_{k++}.mat");
            r.sharedMaterials = mats;
        }
        var b = rs[0].bounds;
        foreach (var r in rs) b.Encapsulate(r.bounds);
        var prefab = PrefabUtility.SaveAsPrefabAsset(root, $"{OutRoot}/P_{id}.prefab");
        Debug.Log($"[Props] {id} size={b.size.ToString("F3")} min.y={b.min.y:F3} center=({b.center.x:F3}, {b.center.z:F3})");
        Object.DestroyImmediate(root);
        return prefab;
    }
}
