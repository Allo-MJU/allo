using System;
using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppUiBookTests
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
        AppSession.Receive(State());
        _root = new GameObject("Book behavior test");
        _ui = _root.AddComponent<AppUi>();
        if (Get<RectTransform>("_safe") == null) Call("Awake");
        Call("OnState", AppSession.State);
        var content = Get<RectTransform>("_content");
        content.anchorMin = content.anchorMax = new Vector2(.5f, .5f);
        content.sizeDelta = new Vector2(1460, 622);
    }

    [TearDown]
    public void TearDown()
    {
        Object.DestroyImmediate(_root);
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous);
    }

    [Test]
    public void DexDetailsAreLeftOfTheSelectableCatalog()
    {
        Build("BuildDex");
        var left = Named("Left book page");
        var right = Named("Right book page");
        Assert.NotNull(Named("Collection book"));
        Assert.Greater(right.position.x, left.position.x);
        Assert.IsTrue(Named("Dex grid").IsChildOf(right));
        Assert.IsTrue(HasText(left, "길싹이"));
        Assert.IsTrue(ButtonNamed("차 안으로 데리고 오기").transform.IsChildOf(left));
    }

    [Test]
    public void ChoosingAnUncollectedSpeciesShowsItsHintAndConcealsItsName()
    {
        Build("BuildDex");
        Named("Dex grid").GetComponentsInChildren<Button>().Last().onClick.Invoke();
        Build("BuildDex");
        Assert.AreEqual("secret", Get<string>("_selectedDex"));
        Assert.IsTrue(HasText(Named("Left book page"), "비 오는 길에서 만나 보세요."));
        Assert.IsFalse(_root.GetComponentsInChildren<Text>().Any(t => t.text.Contains("숨은친구")));
        Assert.IsNull(ButtonNamed("차 안으로 데리고 오기"));
    }

    [Test]
    public void EmptyDexRetainsBothBookPagesAndExplainsTheMissingCatalog()
    {
        Update(s => s.dex = Array.Empty<DexState>());
        Build("BuildDex");
        Assert.NotNull(Named("Left book page")); Assert.NotNull(Named("Right book page"));
        Assert.IsTrue(_root.GetComponentsInChildren<Text>().Any(t => t.text.Contains("불러오는 중")));
    }

    [Test]
    public void MaterialSlotSelectionShowsTheActualCountOnTheLeft()
    {
        BuildInventory();
        Named("Supply slot stone").GetComponent<Button>().onClick.Invoke();
        Build("BuildInventory");
        var left = Named("Left book page"); var right = Named("Right book page");
        Assert.Greater(right.position.x, left.position.x);
        Assert.IsTrue(Named("Supply grid").IsChildOf(right));
        Assert.IsTrue(HasText(left, "돌"));
        Assert.IsTrue(left.GetComponentsInChildren<Text>().Any(t => t.text.Contains("17")));
        Assert.NotNull(ButtonNamed("주방에서 요리하기"));
    }

    [Test]
    public void ZeroFoodAndNoRecipientCannotOpenAConsumptionConfirmation()
    {
        BuildInventory(); SelectFoods();
        Named("Supply slot stew").GetComponent<Button>().onClick.Invoke();
        Build("BuildInventory");
        Assert.IsFalse(ButtonNamed("요리 1개 주기").interactable);
        Assert.IsNull(Get<Action>("_confirmAction"));
        Update(s => { s.foods[1].count = 3; s.creatures = Array.Empty<CreatureState>(); });
        Build("BuildInventory");
        var feed = ButtonNamed("요리 1개 주기");
        Assert.IsTrue(feed == null || !feed.interactable);
        Assert.IsTrue(_root.GetComponentsInChildren<Text>().Any(t => t.text.Contains("함께하는 친구")));
    }

    [Test]
    public void ConfirmationKeepsTheReviewedFoodAndRecipientAcrossASnapshot()
    {
        BuildInventory(); SelectFoods();
        Named("Supply slot stew").GetComponent<Button>().onClick.Invoke();
        Update(s => s.foods[1].count = 3);
        Build("BuildInventory");
        ButtonNamed("다른 친구 고르기").onClick.Invoke(); Build("BuildInventory");
        ButtonNamed("요리 1개 주기").onClick.Invoke();
        var intent = ConfirmationIntent();
        Update(s => { s.foods = s.foods.Reverse().ToArray(); s.creatures = s.creatures.Reverse().ToArray(); });
        var envelope = AppSession.CreateAction(intent.action, intent);
        Assert.AreEqual("feedFood", envelope.action);
        Assert.AreEqual("stew", envelope.recipeId);
        Assert.AreEqual("friend-second", envelope.creatureId);
    }

    [Test]
    public void BusyStateDisablesInventoryWritesAndVehicleSelection()
    {
        Update(s => s.busy = true);
        Build("BuildDex");
        Assert.IsFalse(ButtonNamed("차 안으로 데리고 오기").interactable);
        BuildInventory(); SelectFoods();
        Assert.IsFalse(ButtonNamed("요리 1개 주기").interactable);
        Assert.IsFalse(ButtonNamed("주방에서 요리하기").interactable);
    }

    [Test]
    public void UncraftedLockedFoodExplainsItsRequiredKitchenLevel()
    {
        BuildInventory(); SelectFoods();
        Named("Supply slot stew").GetComponent<Button>().onClick.Invoke();
        Update(s => { s.foods[1].unlocked = false; s.foods[1].requiredLevel = 3; });
        Build("BuildInventory");
        Assert.IsTrue(HasText(Named("Left book page"), "주방 Lv.3에서 만들 수 있어요."));
        Assert.IsFalse(_root.GetComponentsInChildren<Text>().Any(t => t.text.Contains("모두 사용")));
    }

    [Test]
    public void OpeningFoodTabAfterAFittingMaterialPageStartsAtTheTop()
    {
        Update(s => s.view = "inventory");
        RenderSnapshot();
        var materialPage = Named("Left book page").GetComponent<ScrollRect>();
        Assert.LessOrEqual(materialPage.content.rect.height, materialPage.viewport.rect.height);
        ButtonNamed("요리").onClick.Invoke();
        RenderSnapshot();
        var foodPage = Named("Left book page").GetComponent<ScrollRect>();
        Assert.Greater(foodPage.content.rect.height, foodPage.viewport.rect.height);
        Assert.That(foodPage.verticalNormalizedPosition, Is.EqualTo(1).Within(.002f));
    }

    void RenderSnapshot()
    {
        Call("Render");
        Canvas.ForceUpdateCanvases();
    }

    void BuildInventory() { Update(s => s.view = "inventory"); Build("BuildInventory"); }
    void SelectFoods() { ButtonNamed("요리").onClick.Invoke(); Build("BuildInventory"); }
    void Update(Action<AppState> change)
    {
        var state = AppSession.State;
        // Receive rejects same-reference revisions, so deserialize a new authoritative snapshot.
        var next = JsonUtility.FromJson<AppState>(JsonUtility.ToJson(state));
        next.revision++; change(next); AppSession.Receive(next); Call("OnState", AppSession.State);
    }
    static AppState State() => new AppState
    {
        revision = 1, view = "dex", ready = true, connected = true,
        dex = new[] {
            new DexState { id = "road_sprout", name = "길싹이", collected = true, count = 2, description = "처음 만난 친구" },
            new DexState { id = "secret", name = "숨은친구", description = "비 오는 길에서 만나 보세요." }
        },
        creatures = new[] {
            new CreatureState { id = "friend-first", speciesId = "road_sprout", name = "첫 친구" },
            new CreatureState { id = "friend-second", speciesId = "road_sprout", name = "두 번째 친구" }
        },
        materials = new[] { new MaterialState { id = "wood", label = "나무", count = 4 }, new MaterialState { id = "stone", label = "돌", count = 17 } },
        foods = new[] { new FoodState { id = "snack", label = "간식", count = 2 }, new FoodState { id = "stew", label = "스튜", count = 0 } }
    };
    void Build(string method)
    {
        var content = Get<RectTransform>("_content");
        foreach (Transform child in content.Cast<Transform>().ToArray()) Object.DestroyImmediate(child.gameObject);
        Call(method); Canvas.ForceUpdateCanvases();
    }
    Transform Named(string name) => _root.GetComponentsInChildren<Transform>().SingleOrDefault(t => t.name == name);
    Button ButtonNamed(string text) => _root.GetComponentsInChildren<Button>().SingleOrDefault(b => b.GetComponentInChildren<Text>()?.text == text);
    static bool HasText(Transform parent, string text) => parent.GetComponentsInChildren<Text>().Any(t => t.text == text);
    AppAction ConfirmationIntent()
    {
        var action = Get<Action>("_confirmAction"); Assert.NotNull(action);
        return action.Target.GetType().GetFields(Private | BindingFlags.Public).Select(f => f.GetValue(action.Target)).OfType<AppAction>().Single();
    }
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Call(string name, params object[] values) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, values);
}
