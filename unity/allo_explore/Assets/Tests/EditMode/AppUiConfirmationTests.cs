using System;
using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppUiConfirmationTests
{
    const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    AppState _previous;
    GameObject _root;
    AppUi _ui;

    [SetUp]
    public void SetUp()
    {
        _previous = AppSession.State;
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, null);
        AppSession.Receive(new AppState
        {
            revision = 1, view = "camp", ready = true,
            facilities = new[] { new FacilityState { id = "workshop", label = "작업장", level = 1 }, new FacilityState { id = "kitchen", label = "주방", level = 1 } },
            jobs = new[] { new JobState { role = "builder", label = "건설", targetId = "workshop" }, new JobState { role = "cook", label = "요리" } },
            egg = new EggState { id = "old-egg", active = true, phase = "incubating" }
        });
        _root = new GameObject("Confirmation regression UI");
        _ui = _root.AddComponent<AppUi>();
        if (Get<RectTransform>("_safe") == null) Call("Awake");
        Call("OnState", AppSession.State);
    }

    [TearDown]
    public void TearDown()
    {
        Object.DestroyImmediate(_root);
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous);
    }

    [Test]
    public void ConfirmationMakesVillageInertAndKeepsReviewedCancellationRole()
    {
        Set("_campDetail", true); Set("_campTab", "builder");
        Call("BuildCamp");
        ButtonNamed("이 작업 취소하기").onClick.Invoke();
        ClearContent(); Call("BuildConfirmation"); Canvas.ForceUpdateCanvases();
        var map = Get<RectTransform>("_content").Find("Village map");
        var group = map.GetComponent<CanvasGroup>();
        Assert.NotNull(group);
        Assert.IsFalse(group.interactable);
        Assert.IsFalse(group.blocksRaycasts);
        var kitchen = map.Find("Facility node kitchen").GetComponent<Button>();
        Assert.IsFalse(kitchen.IsInteractable());
        ExecuteEvents.Execute(kitchen.gameObject, new PointerEventData(EventSystem.current) { button = PointerEventData.InputButton.Left }, ExecuteEvents.pointerClickHandler);
        Assert.AreEqual("builder", Get<string>("_campTab"));
        var captured = ConfirmationIntent();
        Set("_campTab", "cook");
        var envelope = AppSession.CreateAction(captured.action, captured);
        Assert.AreEqual("cancel", envelope.action);
        Assert.AreEqual("builder", envelope.role);
    }

    [Test]
    public void EggReplacementCannotRetargetAnAlreadyReviewedDiscard()
    {
        Set("_zoneDrawer", true);
        Call("BuildCabin");
        ButtonNamed("돌보기 그만두기").onClick.Invoke();
        var captured = ConfirmationIntent();
        AppSession.Receive(new AppState { revision = 2, view = "cabin", ready = true, egg = new EggState { id = "new-egg", active = true, phase = "incubating" } });
        var envelope = AppSession.CreateAction(captured.action, captured);
        Assert.AreEqual("discardEgg", envelope.action);
        Assert.AreEqual("old-egg", envelope.eggId);
    }

    [Test]
    public void GlobalNavigationDismissesThePendingConfirmation()
    {
        Set("_campDetail", true); Call("BuildCamp");
        ButtonNamed("이 작업 취소하기").onClick.Invoke();
        Assert.NotNull(Get<Action>("_confirmAction"));
        Call("Navigate", "inventory");
        Assert.IsNull(Get<Action>("_confirmAction"));
    }

    AppAction ConfirmationIntent()
    {
        var action = Get<Action>("_confirmAction");
        return action.Target.GetType().GetFields(Private | BindingFlags.Public).Select(f => f.GetValue(action.Target)).OfType<AppAction>().Single();
    }
    Button ButtonNamed(string name) => _root.GetComponentsInChildren<Button>().Single(b => b.GetComponentInChildren<Text>()?.text == name);
    void ClearContent() { var content = Get<RectTransform>("_content"); foreach (Transform child in content.Cast<Transform>().ToArray()) Object.DestroyImmediate(child.gameObject); }
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Set(string name, object value) => typeof(AppUi).GetField(name, Private).SetValue(_ui, value);
    void Call(string name, params object[] values) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, values);
}
