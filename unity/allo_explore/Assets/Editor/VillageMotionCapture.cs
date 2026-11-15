using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using Allo.App;
using Allo.Critters;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.UI;
using Object = UnityEngine.Object;

/// Captures actual PlayMode UGUI frames; no player data, mock UI or extra runtime world.
/// Unity -batchmode -projectPath unity/allo_explore -executeMethod VillageMotionCapture.Run
public static class VillageMotionCapture
{
    const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    const string Pending = "ALLO.VillageMotionCapture.Pending";
    const float StepSeconds = 1f / 12;
    static readonly string[] SpeciesIds = { "road_sprout", "puddle_pip", "lamp_moth", "highway_comet" };
    [Serializable] sealed class Catalog { public Species[] species; }
    [Serializable] sealed class Species { public string id, nameKo, attribute, hint, sprite; }
    [Serializable] sealed class ProfileCatalog { public Profile[] profiles; }
    [Serializable] sealed class Profile { public string id, summary; public string[] traits; }
    [Serializable] sealed class ActorEvidence { public string id; public float travelled; public int distinctFrames; }
    [Serializable] sealed class SizeEvidence
    {
        public int width, height, walkFrames = 72, detailFrames = 36;
        public ActorEvidence[] actors;
        public int previewDistinctFrames, previewFrameBeforeSnapshot, previewFrameAfterSnapshot;
        public float snapshotPositionDelta, inspectorMapPositionDelta, reducedMotionPositionDelta;
        public bool reducedMotionPreviewFrozen, previewLeftOfInspector;
        public string previewTexture;
    }
    [Serializable] sealed class Evidence
    {
        public string source = "Actual Unity PlayMode UGUI, synthetic AppState fixture; not an installed device capture";
        public int fps = 12; public float walkSeconds = 6, detailSeconds = 3, warmupSeconds = 2;
        public SizeEvidence[] captures;
    }
    static Species[] _species;
    static Profile[] _profiles;
    static string _output;

    [InitializeOnLoadMethod]
    static void Resume()
    {
        if (!SessionState.GetBool(Pending, false)) return;
        EditorApplication.playModeStateChanged -= OnPlayMode;
        EditorApplication.playModeStateChanged += OnPlayMode;
    }

