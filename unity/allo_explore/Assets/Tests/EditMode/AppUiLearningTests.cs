using System;
using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppUiLearningTests
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
        _root = new GameObject("Companion learning UI"); _ui = _root.AddComponent<AppUi>();
        if (typeof(AppUi).GetField("_safe", Private).GetValue(_ui) == null) Call("Awake");
        Call("OnState", AppSession.State);
    }
    [TearDown]
    public void TearDown() { Object.DestroyImmediate(_root); typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous); }

    [Test]
    public void EggGetsSevenCareActionsAndNeverCompanionChat()
    {
        Call("BuildCabin");
        foreach (var label in new[] { "간식", "물", "공", "쓰다듬기", "인형", "쿠션", "담요" })
            Assert.IsTrue(ButtonNamed(label)?.interactable, label);
        Assert.IsNull(ButtonNamed("다음 이야기"));
        Assert.IsNull(ButtonNamed("친구에게 말 걸기"));
    }

    [Test]
    public void SelectedOwnedFriendKeepsStoryWhileANewEggExists()
    {
        var state = State(); SelectFriend(state); Apply(state);
        Call("BuildCabin");
        Assert.IsTrue(HasText("작은 새싹 이야기"));
        Assert.IsTrue(HasText("새싹이 햇빛을 만났어요."));
        Assert.IsTrue(ButtonNamed("다음 이야기").interactable);
        Assert.IsTrue(ButtonNamed("이야기 다시 듣기").interactable);
        Assert.IsTrue(ButtonNamed("친구에게 말 걸기").interactable);
        Assert.IsNull(ButtonNamed("함께 사진 찍기"));
        Assert.IsFalse(CabinEgg.CanInteract(state, "cabin", "new-egg"));
    }

    [Test]
    public void UnownedSelectionCannotOpenStoryOrCare()
    {
        var state = State(); SelectFriend(state); state.learning.creatureId = "not-owned"; Apply(state);
        Assert.IsFalse(AppUi.HasSelectedCompanion(state));
        Assert.IsFalse(AppUi.CanCommonCare(state, "pet"));
        Assert.IsFalse(AppUi.CanCompanionTalk(state));
    }

    [Test]
    public void BusyRecordingAndUnavailableStoryDisableDialogueButKeepFreeCare()
    {
        var state = State(); SelectFriend(state);
        state.learning.recording = true;
        Assert.IsFalse(AppUi.CanCompanionTalk(state));
        Assert.IsTrue(AppUi.CanCommonCare(state, "snack"));
        state.learning.recording = false; state.learning.available = false;
        Assert.IsFalse(AppUi.CanCompanionTalk(state));
        Assert.IsTrue(AppUi.CanCommonCare(state, "ball"));
        Assert.IsFalse(AppUi.CanCommonCare(state, "feedFood"));
    }

    [Test]
    public void CarePlaybackRequiresANewAcceptedSequenceForTheSameVisibleTarget()
    {
        var previous = State(); var next = State();
        next.learning.careSequence = 1; next.learning.careActionId = "ball";
        Assert.IsTrue(CabinEgg.ShouldPlayCare(previous, next));
        Assert.IsFalse(CabinEgg.ShouldPlayCare(next, next));
        Assert.IsFalse(CabinEgg.ShouldPlayCare(null, next), "restoring a snapshot must not replay old care");
        next.view = "home"; Assert.IsFalse(CabinEgg.ShouldPlayCare(previous, next));
        next.view = "cabin"; SelectFriend(next); Assert.IsFalse(CabinEgg.ShouldPlayCare(previous, next));
        SelectFriend(previous); Assert.IsTrue(CabinEgg.ShouldPlayCare(previous, next));
        next.egg.id = "another-round";
        Assert.IsTrue(CabinEgg.ShouldPlayCare(previous, next), "selected companion care is independent of a new egg round");
    }

    [Test]
    public void CommonCareActionPreservesIdentityAndDoesNotBecomeLegacyPet()
    {
        var state = State(); SelectFriend(state);
        var action = AppUi.CommonCareIntent(state, "pet");
        Assert.AreEqual("commonCare", action.action);
        Assert.AreEqual("pet", action.actionId);
        Assert.AreEqual("owned-a", action.creatureId);
        Assert.IsNull(AppUi.CommonCareIntent(state, "unknown"));
    }

    [Test]
    public void SessionEndDisablesCareAndDialogueButLeavesMuteAvailable()
    {
        var state = State(); SelectFriend(state); state.sessionEnded = true; Apply(state);
        Call("BuildCabin");
        Assert.IsFalse(ButtonNamed("간식").interactable);
        Assert.IsFalse(ButtonNamed("다음 이야기").interactable);
        Assert.IsTrue(ButtonNamed("목소리 끄기").interactable);
    }

    [Test]
    public void CompanionMicrophoneUsesNativeAvailabilityIndependentlyFromEggEvaluation()
    {
        var state = State(); SelectFriend(state); state.speechAvailable = false; Apply(state);
        Call("BuildCabin");
        Assert.IsTrue(ButtonNamed("친구에게 말 걸기").interactable);
    }

    [Test]
    public void ChoosingAnOwnedFriendAfterHatchHidesTheOverlappingEggStartSheet()
    {
        var state = State(); state.egg.active = false; state.egg.phase = "hatched"; Apply(state);
        typeof(AppUi).GetField("_choosingCompanion", Private).SetValue(_ui, true);
        Call("BuildCabin");
        Assert.IsNotNull(_root.GetComponentsInChildren<Transform>().SingleOrDefault(t => t.name == "Choose care target"));
        Assert.IsNull(_root.GetComponentsInChildren<Transform>().SingleOrDefault(t => t.name == "Cabin start bottom sheet"));
    }

    [Test]
    public void OpeningTheFriendPickerClosesTheEggTextAndZoneDrawers()
    {
        typeof(AppUi).GetField("_speechDrawer", Private).SetValue(_ui, true);
        typeof(AppUi).GetField("_zoneDrawer", Private).SetValue(_ui, true);
        Call("BuildCompanionSelector");
        ButtonNamed("친구 고르기").onClick.Invoke();
        Assert.IsFalse((bool)typeof(AppUi).GetField("_speechDrawer", Private).GetValue(_ui));
        Assert.IsFalse((bool)typeof(AppUi).GetField("_zoneDrawer", Private).GetValue(_ui));
    }

    [TestCase("글로 말하기")]
    [TestCase("자리와 돌보기")]
    public void OpeningAnEggDrawerClosesTheFriendPicker(string action)
    {
        typeof(AppUi).GetField("_choosingCompanion", Private).SetValue(_ui, true);
        Call("BuildCabin");
        ButtonNamed(action).onClick.Invoke();
        Assert.IsFalse((bool)typeof(AppUi).GetField("_choosingCompanion", Private).GetValue(_ui));
    }

    [Test]
    public void ActiveWindowStoryHidesCompanionPanelAndCareControls()
    {
        var state = State(); SelectFriend(state);
        state.story = new StoryState { active = true, canPlay = true };
        Apply(state); Call("BuildCabin");
        Assert.IsFalse(AppUi.CanCompanionTalk(state));
        Assert.IsFalse(AppUi.CanCommonCare(state, "pet"));
        Assert.IsNull(ButtonNamed("다음 이야기"));
        Assert.IsNull(ButtonNamed("간식"));
        Assert.IsFalse(CabinEgg.CanInteract(state, "cabin", "new-egg"));
    }

    [Test]
    public void OnlyOneCommonCareDockIsBuiltForAnEgg()
    {
        Call("BuildCabin");
        Assert.AreEqual(1, _root.GetComponentsInChildren<Transform>().Count(t => t.name == "Common care dock"));
    }

    static AppState State() => new AppState
    {
        revision = 1, view = "cabin", ready = true, speechAvailable = true,
        egg = new EggState { id = "new-egg", active = true, phase = "incubating" },
        learning = new LearningState { target = "egg", active = true, creatures = new[] { new LearningCreatureState { creatureId = "owned-a", speciesId = "road_sprout", name = "새싹이" } } }
    };
    static void SelectFriend(AppState state)
    {
        state.learning.target = "companion"; state.learning.creatureId = "owned-a";
        state.learning.speciesId = "road_sprout"; state.learning.name = "새싹이";
        state.learning.active = state.learning.available = state.learning.canNext = state.learning.speechAvailable = true;
        state.learning.title = "작은 새싹 이야기"; state.learning.text = "새싹이 햇빛을 만났어요.";
    }
    void Apply(AppState state) { state.revision = AppSession.State.revision + 1; AppSession.Receive(state); Call("OnState", AppSession.State); }
    Button ButtonNamed(string text) => _root.GetComponentsInChildren<Button>().SingleOrDefault(b => b.GetComponentInChildren<Text>()?.text == text);
    bool HasText(string text) => _root.GetComponentsInChildren<Text>().Any(t => t.text == text);
    void Call(string name, params object[] values) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, values);
}
