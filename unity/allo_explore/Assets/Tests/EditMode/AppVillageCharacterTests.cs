using System;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppVillageCharacterTests
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
        AppSession.Receive(State(1));
        _root = new GameObject("Village character detail test");
        _ui = _root.AddComponent<AppUi>();
        if (Get<RectTransform>("_safe") == null) Call("Awake");
        Call("OnState", AppSession.State); Render();
    }

    [TearDown]
    public void TearDown()
    {
        Object.DestroyImmediate(_root);
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous);
    }

    [Test]
    public void TappingSameSpeciesOpensExactOwnedCharacterAboveTheMap()
    {
        Marker("second").GetComponent<Button>().onClick.Invoke(); Render();
        var detail = Get<RectTransform>("_content").Find("Village character detail");
        Assert.NotNull(detail, "tap must open local detail instead of sending dex navigation");
        Assert.AreEqual("second", Get<string>("_villageCreatureId"));
        Assert.IsTrue(detail.GetComponentsInChildren<Text>().Any(t => t.text == "두 번째 친구"));
        Assert.IsTrue(detail.GetComponentsInChildren<Text>().Any(t => t.text == "두 번째 친구의 배운 행동"));
        Assert.NotNull(detail.Find("Enlarged character"));
        Assert.IsTrue(Get<RectTransform>("_villageLayer").gameObject.activeSelf);
        Assert.AreEqual("camp", AppSession.CurrentView);
    }

    [Test]
    public void ClosingCharacterDetailPreservesMapPanAndFacilityCanReplaceIt()
    {
        var scroll = Get<ScrollRect>("_villageScroll");
        scroll.normalizedPosition = new Vector2(.23f, .71f); Canvas.ForceUpdateCanvases();
        var position = scroll.content.anchoredPosition;
        Marker("first").GetComponent<Button>().onClick.Invoke(); Render();
        var close = _root.GetComponentsInChildren<Button>().FirstOrDefault(b => b.name == "상세 닫기");
        Assert.NotNull(close); close.onClick.Invoke(); Render();
        Assert.IsNull(Get<RectTransform>("_content").Find("Village character detail"));
        Assert.Less(Vector2.Distance(position, scroll.content.anchoredPosition), 1);
        Marker("first").GetComponent<Button>().onClick.Invoke(); Render();
        Call("OpenVillageFacility", "kitchen"); Render();
        Assert.IsNull(Get<RectTransform>("_content").Find("Village character detail"));
        Assert.IsTrue(Get<bool>("_campDetail"));
    }

    [Test]
    public void RemovedCharacterAndLeavingVillageDiscardTheSelection()
    {
        Marker("first").GetComponent<Button>().onClick.Invoke(); Render();
        Assert.NotNull(Get<RectTransform>("_content").Find("Village character detail"));
        var next = State(2); next.creatures = next.creatures.Skip(1).ToArray(); Receive(next);
        Assert.IsNull(Get<RectTransform>("_content").Find("Village character detail"));
        Marker("second").GetComponent<Button>().onClick.Invoke(); Render();
        next = State(3); next.view = "inventory"; Receive(next);
        Receive(State(4));
        Assert.IsNull(Get<RectTransform>("_content").Find("Village character detail"));
    }

    [Test]
    public void ReplacingAMissingMarkerUsesItsVacantSpotWithoutMovingRetainedFriends()
    {
        var state = State(2);
        state.creatures = Enumerable.Range(0, 5).Select(i => new CreatureState { id = "friend-" + i, name = "Friend", speciesId = "road_sprout", sprite = "" }).ToArray();
        Receive(state);
        var retained = Marker("friend-3"); var anchor = retained.anchorMin;
        var next = State(3); next.creatures = state.creatures.Skip(1).ToArray(); Receive(next);
        var anchors = Get<RectTransform>("_villageContent").Cast<RectTransform>()
            .Where(t => t.name.StartsWith("Village friend ")).Select(t => t.anchorMin).ToArray();
        Assert.AreEqual(4, anchors.Distinct().Count(), "replacement must not cover an existing friend");
        Assert.AreEqual(anchor, retained.anchorMin, "retained characters must not teleport");
    }

    [Test]
    public void NativeBackDismissesFoodConfirmationBeforeClosingCharacterDetail()
    {
        Marker("second").GetComponent<Button>().onClick.Invoke(); Render();
        Set("_confirmAction", (Action)(() => { }));
        Set("_confirmTitle", "Give food?"); Set("_confirmDescription", "Confirm"); Render();
        Allo.Bridge.FlutterBridge.HandleBack(); Render();
        Assert.IsNull(Get<Action>("_confirmAction"));
        Assert.AreEqual("second", Get<string>("_villageCreatureId"));
        Assert.NotNull(Get<RectTransform>("_content").Find("Village character detail"));
        Allo.Bridge.FlutterBridge.HandleBack(); Render();
        Assert.IsNull(Get<RectTransform>("_content").Find("Village character detail"));
    }

    [Test]
    public void RemovedCharacterCancelsItsPendingFoodConfirmation()
    {
        Marker("first").GetComponent<Button>().onClick.Invoke(); Render();
        var sent = false;
        Set("_confirmAction", (Action)(() => sent = true));
        Set("_confirmTitle", "Give food?"); Set("_confirmDescription", "Confirm"); Render();
        var state = State(2); state.creatures = state.creatures.Skip(1).ToArray(); Receive(state);
        Assert.IsNull(Get<Action>("_confirmAction"), "removed owned IDs must invalidate captured actions");
        Assert.IsFalse(sent);
        Assert.IsNull(Get<RectTransform>("_content").Find("Village character detail"));
    }

    [Test]
    public void ReturningHomeFromFacilityDoesNotFreezeFriends()
    {
        Call("OpenVillageFacility", "kitchen"); Render();
        var state = State(2); state.view = "home"; Receive(state);
        var marker = Marker("first"); var position = marker.anchoredPosition;
        for (var i = 0; i < 30; i++) Call("TickVillageFriends", .1f);
        Assert.Greater(Vector2.Distance(position, marker.anchoredPosition), 1);
    }

    [Test]
    public void CharacterInspectorDoesNotInheritFacilityScrollPosition()
    {
        var state = State(2);
        state.creatures[1].actions = Enumerable.Range(0, 12).Select(i => "learned-" + i).ToArray();
        Receive(state);
        Call("OpenVillageFacility", "kitchen"); Render();
        var facilityScroll = Get<RectTransform>("_content").GetComponentInChildren<ScrollRect>();
        facilityScroll.verticalNormalizedPosition = .2f;
        Marker("second").GetComponent<Button>().onClick.Invoke(); Render();
        var detail = Get<RectTransform>("_content").Find("Village character detail");
        Assert.NotNull(detail);
        Assert.That(detail.GetComponentInChildren<ScrollRect>().verticalNormalizedPosition, Is.EqualTo(1).Within(.01f));
    }

    [Test]
    public void WanderingMovesWithinItsOwnSmallAreaAndSnapshotKeepsItsPosition()
    {
        var marker = Marker("first"); var origin = marker.anchoredPosition;
        for (var i = 0; i < 30; i++) Call("TickVillageFriends", .1f);
        Assert.Greater(Vector2.Distance(origin, marker.anchoredPosition), 1);
        var moved = marker.anchoredPosition;
        Receive(State(2));
        Assert.Less(Vector2.Distance(moved, marker.anchoredPosition), 1, "snapshots must not reset wandering");
        for (var i = 0; i < 1200; i++)
        {
            Call("TickVillageFriends", .1f);
            Assert.LessOrEqual(Vector2.Distance(origin, marker.anchoredPosition), 65, "stay near the original spot");
        }
    }

    [TestCase("reduced")]
    [TestCase("busy")]
    [TestCase("detail")]
    [TestCase("confirmation")]
    public void MotionPausesForAccessibilityAndProtectedInteraction(string reason)
    {
        var state = State(2); state.reducedMotion = reason == "reduced"; state.busy = reason == "busy";
        Receive(state);
        if (reason == "detail") { Marker("first").GetComponent<Button>().onClick.Invoke(); Render(); }
        if (reason == "confirmation") Set("_confirmAction", (Action)(() => { }));
        var marker = Marker("first"); var position = marker.anchoredPosition;
        for (var i = 0; i < 30; i++) Call("TickVillageFriends", .1f);
        Assert.AreEqual(position, marker.anchoredPosition);
    }

    static AppState State(int revision) => new AppState
    {
        revision = revision, view = "camp", ready = true,
        facilities = new[] { new FacilityState { id = "workshop", level = 1 }, new FacilityState { id = "kitchen", level = 1 }, new FacilityState { id = "training", level = 1 } },
        creatures = new[]
        {
            new CreatureState { id = "first", speciesId = "road_sprout", name = "첫 친구", role = "builder", sprite = "" },
            new CreatureState { id = "second", speciesId = "road_sprout", name = "두 번째 친구", role = "cook", sprite = "" }
        }
    };
    RectTransform Marker(string id) => (RectTransform)Get<RectTransform>("_villageContent").Find("Village friend " + id);
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Set(string name, object value) => typeof(AppUi).GetField(name, Private).SetValue(_ui, value);
    void Call(string name, params object[] args)
    {
        var method = typeof(AppUi).GetMethod(name, Private);
        Assert.NotNull(method, "missing village behavior: " + name);
        method.Invoke(_ui, args);
    }
    void Receive(AppState state) { AppSession.Receive(state); Call("OnState", AppSession.State); Render(); }
    void Render()
    {
        var old = Get<RectTransform>("_content").Cast<Transform>().ToArray();
        foreach (var child in old) LogAssert.Expect(LogType.Error, new Regex("^Destroy may not be called from edit mode! Use DestroyImmediate instead\\."));
        Call("Render");
        foreach (var child in old) if (child != null && !child.gameObject.activeSelf) Object.DestroyImmediate(child.gameObject);
    }
}
