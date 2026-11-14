using System;
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

/// Actual Unity UGUI captures. Run with graphics enabled:
/// Unity -batchmode -projectPath unity/allo_explore -executeMethod BookUiCapture.Run
public static class BookUiCapture
{
    const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    [Serializable] sealed class Catalog { public Species[] species; }
    [Serializable] sealed class Species { public string id, nameKo, attribute, hint, sprite; }
    static Species[] _species;
    static string _output;
    static long _revision;

    const string PendingCapture = "ALLO.BookUiCapture.Pending";

    [InitializeOnLoadMethod]
    static void ResumeAfterDomainReload()
    {
        if (!SessionState.GetBool(PendingCapture, false)) return;
        EditorApplication.playModeStateChanged -= OnPlayModeChanged;
        EditorApplication.playModeStateChanged += OnPlayModeChanged;
    }

    public static void Run()
    {
        // ScrollRect deliberately forces AutoHide scrollbars visible outside play mode.
        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene);
        SessionState.SetBool(PendingCapture, true);
        ResumeAfterDomainReload();
        EditorApplication.EnterPlaymode();
    }

    static void OnPlayModeChanged(PlayModeStateChange state)
    {
        if (state != PlayModeStateChange.EnteredPlayMode) return;
        SessionState.SetBool(PendingCapture, false);
        EditorApplication.playModeStateChanged -= OnPlayModeChanged;
        try { CaptureAll(); EditorApplication.Exit(0); }
        catch (Exception error) { Debug.LogException(error); EditorApplication.Exit(1); }
    }

    static void CaptureAll()
    {
        var repo = Path.GetFullPath(Path.Combine(Application.dataPath, "../../.."));
        _output = Environment.GetEnvironmentVariable("ALLO_BOOK_CAPTURE_DIR") ?? Path.Combine(repo, "docs/work-results/unity-phone/book-ui");
        Directory.CreateDirectory(_output);
        _species = JsonUtility.FromJson<Catalog>(File.ReadAllText(Path.Combine(repo, "phone/assets/data/species.json"))).species;
        if (_species == null || _species.Length != 12) throw new InvalidOperationException("Expected the real twelve-species catalog.");
        var previous = AppSession.State;
        // Play mode is initialized on an empty scene before warming the art cache.
        foreach (var species in _species) SpriteLoader.LoadNow(species.sprite);
        try
        {
            foreach (var size in new[] { new Vector2Int(1600, 720), new Vector2Int(1024, 576) })
            {
                CaptureView(size, "dex", "dex");
                CaptureView(size, "inventory", "materials");
                CaptureView(size, "inventory", "foods");
            }
            CaptureView(new Vector2Int(1600, 720), "dex", "uncollected", true);
            var reviewSize = new Vector2Int(1600, 720);
            CaptureView(reviewSize, "dex", "dex-scrolled");
            CaptureView(reviewSize, "dex", "dex-empty");
            CaptureView(reviewSize, "inventory", "materials-empty");
            CaptureView(reviewSize, "inventory", "food-zero");
            CaptureView(reviewSize, "dex", "dex-ended-trip");
            CaptureView(reviewSize, "dex", "dex-long-description");
            CaptureView(reviewSize, "inventory", "materials-large-count");
            CapturePortraits();
            Debug.Log("[BookUiCapture] Saved actual Unity book views and twelve-species portrait contact sheet to " + _output);
        }
        finally { SetState(previous); }
    }

    static AppState Fixture(string view) => new AppState
    {
        revision = ++_revision, view = view, ready = true, connected = true,
        dex = _species.Select(s => new DexState { id = s.id, name = s.nameKo, attribute = s.attribute, role = Role(s.id), description = s.hint, sprite = s.sprite, collected = true, count = s.id == "road_sprout" ? 2 : 1 }).ToArray(),
        creatures = _species.Select(s => new CreatureState { id = "capture-" + s.id, speciesId = s.id, name = s.nameKo, sprite = s.sprite, role = Role(s.id), actions = s.id == "road_sprout" ? new[] { "greeting" } : Array.Empty<string>() }).Concat(new[] { new CreatureState { id = "capture-road_sprout-second", speciesId = "road_sprout", name = "길싹이", sprite = "species/road_sprout.png", role = "builder" } }).ToArray(),
        materials = new[] { new MaterialState { id = "wood", label = "나무", count = 28 }, new MaterialState { id = "stone", label = "돌", count = 17 }, new MaterialState { id = "ingredient", label = "식재료", count = 12 } },
        foods = new[] { new FoodState { id = "berry_snack", label = "베리 간식", count = 4, unlocked = true, requiredLevel = 1, costIngredient = 2 }, new FoodState { id = "travel_soup", label = "여행 수프", count = 2, unlocked = true, requiredLevel = 2, costIngredient = 3 }, new FoodState { id = "picnic_feast", label = "소풍 만찬", count = 0, unlocked = false, requiredLevel = 3, costIngredient = 4 } },
        facilities = new[] { new FacilityState { id = "kitchen", label = "주방", level = 2, unlocked = true } }, fishingRecords = 7
    };

    // Match the fixed species roles in phone/packages/allo_core/lib/src/base_camp_catalog.dart.
    static string Role(string id)
    {
        switch (id)
        {
            case "puddle_pip": case "river_glider": case "tide_keeper": case "sea_mist": return "cook";
            case "lamp_moth": case "tunnel_moth": case "star_owl": case "storm_lantern": return "trainer";
            default: return "builder";
        }
    }

    static void CaptureView(Vector2Int size, string view, string kind, bool locked = false)
    {
        SetState(null);
        var state = Fixture(view);
        if (locked) { state.dex[11].collected = false; state.dex[11].count = 0; state.creatures = state.creatures.Where(c => c.speciesId != state.dex[11].id).ToArray(); }
        if (kind == "dex-empty") state.dex = Array.Empty<DexState>();
        if (kind == "materials-empty") state.materials = Array.Empty<MaterialState>();
        if (kind == "dex-ended-trip") { state.connected = false; state.sessionEnded = true; }
        if (kind == "dex-long-description")
            state.dex[0].description = string.Join(" ", Enumerable.Repeat(state.dex[0].description, 24));
        if (kind == "materials-large-count") state.materials[1].count = 123456;
        AppSession.Receive(state);
        var root = new GameObject("Book capture application");
        var camera = NewCamera(size);
        try
        {
            var ui = root.AddComponent<AppUi>();
            if (Get<RectTransform>(ui, "_safe") == null) Call(ui, "Awake");
            Call(ui, "OnState", state);
            root.GetComponent<StoryOverlay>()?.Apply(state, false);
            if (kind == "foods") { Set(ui, "_supplyTab", "foods"); Set(ui, "_selectedSupply", "travel_soup"); }
            if (kind == "food-zero") { Set(ui, "_supplyTab", "foods"); Set(ui, "_selectedSupply", "picnic_feast"); }
            if (kind == "materials-large-count") Set(ui, "_selectedSupply", "stone");
            if (locked) Set(ui, "_selectedDex", state.dex[11].id);
            var canvas = root.GetComponentInChildren<Canvas>();
            ConfigureCanvas(canvas, camera, size);
            var safe = Get<RectTransform>(ui, "_safe");
            safe.anchorMin = Vector2.zero; safe.anchorMax = Vector2.one; safe.offsetMin = safe.offsetMax = Vector2.zero;
            Canvas.ForceUpdateCanvases();
            Call(ui, "UpdateChrome"); Call(ui, "Render");
            Canvas.ForceUpdateCanvases();
            if (kind == "dex-scrolled")
            {
                var left = root.GetComponentsInChildren<ScrollRect>().Single(s => s.name == "Left book page");
                if (left.content.rect.height <= left.viewport.rect.height)
                    throw new InvalidOperationException("Dex scroll capture must show actual overflowing detail.");
                left.verticalNormalizedPosition = 0;
                Canvas.ForceUpdateCanvases();
            }
            // Batch editor capture has no player frame: run UGUI's real lifecycle to settle thumbs/AutoHide.
            foreach (var scroll in root.GetComponentsInChildren<ScrollRect>())
                typeof(ScrollRect).GetMethod("LateUpdate", Private).Invoke(scroll, null);
            Canvas.ForceUpdateCanvases();
            foreach (var scroll in root.GetComponentsInChildren<ScrollRect>())
            {
                var overflow = scroll.content.rect.height > scroll.viewport.rect.height + .01f;
                if (scroll.verticalScrollbar.gameObject.activeSelf != overflow)
                    throw new InvalidOperationException("Scrollbar visibility does not match actual page overflow.");
                if (overflow && scroll.verticalScrollbar.size >= .999f)
                    throw new InvalidOperationException("Overflowing page must show a proportional scrollbar thumb.");
            }
            Save(camera, size, kind + "-" + size.x + "x" + size.y + ".png");
        }
        finally { Object.DestroyImmediate(root); DropCamera(camera); }
    }

    static void CapturePortraits()
    {
        var size = new Vector2Int(1600, 720);
        SetState(null); AppSession.Receive(Fixture("dex"));
        var root = new GameObject("Book portrait inspection");
        var camera = NewCamera(size);
        try
        {
            var ui = root.AddComponent<AppUi>();
            if (Get<RectTransform>(ui, "_safe") == null) Call(ui, "Awake");
            foreach (Transform child in root.transform) child.gameObject.SetActive(false);
            var canvasObject = new GameObject("Portrait sheet", typeof(RectTransform), typeof(Canvas));
            canvasObject.transform.SetParent(root.transform, false);
            ConfigureCanvas(canvasObject.GetComponent<Canvas>(), camera, size);
            var font = Get<Font>(ui, "_font");
            var title = TextAt(canvasObject.transform, "실제 도감 얼굴 12종 · 자산이 없는 종은 준비 중 표시", font, 28);
            title.color = new Color(.96f, .93f, .83f);
            Place(title.rectTransform, 40, 12, 1520, 44);
            for (var i = 0; i < _species.Length; i++)
            {
                var species = _species[i];
                var card = new GameObject(species.id, typeof(RectTransform), typeof(Image), typeof(VerticalLayoutGroup));
                card.transform.SetParent(canvasObject.transform, false);
                Place((RectTransform)card.transform, 40 + (i % 4) * 386, 72 + (i / 4) * 208, 362, 194);
                card.GetComponent<Image>().color = new Color(.94f, .90f, .80f);
                var layout = card.GetComponent<VerticalLayoutGroup>();
                layout.padding = new RectOffset(10, 10, 6, 6); layout.spacing = 2;
                layout.childControlHeight = layout.childControlWidth = true;
                layout.childForceExpandHeight = false;
                Call(ui, "BookPortrait", card.transform, species.sprite, species.id, 145f, true);
                var label = TextAt(card.transform, species.nameKo + " · " + species.id, font, 21);
                label.gameObject.AddComponent<LayoutElement>().preferredHeight = 28;
            }
            Canvas.ForceUpdateCanvases();
            Save(camera, size, "portraits-all-12.png");
        }
        finally { Object.DestroyImmediate(root); DropCamera(camera); }
    }

    static void ConfigureCanvas(Canvas canvas, Camera camera, Vector2Int size)
    {
        var scaler = canvas.GetComponent<CanvasScaler>(); if (scaler != null) scaler.enabled = false;
        canvas.renderMode = RenderMode.ScreenSpaceCamera; canvas.worldCamera = camera; canvas.planeDistance = 10;
        canvas.scaleFactor = size.y / 720f;
    }
    static Camera NewCamera(Vector2Int size)
    {
        var camera = new GameObject("Book capture camera", typeof(Camera)).GetComponent<Camera>();
        camera.transform.position = new Vector3(0, 0, -10);
        camera.orthographic = true; camera.orthographicSize = 360;
        camera.clearFlags = CameraClearFlags.SolidColor; camera.backgroundColor = new Color(.12f, .21f, .17f);
        camera.nearClipPlane = .1f; camera.farClipPlane = 100;
        camera.targetTexture = new RenderTexture(size.x, size.y, 24); camera.targetTexture.Create();
        return camera;
    }
    static void Save(Camera camera, Vector2Int size, string filename)
    {
        Canvas.ForceUpdateCanvases(); camera.Render();
        var previous = RenderTexture.active; RenderTexture.active = camera.targetTexture;
        var image = new Texture2D(size.x, size.y, TextureFormat.RGB24, false);
        try { image.ReadPixels(new Rect(0, 0, size.x, size.y), 0, 0); image.Apply(); File.WriteAllBytes(Path.Combine(_output, filename), image.EncodeToPNG()); }
        finally { RenderTexture.active = previous; Object.DestroyImmediate(image); }
    }
    static void DropCamera(Camera camera) { var texture = camera.targetTexture; camera.targetTexture = null; texture.Release(); Object.DestroyImmediate(texture); Object.DestroyImmediate(camera.gameObject); }
    static void Place(RectTransform rect, float x, float y, float width, float height) { rect.anchorMin = rect.anchorMax = rect.pivot = new Vector2(0, 1); rect.anchoredPosition = new Vector2(x, -y); rect.sizeDelta = new Vector2(width, height); }
    static Text TextAt(Transform parent, string value, Font font, int size)
    {
        var go = new GameObject("Label", typeof(RectTransform), typeof(Text)); go.transform.SetParent(parent, false);
        var label = go.GetComponent<Text>(); label.font = font; label.fontSize = size; label.text = value;
        label.color = new Color(.19f, .22f, .17f); label.alignment = TextAnchor.MiddleCenter;
        return label;
    }
    static void SetState(AppState state) => typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, state);
    static T Get<T>(AppUi ui, string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(ui);
    static void Set(AppUi ui, string name, object value) => typeof(AppUi).GetField(name, Private).SetValue(ui, value);
    static void Call(AppUi ui, string method, params object[] values) => typeof(AppUi).GetMethod(method, Private).Invoke(ui, values);
}
