using System.Collections.Generic;
using System.IO;
using System.Linq;
using Allo.Critters;
using UnityEditor;
using UnityEngine;

/// 캐릭터 3D 모델(이미지→3D 서비스로 만든 FBX)을 게임용 프리팹으로 바꾼다.
///   원본: Assets/Characters/Source/{종 ID}/*.fbx (+ 텍스처). scripts/import_characters.sh 가 내려받은 폴더에서 복사한다
///   결과: Assets/Resources/Characters/C_{종 ID}.prefab (발밑 가운데 원점, 앞 +Z, 키 Tuning.height)
///   Unity -batchmode -quit -projectPath unity/allo_explore -executeMethod CharacterImport.Run
public static class CharacterImport
{
    const string SourceRoot = "Assets/Characters/Source";
    const string MatRoot = "Assets/Characters/Materials";
    const string OutRoot = "Assets/Resources/Characters";

    /// 종마다 손볼 값. yaw: 모델 앞이 +Z 가 되도록 돌릴 각도(도). height: 프리팹 키(m) — 실제 크기는 쓰는 곳에서 다시 맞춘다
    public static readonly Dictionary<string, (float yaw, float height)> Tuning = new()
    {
        ["road_sprout"] = (0, 0.3f),
        ["puddle_pip"] = (0, 0.3f),
        ["lamp_moth"] = (0, 0.3f),
        ["storm_lantern"] = (0, 0.3f),
        ["highway_comet"] = (0, 0.3f),
        ["sea_mist"] = (0, 0.3f),
    };

    public static void Run()
    {
        if (!AssetDatabase.IsValidFolder(SourceRoot)) { Debug.Log("[Characters] 원본 폴더가 없어요: " + SourceRoot); return; }
        Ensure(MatRoot);
        Ensure(OutRoot);
        foreach (var dir in AssetDatabase.GetSubFolders(SourceRoot))
        {
            var id = Path.GetFileName(dir);
            var fbx = AssetDatabase.FindAssets("t:Model", new[] { dir }).Select(AssetDatabase.GUIDToAssetPath).FirstOrDefault();
            if (fbx == null) { Debug.LogWarning($"[Characters] {id}: FBX 가 없어요"); continue; }
            Prepare(fbx, dir);
            var prefab = Make(id, AssetDatabase.LoadAssetAtPath<GameObject>(fbx));
            Debug.Log(prefab != null ? $"[Characters] {id} → {AssetDatabase.GetAssetPath(prefab)}" : $"[Characters] {id}: 실패");
        }
        AssetDatabase.SaveAssets();
    }

    static void Ensure(string path)
    {
        if (AssetDatabase.IsValidFolder(path)) return;
        Ensure(Path.GetDirectoryName(path).Replace('\\', '/'));
        AssetDatabase.CreateFolder(Path.GetDirectoryName(path).Replace('\\', '/'), Path.GetFileName(path));
    }

    /// 애니메이션·리그 없이 메시만, FBX 안에 묻힌 텍스처는 꺼내 둔다
    static void Prepare(string fbx, string dir)
    {
        var imp = (ModelImporter)AssetImporter.GetAtPath(fbx);
        var changed = false;
        if (imp.animationType != ModelImporterAnimationType.None) { imp.animationType = ModelImporterAnimationType.None; changed = true; }
        if (imp.importAnimation) { imp.importAnimation = false; changed = true; }
        if (imp.materialImportMode != ModelImporterMaterialImportMode.ImportStandard) { imp.materialImportMode = ModelImporterMaterialImportMode.ImportStandard; changed = true; }
        if (changed) imp.SaveAndReimport();
        var texDir = dir + "/Textures";
        if (!AssetDatabase.IsValidFolder(texDir) && imp.ExtractTextures(texDir)) AssetDatabase.Refresh();
    }

    public static GameObject Make(string id, GameObject src)
    {
        if (src == null) return null;
        var (yaw, height) = Tuning.TryGetValue(id, out var t) ? t : (0f, 0.3f);
        var model = Object.Instantiate(src);
        model.transform.SetPositionAndRotation(Vector3.zero, Quaternion.Euler(0, yaw, 0));
        foreach (var c in model.GetComponentsInChildren<Component>(true))
            if (c is MonoBehaviour || c is Collider || c is Animator || c is Animation) Object.DestroyImmediate(c);
        var rs = model.GetComponentsInChildren<Renderer>();
        if (rs.Length == 0) { Object.DestroyImmediate(model); return null; }
        var b = rs[0].bounds;
        foreach (var r in rs) b.Encapsulate(r.bounds);
        var s = height / Mathf.Max(0.001f, b.size.y);

        var root = new GameObject("C_" + id);
        var holder = new GameObject("Model").transform;
        holder.SetParent(root.transform, false);
        model.transform.SetParent(holder, true);
        holder.localScale = Vector3.one * s;
        holder.localPosition = new Vector3(-b.center.x, -b.min.y, -b.center.z) * s;
        var info = root.AddComponent<CharacterModel>();
        info.height = height;
        info.footprint = new Vector2(b.size.x, b.size.z) * s;

        var converted = new Dictionary<Material, Material>();
        foreach (var r in rs)
        {
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            if (r is SkinnedMeshRenderer smr) smr.updateWhenOffscreen = false;
            var mats = r.sharedMaterials;
            for (var i = 0; i < mats.Length; i++)
            {
                var m = mats[i];
                if (m == null) continue;
                if (!converted.TryGetValue(m, out var dst))
                {
                    dst = Toon(m, $"{MatRoot}/{id}_{converted.Count}.mat");
                    converted[m] = dst;
                }
                mats[i] = dst;
            }
            r.sharedMaterials = mats;
        }
        var prefab = PrefabUtility.SaveAsPrefabAsset(root, $"{OutRoot}/C_{id}.prefab");
        Debug.Log($"[Characters] {id} size={b.size * s} footprint={info.footprint}");
        Object.DestroyImmediate(root);
        return prefab;
    }

    /// 서비스가 구운 색 텍스처를 그대로 쓰고, 명암은 부드럽게(그림에 이미 음영이 있다), 외곽선은 얇게
    static Material Toon(Material src, string path)
    {
        var tex = src.HasProperty("_MainTex") ? src.mainTexture : src.HasProperty("_BaseMap") ? src.GetTexture("_BaseMap") : null;
        var col = src.HasProperty("_BaseColor") ? src.GetColor("_BaseColor") : src.HasProperty("_Color") ? src.color : Color.white;
        var dst = new Material(Shader.Find("Allo/Toon"))
        {
            color = tex != null ? Color.white : new Color(col.r, col.g, col.b, 1),
            mainTexture = tex,
        };
        dst.SetFloat("_RampSoft", 0.3f);
        dst.SetColor("_ShadowTint", new Color(0.8f, 0.82f, 0.95f, 1));
        dst.SetFloat("_RimStrength", 0.25f);
        dst.SetFloat("_OutlineWidth", 0.004f);
        dst.SetFloat("_OutlineDist", 0.05f);
        var old = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (old != null) { EditorUtility.CopySerialized(dst, old); return old; }
        AssetDatabase.CreateAsset(dst, path);
        return dst;
    }
}
