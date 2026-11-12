using System.Collections;
using System.Collections.Generic;
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
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
}
