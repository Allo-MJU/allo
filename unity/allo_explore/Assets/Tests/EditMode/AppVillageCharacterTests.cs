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
        Assert.IsTrue(detail.GetComponentsInChildren<Text>().Any(t => t.text == "할 수 있는 행동"));
        var preview = detail.GetComponentsInChildren<RectTransform>().Single(t => t.name == "Enlarged character");
        var inspector = detail.Find("Character inspector");
        Assert.NotNull(inspector);
        Assert.IsFalse(preview.IsChildOf(inspector), "character art stays separate from right-hand explanation and actions");
        Assert.Less(preview.position.x, inspector.position.x, "large character preview belongs on the left");
        Assert.That(((RectTransform)inspector).anchorMin.x, Is.GreaterThanOrEqualTo(.55f));
        Assert.IsTrue(Get<RectTransform>("_villageLayer").gameObject.activeSelf);
        Assert.AreEqual("camp", AppSession.CurrentView);
    }

    [Test]
    public void DetailUsesTheExistingJoyActionInsteadOfTheWalkingSheet()
    {
        Marker("first").GetComponent<Button>().onClick.Invoke(); Render();
        var detail = Get<RectTransform>("_content").Find("Village character detail");
        var art = detail.GetComponentInChildren<VillageCharacterArt>();
        Assert.NotNull(art);
        Assert.AreEqual("poses/road_sprout/joy-sheet.png", art.GetComponent<RawImage>().texture.name);
    }

    [Test]
    public void RightInspectorShowsTheSelectedCharactersPersonaSummaryAndTraits()
    {
        var state = State(2);
        state.creatures[1] = JsonUtility.FromJson<CreatureState>("{\"id\":\"second\",\"speciesId\":\"road_sprout\",\"name\":\"두 번째 친구\",\"role\":\"cook\",\"personaSummary\":\"차분히 관찰하는 솔직한 친구예요.\",\"personaTraits\":[\"호기심\",\"솔직함\"]}");
        Receive(state);
        Marker("second").GetComponent<Button>().onClick.Invoke(); Render();
        var inspector = Get<RectTransform>("_content").Find("Village character detail/Character inspector");
        var texts = inspector.GetComponentsInChildren<Text>().Select(t => t.text).ToArray();
        Assert.Contains("차분히 관찰하는 솔직한 친구예요.", texts);
        Assert.Contains("호기심", texts); Assert.Contains("솔직함", texts);
        foreach (var tag in inspector.GetComponentsInChildren<Text>().Where(t => t.text == "호기심" || t.text == "솔직함" || t.text == "요리사"))
            Assert.GreaterOrEqual(tag.rectTransform.rect.height + .01f, tag.preferredHeight, "profile tag must have enough allocated height to draw its text");
        Assert.AreEqual("second", Get<string>("_selectedCreature"));
    }

    [Test]
    public void EmptyInteractionsOfferExistingTrainingAndKitchenRoutes()
    {
        Marker("second").GetComponent<Button>().onClick.Invoke(); Render();
        var buttons = Get<RectTransform>("_content").GetComponentsInChildren<Button>();
        Assert.IsTrue(buttons.Single(b => b.name == "훈련장 살펴보기").interactable);
        buttons.Single(b => b.name == "주방 살펴보기").onClick.Invoke(); Render();
        Assert.IsNull(Get<string>("_villageCreatureId"));
        Assert.AreEqual("kitchen", Get<string>("_facility"));
        Assert.IsTrue(Get<bool>("_campDetail"));
    }

    [Test]
    public void InspectorFoodConfirmationKeepsTheExactRecipientAndRecipe()
    {
        var state = State(2); state.foods = new[] { new FoodState { id = "berry_snack", label = "베리 간식", count = 2 } }; Receive(state);
        Marker("second").GetComponent<Button>().onClick.Invoke(); Render();
        Get<RectTransform>("_content").GetComponentsInChildren<Button>().Single(b => b.name == "베리 간식 · 2개 · 1개 주기").onClick.Invoke();
        var confirmation = Get<Action>("_confirmAction"); Assert.NotNull(confirmation);
        var intent = confirmation.Target.GetType().GetFields(Private | BindingFlags.Public).Select(f => f.GetValue(confirmation.Target)).OfType<AppAction>().Single();
        Assert.AreEqual("feedFood", intent.action);
        Assert.AreEqual("second", intent.creatureId);
        Assert.AreEqual("berry_snack", intent.recipeId);
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
    public void WalkingCoversVisibleGroundAndSnapshotKeepsItsPosition()
    {
        var marker = Marker("first"); var origin = marker.anchoredPosition;
        for (var i = 0; i < 30; i++) Call("TickVillageFriends", .1f);
        Assert.Greater(Vector2.Distance(origin, marker.anchoredPosition), 1);
        var moved = marker.anchoredPosition;
        Receive(State(2));
        Assert.Less(Vector2.Distance(moved, marker.anchoredPosition), 1, "snapshots must not reset wandering");
        var farthest = 0f;
        for (var i = 0; i < 1200; i++)
        {
            Call("TickVillageFriends", .1f);
            var distance = Vector2.Distance(origin, marker.anchoredPosition);
            farthest = Mathf.Max(farthest, distance);
            Assert.LessOrEqual(distance, 165, "walk on the grass near its own area");
        }
        Assert.Greater(farthest, 90, "walking must cover ground beyond the old floating effect");
    }

    [Test]
    public void WalkingAlternatesWithRestAndChangesTheArtMotionState()
    {
        var marker = Marker("first");
        var art = marker.GetComponentsInChildren<MonoBehaviour>().FirstOrDefault(c => c.GetType().Name == "VillageCharacterArt");
        Assert.NotNull(art, "village art must use an articulated frame renderer");
        var moving = art.GetType().GetProperty("IsMoving");
        var walked = false; var restedAfterWalking = false;
        for (var i = 0; i < 800; i++)
        {
            Call("TickVillageFriends", .1f);
            var isMoving = (bool)moving.GetValue(art);
            if (isMoving) walked = true;
            if (walked && !isMoving) restedAfterWalking = true;
        }
        Assert.IsTrue(walked);
        Assert.IsTrue(restedAfterWalking);
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