    public static void Run()
    {
        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene);
        SessionState.SetBool(Pending, true);
        Resume();
        EditorApplication.EnterPlaymode();
    }

    static void OnPlayMode(PlayModeStateChange change)
    {
        if (change != PlayModeStateChange.EnteredPlayMode) return;
        SessionState.SetBool(Pending, false);
        EditorApplication.playModeStateChanged -= OnPlayMode;
        try { CaptureAll(); EditorApplication.Exit(0); }
        catch (Exception error) { Debug.LogException(error); EditorApplication.Exit(1); }
    }

    static void CaptureAll()
    {
        var repo = Path.GetFullPath(Path.Combine(Application.dataPath, "../../.."));
        _output = Environment.GetEnvironmentVariable("ALLO_VILLAGE_CAPTURE_DIR") ?? Path.Combine(repo, "docs/work-results/unity-phone/village-motion");
        Directory.CreateDirectory(_output);
        _species = JsonUtility.FromJson<Catalog>(File.ReadAllText(Path.Combine(repo, "phone/assets/data/species.json"))).species;
        _profiles = JsonUtility.FromJson<ProfileCatalog>(File.ReadAllText(Path.Combine(repo, "phone/assets/data/character_profiles.json"))).profiles;
        foreach (var species in _species.Where(s => SpeciesIds.Contains(s.id))) SpriteLoader.LoadNow(species.sprite);
        var previous = AppSession.State;
        try
        {
            var evidence = new Evidence { captures = new[] { CaptureSize(new Vector2Int(1600, 720)), CaptureSize(new Vector2Int(1024, 576)) } };
            File.WriteAllText(Path.Combine(_output, "motion-evidence.json"), JsonUtility.ToJson(evidence, true) + "\n");
            Debug.Log("[VillageMotionCapture] PASS " + JsonUtility.ToJson(evidence));
        }
        finally { SetState(previous); }
    }

    static AppState Fixture() => new AppState
    {
        revision = 1, ready = true, isDemo = true, view = "camp",
        creatures = SpeciesIds.Select(id => { var s = _species.Single(v => v.id == id); var p = _profiles.FirstOrDefault(v => v.id == id); return new CreatureState
            { id = "capture-" + id, speciesId = id, name = s.nameKo, sprite = s.sprite, role = Role(id), personaSummary = p?.summary ?? "", personaTraits = p?.traits ?? Array.Empty<string>(), actions = id == "road_sprout" ? new[] { "greeting" } : Array.Empty<string>() }; }).ToArray(),
        dex = _species.Select(s => new DexState { id = s.id, name = s.nameKo, sprite = s.sprite, attribute = s.attribute, role = Role(s.id), description = s.hint, collected = SpeciesIds.Contains(s.id), count = SpeciesIds.Contains(s.id) ? 1 : 0 }).ToArray(),
        materials = new[] { new MaterialState { id = "wood", label = "나무", count = 28 }, new MaterialState { id = "stone", label = "돌", count = 17 }, new MaterialState { id = "ingredient", label = "식재료", count = 12 } },
        foods = new[] { new FoodState { id = "berry_snack", label = "베리 간식", count = 4, unlocked = true, requiredLevel = 1, costIngredient = 2 } },
        facilities = new[] { new FacilityState { id = "workshop", label = "작업장", level = 1, unlocked = true }, new FacilityState { id = "kitchen", label = "주방", level = 1, unlocked = true }, new FacilityState { id = "training", label = "훈련장", level = 1, unlocked = true } }
    };

    static string Role(string id)
    {
        switch (id)
        {
            case "puddle_pip": case "river_glider": case "tide_keeper": case "sea_mist": return "cook";
            case "lamp_moth": case "tunnel_moth": case "star_owl": case "storm_lantern": return "trainer";
            default: return "builder";
        }
    }

    static SizeEvidence CaptureSize(Vector2Int size)
    {
        var result = new SizeEvidence { width = size.x, height = size.y };
        var fixture = Fixture(); SetState(fixture);
        var root = new GameObject("Village motion capture application");
        var camera = NewCamera(size);
        try
        {
            var ui = root.AddComponent<AppUi>();
            if (Get<RectTransform>(ui, "_safe") == null) Call(ui, "Awake");
            Call(ui, "OnState", fixture);
            var canvas = root.GetComponentInChildren<Canvas>();
            var scaler = canvas.GetComponent<CanvasScaler>(); if (scaler != null) scaler.enabled = false;
            canvas.renderMode = RenderMode.ScreenSpaceCamera; canvas.worldCamera = camera; canvas.planeDistance = 10; canvas.scaleFactor = size.y / 720f;
            var safe = Get<RectTransform>(ui, "_safe"); safe.anchorMin = Vector2.zero; safe.anchorMax = Vector2.one; safe.offsetMin = safe.offsetMax = Vector2.zero;
            Canvas.ForceUpdateCanvases(); Call(ui, "UpdateChrome"); Call(ui, "Render"); Canvas.ForceUpdateCanvases();
            var friends = Get<Dictionary<string, RectTransform>>(ui, "_villageFriends");
            Require(friends.Count == 4, "Expected exactly four actual owned-character map markers.");
            for (var i = 0; i < 24; i++) Step(ui, root);
            var previous = Positions(friends);
            var travelled = friends.Keys.ToDictionary(id => id, id => 0f);
            var frames = friends.Keys.ToDictionary(id => id, id => new HashSet<int>());
            var walkDir = Path.Combine("/tmp/allo-village-motion-frames/walk", size.x + "x" + size.y); Directory.CreateDirectory(walkDir);
            for (var i = 0; i < result.walkFrames; i++)
            {
                Step(ui, root);
                foreach (var entry in friends)
                {
                    travelled[entry.Key] += Vector2.Distance(previous[entry.Key], entry.Value.anchoredPosition);
                    previous[entry.Key] = entry.Value.anchoredPosition;
                    frames[entry.Key].Add(entry.Value.GetComponentInChildren<VillageCharacterArt>().FrameIndex);
                }
                if (i == 36)
                {
                    var before = Positions(friends); Snapshot(ui, fixture);
                    result.snapshotPositionDelta = MaxDelta(before, friends);
                    Require(result.snapshotPositionDelta < .001f, "Same-view snapshot reset an actor position.");
                }
                Save(camera, size, Path.Combine(walkDir, i.ToString("D3") + ".png"));
                if (i == 18) Save(camera, size, Path.Combine(_output, "walk-" + size.x + "x" + size.y + ".png"));
            }
            result.actors = friends.Keys.Select(id => new ActorEvidence { id = id, travelled = travelled[id], distinctFrames = frames[id].Count }).ToArray();
            Require(result.actors.All(a => a.travelled > 10 && a.distinctFrames >= 4), "Every actor must actually travel and advance its atlas frames.");
            Call(ui, "OpenVillageFriend", "capture-road_sprout"); Call(ui, "Render"); Canvas.ForceUpdateCanvases();
            var inspector = root.GetComponentsInChildren<RectTransform>().Single(t => t.name == "Character inspector");
            var stage = root.GetComponentsInChildren<RectTransform>().Single(t => t.name == "Character animation stage");
            var enlarged = root.GetComponentsInChildren<RectTransform>().Single(t => t.name == "Enlarged character");
            var artwork = Get<VillageCharacterArt>(ui, "_villageDetailArt");
            result.previewTexture = artwork.GetComponent<RawImage>().texture?.name;
            Require(result.previewTexture != null && result.previewTexture.EndsWith("/joy-sheet.png", StringComparison.Ordinal), "Enlarged character must use the original Joy reaction strip.");
            var characterBounds = new Vector3[4]; var inspectorBounds = new Vector3[4]; var stageBounds = new Vector3[4];
            ((RectTransform)artwork.transform).GetWorldCorners(characterBounds); inspector.GetWorldCorners(inspectorBounds); stage.GetWorldCorners(stageBounds);
            result.previewLeftOfInspector = characterBounds[2].x < inspectorBounds[0].x;
            Require(result.previewLeftOfInspector, "Enlarged character must remain left of the text inspector.");
            Require(characterBounds[0].x >= stageBounds[0].x - .01f && characterBounds[2].x <= stageBounds[2].x + .01f &&
                characterBounds[0].y >= stageBounds[0].y - .01f && characterBounds[2].y <= stageBounds[2].y + .01f,
                "Reaction artwork must fit inside the left preview stage.");
            var held = Positions(friends); var previewFrames = new HashSet<int>();
            var detailDir = Path.Combine("/tmp/allo-village-motion-frames/detail", size.x + "x" + size.y); Directory.CreateDirectory(detailDir);
            for (var i = 0; i < result.detailFrames; i++)
            {
                Step(ui, root);
                var preview = Get<VillageCharacterArt>(ui, "_villageDetailArt"); previewFrames.Add(preview.FrameIndex);
                if (i == 12)
                {
                    result.previewFrameBeforeSnapshot = preview.FrameIndex; Snapshot(ui, fixture);
                    result.previewFrameAfterSnapshot = Get<VillageCharacterArt>(ui, "_villageDetailArt").FrameIndex;
                    Require(result.previewFrameBeforeSnapshot > 0 && result.previewFrameBeforeSnapshot == result.previewFrameAfterSnapshot, "Snapshot reset the preview animation phase.");
                }
                Save(camera, size, Path.Combine(detailDir, i.ToString("D3") + ".png"));
                if (i == 12) Save(camera, size, Path.Combine(_output, "detail-" + size.x + "x" + size.y + ".png"));
            }
            result.inspectorMapPositionDelta = MaxDelta(held, friends); result.previewDistinctFrames = previewFrames.Count;
            Require(result.inspectorMapPositionDelta < .001f && previewFrames.Count >= 4, "Inspector must pause map travel while showing the actual Joy reaction frames.");
            fixture.reducedMotion = true; Snapshot(ui, fixture); var frozen = Positions(friends);
            for (var i = 0; i < 18; i++) Step(ui, root);
            result.reducedMotionPositionDelta = MaxDelta(frozen, friends);
            var reduced = Get<VillageCharacterArt>(ui, "_villageDetailArt"); result.reducedMotionPreviewFrozen = reduced.FrameIndex == 0 && !reduced.IsAnimated;
            Require(result.reducedMotionPositionDelta < .001f && result.reducedMotionPreviewFrozen, "Reduced motion must freeze map and preview.");
            Save(camera, size, Path.Combine(_output, "reduced-motion-" + size.x + "x" + size.y + ".png"));
            fixture.reducedMotion = false; Snapshot(ui, fixture);
            CaptureDetailVariant(ui, root, camera, size, "capture-puddle_pip", "detail-puddle-personality");
            fixture.creatures.Single(c => c.speciesId == "road_sprout").actions = Array.Empty<string>();
            fixture.foods = Array.Empty<FoodState>(); Snapshot(ui, fixture);
            CaptureDetailVariant(ui, root, camera, size, "capture-road_sprout", "detail-empty-actions-foods");
            Debug.Log("[VillageMotionCapture] Captured " + size + ": " + JsonUtility.ToJson(result));
            return result;
        }
        finally { Object.DestroyImmediate(root); DropCamera(camera); }
    }

    static void CaptureDetailVariant(AppUi ui, GameObject root, Camera camera, Vector2Int size, string ownedId, string filename)
    {
        Call(ui, "OpenVillageFriend", ownedId); Call(ui, "Render");
        for (var i = 0; i < 6; i++) Step(ui, root);
        var inspector = root.GetComponentsInChildren<RectTransform>().Single(t => t.name == "Character inspector");
        var scroll = inspector.GetComponentInChildren<ScrollRect>();
        scroll.verticalNormalizedPosition = 1;
        Save(camera, size, Path.Combine(_output, filename + "-" + size.x + "x" + size.y + ".png"));
        if (scroll.content.rect.height > scroll.viewport.rect.height + .01f)
        {
            scroll.verticalNormalizedPosition = 0;
            Save(camera, size, Path.Combine(_output, filename + "-bottom-" + size.x + "x" + size.y + ".png"));
        }
    }

    static void Step(AppUi ui, GameObject root)
    {
        Call(ui, "TickVillageFriends", StepSeconds);
        foreach (var art in root.GetComponentsInChildren<VillageCharacterArt>()) art.Advance(StepSeconds);
        Canvas.ForceUpdateCanvases();
    }
    static void Snapshot(AppUi ui, AppState state) { state.revision++; SetState(state); Call(ui, "OnState", state); Call(ui, "UpdateChrome"); Call(ui, "Render"); Canvas.ForceUpdateCanvases(); }
    static Dictionary<string, Vector2> Positions(Dictionary<string, RectTransform> friends) => friends.ToDictionary(e => e.Key, e => e.Value.anchoredPosition);
    static float MaxDelta(Dictionary<string, Vector2> before, Dictionary<string, RectTransform> after) => before.Max(e => Vector2.Distance(e.Value, after[e.Key].anchoredPosition));
    static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    static void SetState(AppState state) => typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, state);
    static T Get<T>(AppUi ui, string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(ui);
    static void Call(AppUi ui, string name, params object[] args) => typeof(AppUi).GetMethod(name, Private).Invoke(ui, args);
    static Camera NewCamera(Vector2Int size)
    {
        var camera = new GameObject("Village capture camera", typeof(Camera)).GetComponent<Camera>();
        camera.transform.position = new Vector3(0, 0, -10); camera.orthographic = true; camera.orthographicSize = 360;
        camera.clearFlags = CameraClearFlags.SolidColor; camera.backgroundColor = new Color(.12f, .21f, .17f); camera.nearClipPlane = .1f; camera.farClipPlane = 100;
        camera.targetTexture = new RenderTexture(size.x, size.y, 24); camera.targetTexture.Create(); return camera;
    }
    static void Save(Camera camera, Vector2Int size, string path)
    {
        Canvas.ForceUpdateCanvases();
        foreach (var scroll in Object.FindObjectsByType<ScrollRect>(FindObjectsSortMode.None))
        {
            typeof(ScrollRect).GetMethod("LateUpdate", Private).Invoke(scroll, null);
            if (scroll.verticalScrollbar == null) continue;
            var overflow = scroll.content.rect.height > scroll.viewport.rect.height + .01f;
            Require(scroll.verticalScrollbar.gameObject.activeSelf == overflow, "Scrollbar must match actual inspector overflow.");
            Require(!overflow || scroll.verticalScrollbar.size < .999f, "Overflow must show a proportional scrollbar thumb.");
        }
        Canvas.ForceUpdateCanvases(); camera.Render();
        foreach (var label in Object.FindObjectsByType<Text>(FindObjectsSortMode.None).Where(t => t.transform.parent.name.StartsWith("Profile tag ", StringComparison.Ordinal)))
        {
            Require(label.rectTransform.rect.height >= label.preferredHeight - .01f, "Profile tag label must fit its actual text height.");
            Require(label.cachedTextGenerator.characterCountVisible >= label.text.Length, "Every profile tag character must be generated visibly.");
        }
        var previous = RenderTexture.active; RenderTexture.active = camera.targetTexture;
        var image = new Texture2D(size.x, size.y, TextureFormat.RGB24, false);
        try { image.ReadPixels(new Rect(0, 0, size.x, size.y), 0, 0); image.Apply(); File.WriteAllBytes(path, image.EncodeToPNG()); }
        finally { RenderTexture.active = previous; Object.DestroyImmediate(image); }
    }
    static void DropCamera(Camera camera) { var texture = camera.targetTexture; camera.targetTexture = null; texture.Release(); Object.DestroyImmediate(texture); Object.DestroyImmediate(camera.gameObject); }
}
