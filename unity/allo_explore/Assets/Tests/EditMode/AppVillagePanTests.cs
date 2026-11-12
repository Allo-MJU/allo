using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppVillagePanTests
{
    const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    GameObject _root;
    AppUi _ui;
    AppState _previous;

    [SetUp]
    public void SetUp()
    {
        _previous = AppSession.State;
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, null);
        AppSession.Receive(State(1, "home"));
        _root = new GameObject("Village pan regression UI"); _ui = _root.AddComponent<AppUi>();
        if (Get<RectTransform>("_safe") == null) Call("Awake");
        Call("OnState", AppSession.State); Render();
    }
    [TearDown]
    public void TearDown() { Object.DestroyImmediate(_root); typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous); }

    [Test]
    public void WorldCoversCanvasAndPansBothAxesWithoutMovingTheHud()
    {
        var layer = Get<RectTransform>("_villageLayer"); var scroll = Get<ScrollRect>("_villageScroll");
        var content = Get<RectTransform>("_villageContent"); var safe = Get<RectTransform>("_safe");
        Assert.AreEqual(safe.parent, layer.parent); Assert.Less(layer.GetSiblingIndex(), safe.GetSiblingIndex());
        Assert.AreEqual(Vector2.zero, layer.anchorMin); Assert.AreEqual(Vector2.one, layer.anchorMax);
        Assert.IsTrue(scroll.horizontal && scroll.vertical && scroll.inertia); Assert.AreEqual(ScrollRect.MovementType.Clamped, scroll.movementType);
        Assert.Greater(content.rect.width, layer.rect.width + 200); Assert.Greater(content.rect.height, layer.rect.height + 200);
        Assert.AreEqual(0, Get<RectTransform>("_content").GetComponentsInChildren<ScrollRect>().Length, "world pan must be outside menu scroll registry");
        var node = content.Find("Facility node workshop"); Assert.NotNull(node);
        var worldBefore = node.position; var hudBefore = safe.Find("Compact application HUD").position;
        scroll.normalizedPosition = new Vector2(.18f, .78f); Canvas.ForceUpdateCanvases();
        Assert.Greater(Vector3.Distance(worldBefore, node.position), 20);
        Assert.AreEqual(hudBefore, safe.Find("Compact application HUD").position);
        foreach (var edge in new[] { Vector2.zero, Vector2.one })
        {
            scroll.normalizedPosition = edge; Canvas.ForceUpdateCanvases();
            var bounds = RectTransformUtility.CalculateRelativeRectTransformBounds(layer, content);
            Assert.LessOrEqual(bounds.min.x, layer.rect.xMin + 1); Assert.GreaterOrEqual(bounds.max.x, layer.rect.xMax - 1);
            Assert.LessOrEqual(bounds.min.y, layer.rect.yMin + 1); Assert.GreaterOrEqual(bounds.max.y, layer.rect.yMax - 1);
        }
    }

    [Test]
    public void EmptyVillageRaycastRoutesRealDragEventsAndMovesBothAxesOnlyInTheWorld()
    {
        var viewport = Get<RectTransform>("_villageLayer");
        var scroll = Get<ScrollRect>("_villageScroll");
        var content = Get<RectTransform>("_villageContent");
        var hud = Get<RectTransform>("_safe").Find("Compact application HUD");
        scroll.normalizedPosition = new Vector2(.5f, .5f); Canvas.ForceUpdateCanvases();
        // Lower-center clearing avoids facilities, fixed top HUD and right-side actions.
        var localStart = new Vector3(viewport.rect.center.x, Mathf.Lerp(viewport.rect.yMin, viewport.rect.yMax, .16f), 0);
        var localEnd = localStart + new Vector3(viewport.rect.width * .06f, viewport.rect.height * .08f, 0);
        var start = RectTransformUtility.WorldToScreenPoint(null, viewport.TransformPoint(localStart));
        var end = RectTransformUtility.WorldToScreenPoint(null, viewport.TransformPoint(localEnd));
        // These runtime-only components do not automatically register OnEnable in EditMode.
        var eventSystem = _root.GetComponentInChildren<EventSystem>() ?? _root.AddComponent<EventSystem>();
        var raycaster = Get<RectTransform>("_safe").GetComponentInParent<GraphicRaycaster>();
        Assert.NotNull(raycaster);
        var registerRaycaster = !RaycasterManager.GetRaycasters().Contains(raycaster);
        if (registerRaycaster) typeof(BaseRaycaster).GetMethod("OnEnable", Private).Invoke(raycaster, null);
        try
        {
            var pointer = new PointerEventData(eventSystem) { position = start, pressPosition = start, button = PointerEventData.InputButton.Left };
            var hits = new List<RaycastResult>(); eventSystem.RaycastAll(pointer, hits);
            Assert.IsNotEmpty(hits, "empty village must receive a real EventSystem raycast");
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
        }
        finally
        {
            if (registerRaycaster) typeof(BaseRaycaster).GetMethod("OnDisable", Private).Invoke(raycaster, null);
        }
    }

    [Test]
    public void SnapshotInspectorAndHomeCampRoundTripKeepTheSamePanContent()
    {
        var scroll = Get<ScrollRect>("_villageScroll"); var content = Get<RectTransform>("_villageContent");
        scroll.normalizedPosition = new Vector2(.23f, .71f); Canvas.ForceUpdateCanvases();
        var position = content.anchoredPosition;
        foreach (var state in new[] { State(2, "home"), State(3, "camp"), State(4, "home") })
        {
            AppSession.Receive(state); Call("OnState", AppSession.State); Render();
            Assert.AreSame(content, Get<RectTransform>("_villageContent"));
            Assert.That(scroll.normalizedPosition.x, Is.EqualTo(.23f).Within(.002f));
            Assert.That(scroll.normalizedPosition.y, Is.EqualTo(.71f).Within(.002f));
            Assert.Less(Vector2.Distance(position, content.anchoredPosition), 1);
        }
        AppSession.Receive(State(5, "camp")); Call("OnState", AppSession.State); Call("OpenVillageFacility", "kitchen"); Render();
        Assert.AreSame(content, Get<RectTransform>("_villageContent"));
        Assert.Less(Vector2.Distance(position, content.anchoredPosition), 1);
    }

    [Test]
    public void CabinHidesTheWorldAndReturningRestoresIt()
    {
        var layer = Get<RectTransform>("_villageLayer"); var content = Get<RectTransform>("_villageContent");
        AppSession.Receive(State(2, "cabin")); Call("OnState", AppSession.State); Render(); Assert.IsFalse(layer.gameObject.activeSelf);
        AppSession.Receive(State(3, "home")); Call("OnState", AppSession.State); Render(); Assert.IsTrue(layer.gameObject.activeSelf); Assert.AreSame(content, Get<RectTransform>("_villageContent"));
    }
    static AppState State(int revision, string view) => new AppState { revision = revision, view = view, ready = true, facilities = new[] { new FacilityState { id = "workshop", label = "작업장", level = 1 }, new FacilityState { id = "kitchen", label = "주방", level = 1 }, new FacilityState { id = "training", label = "훈련장", level = 1 } } };
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Call(string name, params object[] args) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, args);
    void Render()
    {
        var content = Get<RectTransform>("_content"); var old = content.Cast<Transform>().ToArray();
        foreach (var child in old) LogAssert.Expect(LogType.Error, new Regex("^Destroy may not be called from edit mode! Use DestroyImmediate instead\\."));
        Call("Render"); foreach (var child in old) if (child != null && !child.gameObject.activeSelf) Object.DestroyImmediate(child.gameObject);
    }
}
