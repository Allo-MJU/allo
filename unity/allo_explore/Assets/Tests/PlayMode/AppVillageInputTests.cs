using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppVillageInputTests
{
    const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    AppState _previous;
    GameObject _root;
    AppUi _ui;

    [UnitySetUp]
    public IEnumerator SetUp()
    {
        _previous = AppSession.State;
        // Assign before AddComponent: Receive would install a second full application in PlayMode.
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, new AppState
        {
            revision = 1, view = "home", ready = true,
            facilities = new[] { new FacilityState { id = "workshop", label = "작업장", level = 1 }, new FacilityState { id = "kitchen", label = "주방", level = 1 }, new FacilityState { id = "training", label = "훈련장", level = 1 } }
        });
        _root = new GameObject("Village runtime input test"); _ui = _root.AddComponent<AppUi>();
        // Native runtime OnEnable, layout and rendering initialize the actual raycast stack.
        yield return null; yield return null;
        Canvas.ForceUpdateCanvases();
    }

    [UnityTearDown]
    public IEnumerator TearDown()
    {
        if (_root != null) Object.Destroy(_root);
        yield return null;
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous);
    }

    [UnityTest]
    public IEnumerator EmptyVillageRaycastRoutesRealDragEventsAndMovesBothAxesOnlyInTheWorld()
    {
        var viewport = Get<RectTransform>("_villageLayer"); var scroll = Get<ScrollRect>("_villageScroll");
        var content = Get<RectTransform>("_villageContent");
        Assert.NotNull(viewport); Assert.NotNull(scroll); Assert.NotNull(EventSystem.current);
        var hud = Get<RectTransform>("_safe").Find("Compact application HUD");
        scroll.normalizedPosition = new Vector2(.5f, .5f); Canvas.ForceUpdateCanvases();
        var localStart = new Vector3(viewport.rect.center.x, Mathf.Lerp(viewport.rect.yMin, viewport.rect.yMax, .16f), 0);
        var localEnd = localStart + new Vector3(viewport.rect.width * .06f, viewport.rect.height * .08f, 0);
        var start = RectTransformUtility.WorldToScreenPoint(null, viewport.TransformPoint(localStart));
        var end = RectTransformUtility.WorldToScreenPoint(null, viewport.TransformPoint(localEnd));
        var pointer = new PointerEventData(EventSystem.current) { position = start, pressPosition = start, button = PointerEventData.InputButton.Left };
        var hits = new List<RaycastResult>(); EventSystem.current.RaycastAll(pointer, hits);
        Assert.IsNotEmpty(hits, "empty village must receive a real EventSystem raycast after runtime rendering");
        var handler = ExecuteEvents.GetEventHandler<IDragHandler>(hits[0].gameObject);
        Assert.AreSame(scroll.gameObject, handler, "the topmost empty-world hit must route drag events to the village ScrollRect");
        pointer.pointerCurrentRaycast = pointer.pointerPressRaycast = hits[0]; pointer.pointerDrag = handler;
        var before = content.anchoredPosition; var hudBefore = hud.position;
        ExecuteEvents.Execute(handler, pointer, ExecuteEvents.initializePotentialDrag);
        ExecuteEvents.Execute(handler, pointer, ExecuteEvents.beginDragHandler);
        pointer.dragging = true; pointer.position = end; pointer.delta = end - start;
        ExecuteEvents.Execute(handler, pointer, ExecuteEvents.dragHandler);
        ExecuteEvents.Execute(handler, pointer, ExecuteEvents.endDragHandler);
        Canvas.ForceUpdateCanvases();
        var movement = content.anchoredPosition - before;
        Assert.Greater(Mathf.Abs(movement.x), 10, "real horizontal drag movement");
        Assert.Greater(Mathf.Abs(movement.y), 10, "real vertical drag movement");
        Assert.AreEqual(hudBefore, hud.position, "the fixed HUD must not move with the world");
        yield return null;
    }

    [UnityTest]
    public IEnumerator OwnedFriendRaycastDragPansWithoutOpeningDetailAndTapSelectsTheExactInstance()
    {
        var state = AppSession.State;
        state.view = "camp";
        state.creatures = new[]
        {
            new CreatureState { id = "owned-first", speciesId = "road_sprout", name = "첫 새싹", role = "builder", sprite = "species/road_sprout.png" },
            new CreatureState { id = "owned-second", speciesId = "road_sprout", name = "둘째 새싹", role = "builder", sprite = "species/road_sprout.png" }
        };
        state.dex = new[] { new DexState { id = "road_sprout", name = "도로새싹", collected = true, attribute = "road", role = "builder", sprite = "species/road_sprout.png" } };
        typeof(AppUi).GetMethod("OnState", Private).Invoke(_ui, new object[] { state });
        yield return null; yield return null;
        Canvas.ForceUpdateCanvases();
        var content = Get<RectTransform>("_villageContent");
        var marker = (RectTransform)content.Find("Village friend owned-second");
        var scroll = Get<ScrollRect>("_villageScroll");
        Assert.NotNull(marker);
        Assert.NotNull(marker.Find("Friend avatar/Canonical friend artwork").GetComponent<RawImage>().texture, "the owned marker uses the canonical species artwork");
        CaptureCanvas("village.png");

        var pointer = RaycastMarker(marker);
        var press = ExecuteEvents.GetEventHandler<IPointerClickHandler>(pointer.pointerCurrentRaycast.gameObject);
        Assert.AreSame(marker.gameObject, press, "the real topmost hit must target this owned instance");
        var drag = ExecuteEvents.GetEventHandler<IDragHandler>(pointer.pointerCurrentRaycast.gameObject);
        Assert.AreSame(scroll.gameObject, drag, "dragging a friend must reach the village ScrollRect");
        pointer.pointerPress = press; pointer.pointerDrag = drag; pointer.eligibleForClick = true;
        ExecuteEvents.Execute(press, pointer, ExecuteEvents.pointerDownHandler);
        ExecuteEvents.Execute(drag, pointer, ExecuteEvents.initializePotentialDrag);
        var before = content.anchoredPosition;
        ExecuteEvents.Execute(drag, pointer, ExecuteEvents.beginDragHandler);
        // StandaloneInputModule cancels the button press when its parent becomes the drag handler.
        ExecuteEvents.Execute(press, pointer, ExecuteEvents.pointerUpHandler);
        pointer.eligibleForClick = false; pointer.pointerPress = null; pointer.dragging = true;
        pointer.delta = new Vector2(90, 60); pointer.position += pointer.delta;
        ExecuteEvents.Execute(drag, pointer, ExecuteEvents.dragHandler);
        ExecuteEvents.Execute(drag, pointer, ExecuteEvents.endDragHandler);
        scroll.StopMovement();
        Canvas.ForceUpdateCanvases();
        Assert.Greater(Vector2.Distance(before, content.anchoredPosition), 20);
        yield return null;
        Assert.IsTrue(string.IsNullOrEmpty(Get<string>("_villageCreatureId")), "a completed friend drag must not select an instance");
        Assert.IsNull(Get<RectTransform>("_content").Find("Village character detail"));

        pointer = RaycastMarker(marker);
        press = ExecuteEvents.GetEventHandler<IPointerClickHandler>(pointer.pointerCurrentRaycast.gameObject);
        Assert.AreSame(marker.gameObject, press);
        pointer.pointerPress = press; pointer.eligibleForClick = true;
        ExecuteEvents.Execute(press, pointer, ExecuteEvents.pointerDownHandler);
        ExecuteEvents.Execute(press, pointer, ExecuteEvents.pointerUpHandler);
        ExecuteEvents.Execute(press, pointer, ExecuteEvents.pointerClickHandler);
        yield return null; yield return null;
        Canvas.ForceUpdateCanvases();
        var detail = Get<RectTransform>("_content").Find("Village character detail");
        Assert.NotNull(detail); Assert.IsTrue(detail.gameObject.activeInHierarchy);
        Assert.AreEqual("owned-second", Get<string>("_villageCreatureId"));
        Assert.AreEqual("owned-second", Get<string>("_selectedCreature"));
        Assert.AreEqual("camp", AppSession.State.view, "opening an instance detail must keep the camp view");
        Assert.NotNull(detail.Find("Enlarged character/Canonical friend artwork").GetComponent<RawImage>().texture);
        CaptureCanvas("village-character-detail.png");
    }

    PointerEventData RaycastMarker(RectTransform marker)
    {
        var screen = RectTransformUtility.WorldToScreenPoint(null, marker.TransformPoint(marker.rect.center));
        var pointer = new PointerEventData(EventSystem.current) { position = screen, pressPosition = screen, button = PointerEventData.InputButton.Left };
        var hits = new List<RaycastResult>(); EventSystem.current.RaycastAll(pointer, hits);
        Assert.IsNotEmpty(hits, "the visible owned marker must receive a real UGUI raycast");
        pointer.pointerCurrentRaycast = pointer.pointerPressRaycast = hits[0];
        return pointer;
    }

    void CaptureCanvas(string name)
    {
        var directory = System.Environment.GetEnvironmentVariable("ALLO_VILLAGE_CAPTURE_DIR");
        if (string.IsNullOrEmpty(directory)) return;
        Directory.CreateDirectory(directory);
        var canvas = _root.GetComponentInChildren<Canvas>();
        var mode = canvas.renderMode; var worldCamera = canvas.worldCamera; var distance = canvas.planeDistance;
        var previousTarget = RenderTexture.active;
        var cameraObject = new GameObject("Village test capture camera");
        var camera = cameraObject.AddComponent<Camera>();
        var target = new RenderTexture(1600, 720, 24);
        var pixels = new Texture2D(1600, 720, TextureFormat.RGB24, false);
        try
        {
            camera.transform.position = new Vector3(0, 0, -10);
            camera.clearFlags = CameraClearFlags.SolidColor; camera.backgroundColor = new Color(.96f, .92f, .83f);
            camera.orthographic = true; camera.orthographicSize = 360; camera.targetTexture = target;
            canvas.renderMode = RenderMode.ScreenSpaceCamera; canvas.worldCamera = camera; canvas.planeDistance = 10;
            Canvas.ForceUpdateCanvases(); camera.Render();
            RenderTexture.active = target;
            pixels.ReadPixels(new Rect(0, 0, 1600, 720), 0, 0); pixels.Apply();
            File.WriteAllBytes(Path.Combine(directory, name), pixels.EncodeToPNG());
        }
        finally
        {
            canvas.renderMode = mode; canvas.worldCamera = worldCamera; canvas.planeDistance = distance;
            RenderTexture.active = previousTarget; camera.targetTexture = null;
            target.Release(); Object.Destroy(target); Object.Destroy(pixels); Object.Destroy(cameraObject);
            Canvas.ForceUpdateCanvases();
        }
    }
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
}
