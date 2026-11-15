using System;
using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
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
    [Test]
    public void AuthoritativeFriendsCreateAtMostFourPersistentMarkersAndRemoveOnlyMissingIds()
    {
        var state = State(2, "home");
        state.creatures = Enumerable.Range(0, 5).Select(i => new CreatureState { id = "owned-" + i, speciesId = "species-" + i, name = "친구 " + i, sprite = "" }).ToArray();
        AppSession.Receive(state); Call("OnState", AppSession.State); Render();
        var content = Get<RectTransform>("_villageContent");
        Assert.AreEqual(4, content.Cast<Transform>().Count(t => t.name.StartsWith("Village friend ")));
        Assert.IsNull(content.Find("Village friend owned-4"), "the fifth owned friend has no extra world marker");
        var first = content.Find("Village friend owned-0"); var retained = content.Find("Village friend owned-1");
        Assert.AreEqual(content, first.parent);
        Assert.IsTrue(first.Find("Friend avatar/Missing friend artwork").gameObject.activeSelf, "missing art must be explicit, without substituting a different species");
        retained.GetComponent<Button>().onClick.Invoke();
        Assert.AreEqual("owned-1", Get<string>("_selectedCreature")); Assert.AreEqual("owned-1", Get<string>("_villageCreatureId"));
        var next = State(3, "home"); next.creatures = state.creatures.Select(c => new CreatureState { id = c.id, speciesId = c.speciesId, name = c.id == "owned-0" ? "바뀐 이름" : c.name, sprite = c.sprite }).ToArray();
        AppSession.Receive(next); Call("OnState", AppSession.State); Render();
        Assert.AreSame(first, content.Find("Village friend owned-0"), "unchanged IDs must keep their real GameObjects across snapshots");
        Assert.AreEqual("바뀐 이름", first.Find("Friend name").GetComponentInChildren<Text>().text);
        var replaced = State(4, "home"); replaced.creatures = next.creatures.Skip(1).ToArray();
        AppSession.Receive(replaced); Call("OnState", AppSession.State); Render();
        Assert.IsNull(content.Find("Village friend owned-0"));
        Assert.AreSame(retained, content.Find("Village friend owned-1"));
        Assert.NotNull(content.Find("Village friend owned-4"));
        Assert.AreEqual(4, content.Cast<Transform>().Count(t => t.name.StartsWith("Village friend ")));
    }

    static AppState State(int revision, string view) => new AppState { revision = revision, view = view, ready = true, facilities = new[] { new FacilityState { id = "workshop", label = "작업장", level = 1 }, new FacilityState { id = "kitchen", label = "주방", level = 1 }, new FacilityState { id = "training", label = "훈련장", level = 1 } } };
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Call(string name, params object[] args) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, args);
    void Render() => Call("Render");
}
