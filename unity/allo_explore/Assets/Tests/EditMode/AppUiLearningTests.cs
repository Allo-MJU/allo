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
    public void SummonedFriendIsSilentUntilTappedAndHasNoCabinSelectors()
    {
        var state = State(); SelectFriend(state); Apply(state); Call("BuildCabin");
        Assert.IsNull(ButtonNamed("다음 이야기"));
        Assert.IsNull(ButtonNamed("친구 고르기"));
        Assert.IsNull(ButtonNamed("이 알과 시작하기"));
        Assert.IsFalse(HasText("새싹이 햇빛을 만났어요."));
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
    public void SessionEndDisablesCareAndHidesDialogue()
    {
        var state = State(); SelectFriend(state); state.sessionEnded = true; Apply(state);
        Call("BuildCabin");
        Assert.IsFalse(ButtonNamed("간식").interactable);
        Assert.IsNull(ButtonNamed("다음 이야기"));
        Assert.IsNull(ButtonNamed("목소리 끄기"));
    }

    [Test]
    public void CompanionMicrophoneUsesNativeAvailabilityIndependentlyFromEggEvaluation()
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "chat"; state.speechAvailable = false; Apply(state);
        Call("BuildCabin");
        Assert.IsTrue(ButtonNamed("친구에게 말 걸기").interactable);
    }

    [Test]
    public void InvitationMenuOffersOnlyTwoChoicesAndTargetsExactOwnedInstance()
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "menu";
        state.learning.invitationOpen = true; state.learning.invitationText = "나한테 궁금한 게 있는 거야?"; Apply(state); Call("BuildCabin");
        Assert.IsTrue(HasText("나한테 궁금한 게 있는 거야?"));
        Assert.IsTrue(ButtonNamed("이야기 듣기").interactable);
        Assert.IsTrue(ButtonNamed("말 걸기").interactable);
        Assert.IsNull(ButtonNamed("다음 이야기"));
        var intent = AppUi.CompanionInvitationIntent(state, "road_sprout");
        Assert.AreEqual("owned-a", intent.creatureId);
        Assert.AreEqual("road_sprout", intent.speciesId);
        Assert.IsNull(AppUi.CompanionInvitationIntent(state, "wrong-species"));
        state.learning.creatureId = "unowned";
        Assert.IsNull(AppUi.CompanionInvitationIntent(state, "road_sprout"));
    }

    [TestCase(true, "")]
    [TestCase(false, "연결하지 못했어요. 다시 시도해 주세요.")]
    [TestCase(false, "")]
    public void PendingFailedAndMissingServerInvitationNeverFabricateSuccess(bool busy, string error)
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "menu";
        state.learning.invitationOpen = true; state.learning.busy = busy; state.learning.error = error;
        Apply(state); Call("BuildCabin");
        Assert.IsFalse(HasText("나한테 궁금한 게 있는 거야?"));
        Assert.IsFalse(ButtonNamed("이야기 듣기").interactable);
        Assert.IsFalse(ButtonNamed("말 걸기").interactable);
        if (busy) Assert.IsTrue(HasText("친구의 답을 기다리고 있어요."));
        if (!string.IsNullOrEmpty(error)) Assert.IsTrue(HasText(error));
    }

    [Test]
    public void SuccessfulServerInvitationKeepsTextAlternativeWhenVoiceFails()
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "menu";
        state.learning.invitationOpen = true; state.learning.invitationText = "서버에서 온 초대";
        state.learning.error = "목소리를 재생하지 못했어요.";
        Apply(state); Call("BuildCabin");
        Assert.IsTrue(HasText("서버에서 온 초대"));
        Assert.IsTrue(HasText(state.learning.error));
        Assert.IsTrue(ButtonNamed("이야기 듣기").interactable);
    }

    [TestCase("home")]
    [TestCase("dex")]
    public void InactiveViewsCannotInviteCompanions(string view)
    {
        var state = State(); SelectFriend(state); state.view = view;
        Assert.IsNull(AppUi.CompanionInvitationIntent(state, "road_sprout"));
    }

    [Test]
    public void SessionEndAndInactiveTargetCannotInviteCompanions()
    {
        var state = State(); SelectFriend(state); state.sessionEnded = true;
        Assert.IsNull(AppUi.CompanionInvitationIntent(state, "road_sprout"));
        state.sessionEnded = false; state.learning.active = false;
        Assert.IsNull(AppUi.CompanionInvitationIntent(state, "road_sprout"));
    }

    [Test]
    public void NativeSpeechFocusLossPreservesInvitationBeforeRecordingSnapshotArrives()
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "chat";
        Apply(state); Call("BuildCabin");
        Call("SendLearning", "companionSpeech", "owned-a", null);
        Call("OnApplicationFocus", false); Call("OnApplicationPause", true);
        Assert.IsFalse((bool)typeof(AppUi).GetField("_invitationDismissed", Private).GetValue(_ui));
        Assert.IsFalse(((RectTransform)typeof(AppUi).GetField("_companionBubble", Private).GetValue(_ui)).gameObject.activeSelf);
        Call("OnApplicationPause", false); Call("OnApplicationFocus", true);
        Assert.IsFalse((bool)typeof(AppUi).GetField("_invitationDismissed", Private).GetValue(_ui));
        state.learning.recording = true; Apply(state);
        state.learning.recording = false; Apply(state);
        Call("OnApplicationFocus", false);
        Assert.IsTrue((bool)typeof(AppUi).GetField("_invitationDismissed", Private).GetValue(_ui), "completed native capture must not exempt later real backgrounding");
    }

    [Test]
    public void RecordingSnapshotPreservesNativeModalButOrdinaryBackgroundClosesInvitation()
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "chat";
        state.learning.recording = true; Apply(state); Call("BuildCabin");
        Call("OnApplicationPause", true);
        Assert.IsFalse((bool)typeof(AppUi).GetField("_invitationDismissed", Private).GetValue(_ui));
        state.learning.recording = false; Apply(state);
        Call("OnApplicationPause", true);
        Assert.IsTrue((bool)typeof(AppUi).GetField("_invitationDismissed", Private).GetValue(_ui));
    }

    [Test]
    public void UnavailableOwnedCompanionStillHasAnInvitationWithClearPreparationFeedback()
    {
        var state = State(); SelectFriend(state); state.learning.available = false;
        state.learning.conversationMode = "menu"; state.learning.invitationOpen = true;
        Apply(state); Call("BuildCabin");
        Assert.IsNotNull(AppUi.CompanionInvitationIntent(state, "road_sprout"));
        Assert.IsTrue(HasText("이 친구의 이야기는 준비 중이에요. 함께 놀 수 있어요."));
        Assert.IsFalse(ButtonNamed("이야기 듣기").interactable);
        Assert.IsFalse(ButtonNamed("말 걸기").interactable);
    }

    [Test]
    public void HeadAnchorRejectsBehindCameraAndOffscreenTargets()
    {
        var cameraGo = new GameObject("Anchor camera", typeof(Camera));
        try
        {
            var camera = cameraGo.GetComponent<Camera>();
            Assert.IsTrue(AppUi.HeadAnchorVisible(camera, new Vector3(0, 0, 2)));
            Assert.IsFalse(AppUi.HeadAnchorVisible(camera, new Vector3(0, 0, -2)));
            Assert.IsFalse(AppUi.HeadAnchorVisible(camera, new Vector3(100, 0, 2)));
        }
        finally { Object.DestroyImmediate(cameraGo); }
    }

    [Test]
    public void StoryModeKeepsNextRepeatWithoutChatFields()
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "story";
        Apply(state); Call("BuildCabin");
        Assert.IsTrue(ButtonNamed("다음 이야기").interactable);
        Assert.IsTrue(ButtonNamed("이야기 다시 듣기").interactable);
        Assert.IsNull(_root.GetComponentInChildren<InputField>());
        Assert.IsTrue(HasText(state.learning.text));
    }

    [Test]
    public void ActualCompanionTapEmitsInvitationWithoutPokingAndConsumesInactiveTap()
    {
        var state = State(); SelectFriend(state); Apply(state);
        var actor = new GameObject("Actual companion tap");
        var other = new GameObject("Unselected companion tap");
        var calls = 0;
        Action<string> tapped = species => { Assert.AreEqual("road_sprout", species); calls++; };
        Allo.Critters.CritterDirector.CompanionTapped += tapped;
        try
        {
            var director = actor.AddComponent<Allo.Critters.CritterDirector>();
            var view = actor.AddComponent<Allo.Critters.CritterView>();
            typeof(Allo.Critters.CritterView).GetProperty("Id").SetValue(view, "road_sprout");
            typeof(Allo.Critters.CritterDirector).GetProperty("CompanionId").SetValue(director, "road_sprout");
            var views = (System.Collections.Generic.Dictionary<string, Allo.Critters.CritterView>)typeof(Allo.Critters.CritterDirector).GetField("_views", Private).GetValue(director);
            views["road_sprout"] = view;
            Assert.IsTrue(director.InviteCompanion(view));
            Assert.AreEqual(1, calls);
            Assert.IsNull(view.Brain, "invitation does not invoke the legacy Poke/pose/reward route");
            Assert.IsFalse(director.InviteCompanion(other.AddComponent<Allo.Critters.CritterView>()));
            state.learning.active = false;
            Assert.IsTrue(director.InviteCompanion(view), "inactive selected taps must not fall back to legacy care rewards");
            Assert.AreEqual(1, calls);
        }
        finally
        {
            Allo.Critters.CritterDirector.CompanionTapped -= tapped;
            Object.DestroyImmediate(actor); Object.DestroyImmediate(other);
        }
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
