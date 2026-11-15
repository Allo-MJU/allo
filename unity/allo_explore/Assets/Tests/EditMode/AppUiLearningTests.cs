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
    public void EggGetsFourItemChoicesAndNeverCompanionChat()
    {
        Call("BuildCabin");
        foreach (var label in new[] { "간식", "물", "공", "인형" })
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
        Assert.IsNull(ButtonNamed("행동"));
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
    public void DirectConversationShowsLatestReplyAndComposerWithoutModeChoices()
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "chat";
        Apply(state); Call("BuildCabin");
        Assert.IsTrue(HasText(state.learning.text));
        Assert.NotNull(_root.GetComponentInChildren<InputField>());
        Assert.IsNull(ButtonNamed("이야기 듣기"));
        Assert.IsNull(ButtonNamed("다음 이야기"));
        Assert.NotNull(AppUi.CompanionInvitationIntent(state, "road_sprout"));
    }

    [TestCase(true, "")]
    [TestCase(false, "연결하지 못했어요. 다시 시도해 주세요.")]
    public void DirectConversationWaitAndErrorNeverFabricateReply(bool busy, string error)
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "chat";
        state.learning.text = ""; state.learning.busy = busy; state.learning.error = error;
        Apply(state); Call("BuildCabin");
        Assert.IsFalse(HasText("새싹이 햇빛을 만났어요."));
        if (busy) Assert.IsTrue(HasText("친구가 답을 생각하고 있어요."));
        if (!string.IsNullOrEmpty(error)) Assert.IsTrue(HasText(error));
    }

    [Test]
    public void SelectedBuddyKeepsIndependentEggHudAndGestures()
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "chat"; state.egg.photoRequired = true;
        Apply(state); Call("BuildCabin");
        Assert.IsTrue(_root.GetComponentsInChildren<Transform>().Any(t => t.name == "Cabin affinity HUD"));
        Assert.NotNull(ButtonNamed("함께 사진 찍기"));
        Assert.NotNull(ButtonNamed("자리와 돌보기"));
        Assert.IsFalse(CabinEgg.CanInteract(state, "cabin", "new-egg"), "photo quest gates egg care while companion care stays independent");
        var intent = AppUi.CommonCareIntent(state, "pet");
        Assert.AreEqual("owned-a", intent.creatureId);
        Assert.IsNotNull(ButtonNamed("간식"));
    }

    [Test]
    public void DisconnectedCabinUsesHeaderQrEntryEvenWithStaleEggBuddyAndStory()
    {
        var state = State(); SelectFriend(state); state.connected = false;
        state.story = new StoryState { active = true, available = true, canPlay = true };
        Apply(state); Call("BuildCabin"); Call("UpdateChrome");
        var entry = ButtonNamed("차량 QR 연결하기");
        Assert.IsNotNull(entry);
        var title = (Text)typeof(AppUi).GetField("_title", Private).GetValue(_ui);
        Assert.AreSame(title.transform.parent, entry.transform.parent, "QR entry occupies the former cabin title slot");
        Assert.IsNull(ButtonNamed("차량 연결하기"), "no bottom connect control remains");
        Assert.IsNull(ButtonNamed("간식"));
        Assert.IsFalse(HasText("차 안에서 함께하기"));
        Assert.IsFalse(AppUi.CanCommonCare(state, "pet"));
        Assert.IsFalse(CabinEgg.CanInteract(state, "cabin", "new-egg"));
    }

    [Test]
    public void DisconnectDismissesEggDrawersAndConfirmationBeforeRenderingEmptyCabin()
    {
        typeof(AppUi).GetField("_zoneDrawer", Private).SetValue(_ui, true);
        Call("Confirm", "돌보기 그만두기", "확인", (Action)(() => {}));
        var state = State(); state.connected = false; Apply(state);
        Call("Render"); Call("UpdateChrome");
        Assert.IsNull(ButtonNamed("확인하고 진행"));
        Assert.IsNotNull(ButtonNamed("차량 QR 연결하기"));
        Assert.IsFalse(_ui.StoryUiBlocked);
    }

    [TestCase(false, "new-egg")]
    [TestCase(true, "replacement-egg")]
    public void EndingOrReplacingEggClearsItsHiddenModalWithoutBlockingBuddy(bool active, string eggId)
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "chat";
        Apply(state);
        Call("SendLearning", "companionSpeech", "owned-a", null);
        typeof(AppUi).GetField("_zoneDrawer", Private).SetValue(_ui, true);
        typeof(AppUi).GetField("_speechDrawer", Private).SetValue(_ui, true);
        Call("Confirm", "돌보기 그만두기", "확인", (Action)(() => {}));
        Assert.IsTrue(_ui.StoryUiBlocked);

        var next = State(); SelectFriend(next); next.learning.conversationMode = "chat";
        next.egg.active = active; next.egg.id = eggId; next.egg.phase = active ? "incubating" : "failed";
        Apply(next);
        Assert.IsFalse(_ui.StoryUiBlocked);
        Assert.IsFalse((bool)typeof(AppUi).GetField("_zoneDrawer", Private).GetValue(_ui));
        Assert.IsFalse((bool)typeof(AppUi).GetField("_speechDrawer", Private).GetValue(_ui));
        Assert.IsNull(typeof(AppUi).GetField("_confirmAction", Private).GetValue(_ui));
        Assert.IsTrue((bool)typeof(AppUi).GetField("_nativeSpeechExpected", Private).GetValue(_ui),
            "ending egg care must not cancel the buddy microphone request");
        Call("BuildCabin");
        Assert.IsTrue(ButtonNamed("친구에게 말 걸기").interactable);
        Assert.IsTrue(AppUi.CanCommonCare(next, "snack"));
        Assert.NotNull(ButtonNamed("간식"));
        Assert.IsNotNull(AppUi.CompanionInvitationIntent(next, "road_sprout"));
    }

    [TestCase(true)]
    [TestCase(false)]
    public void PairingQrAvailabilityMatchesTheHost(bool available)
    {
        var state = State(); state.view = "pairing"; state.pairingScanAvailable = available;
        Apply(state); Call("Render");
        Assert.AreEqual(available, ButtonNamed("차량 QR 스캔").interactable);
        Assert.IsFalse(ButtonNamed("차량과 연결하기").interactable);
    }

    [Test]
    public void DirectConversationDisplaysOnlyTheLatestOptionalUserTurn()
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "chat";
        state.learning.lastUserText = "왜 초록색이야?";
        Apply(state); Call("BuildCabin");
        Assert.IsTrue(HasText("나: 왜 초록색이야?"));
        Assert.IsTrue(HasText(state.learning.text));
        Assert.IsNull(ButtonNamed("이야기 듣기"));
        Assert.IsNull(ButtonNamed("이야기 다시 듣기"));
    }

    [Test]
    public void PairingViewIsAcceptedAndShowsManualFields()
    {
        var state = State(); state.view = "pairing";
        Assert.IsTrue(AppSession.Accepts(null, state));
        Apply(state); Call("Render");
        Assert.NotNull(ButtonNamed("차량 QR 스캔"));
        Assert.NotNull(ButtonNamed("차량과 연결하기"));
        Assert.AreEqual(2, _root.GetComponentsInChildren<InputField>().Length);
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
    public void LegacyStoryModeDoesNotRenderChapterControls()
    {
        var state = State(); SelectFriend(state); state.learning.conversationMode = "story";
        Apply(state); Call("BuildCabin");
        Assert.IsNull(ButtonNamed("다음 이야기"));
        Assert.IsNull(ButtonNamed("이야기 다시 듣기"));
        Assert.IsNull(_root.GetComponentInChildren<InputField>());
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
    public void StaleWindowStoryCannotHideOrCaptureDirectCabinControls()
    {
        var state = State(); SelectFriend(state);
        state.story = new StoryState { active = true, canPlay = true, available = true };
        Apply(state); Call("BuildCabin");
        Assert.IsTrue(AppUi.CanCompanionTalk(state));
        Assert.IsTrue(AppUi.CanCommonCare(state, "pet"));
        Assert.NotNull(ButtonNamed("간식"));
        Assert.IsNull(ButtonNamed("여행 노트"));
        Assert.IsNull(ButtonNamed("이야기 시작"));
        Assert.IsFalse(StoryOverlay.CapturingInput);
        Assert.IsNull(_root.GetComponent<StoryOverlay>());
        Assert.IsTrue(CabinEgg.CanInteract(state, "cabin", "new-egg"));
    }

    [Test]
    public void PairedCabinShowsFourIllustratedCirclesWithoutActionMenuOrTouchCareButtons()
    {
        Call("BuildCabin");
        foreach (var label in new[] { "간식", "물", "공", "인형" })
        {
            var button = ButtonNamed(label);
            Assert.IsNotNull(button, label);
            Assert.IsTrue(button.interactable);
            Assert.AreEqual(new Vector2(76, 76), ((RectTransform)button.transform).sizeDelta);
            Assert.IsNotNull(button.transform.Find("Item artwork").GetComponent<Image>().sprite);
        }
        foreach (var removed in new[] { "행동", "쓰다듬기", "알 쓰다듬기", "쿠션", "담요" })
            Assert.IsNull(ButtonNamed(removed), removed);
        Assert.IsFalse(_root.GetComponentsInChildren<Transform>().Any(t => t.name == "Cabin action sheet"));
    }

    [Test]
    public void BuddyAndEggKeepIndependentGestureRoutesAndCompactEggTools()
    {
        var state = State(); SelectFriend(state); state.egg.score = 42;
        Apply(state); Call("BuildCabin");
        Assert.AreEqual("owned-a", AppUi.CommonCareIntent(state, "pet").creatureId);
        Assert.AreEqual("petEgg", CabinEgg.EggIntent(state, "cabin", state.egg.id, "petEgg", 0).action);
        Assert.AreEqual(42, state.egg.score);
        Assert.IsNotNull(ButtonNamed("글로 말하기"));
        Assert.IsNotNull(ButtonNamed("자리와 돌보기"));
        Assert.IsFalse(_ui.CabinGesturesBlocked);
    }

    [Test]
    public void ItemCirclesReuseAntialiasedArtWithoutChangingVillageSurface()
    {
        var original = (Sprite)typeof(AppUi).GetField("_round", Private).GetValue(_ui);
        Call("BuildCabin");
        var disc = ButtonNamed("간식").GetComponent<Image>().sprite;
        var artwork = ButtonNamed("간식").transform.Find("Item artwork").GetComponent<Image>().sprite;
        Assert.GreaterOrEqual(disc.texture.width, 128);
        Assert.AreEqual(FilterMode.Bilinear, disc.texture.filterMode);
        Assert.IsTrue(disc.texture.GetPixels().Any(p => p.a > 0 && p.a < 1));
        Assert.AreEqual(0, disc.texture.GetPixel(0, 0).a);
        RebuildCabin();
        Assert.AreSame(disc, ButtonNamed("간식").GetComponent<Image>().sprite);
        Assert.AreSame(artwork, ButtonNamed("간식").transform.Find("Item artwork").GetComponent<Image>().sprite);
        Assert.AreSame(original, typeof(AppUi).GetField("_round", Private).GetValue(_ui));
    }

    [Test]
    public void ChoosingEggTextOrZoneKeepsOnlyOneDrawerAndBlocksWorldGestures()
    {
        Call("BuildCabin");
        ButtonNamed("글로 말하기").onClick.Invoke(); RebuildCabin();
        Assert.IsNotNull(ButtonNamed("대화 닫기"));
        Assert.IsTrue(_ui.CabinGesturesBlocked);
        Assert.IsFalse((bool)typeof(AppUi).GetField("_zoneDrawer", Private).GetValue(_ui));
        ButtonNamed("대화 닫기").onClick.Invoke(); RebuildCabin();
        ButtonNamed("자리와 돌보기").onClick.Invoke(); RebuildCabin();
        Assert.IsNotNull(ButtonNamed("자리 메뉴 닫기"));
        Assert.IsNull(ButtonNamed("대화 닫기"));
        Assert.IsTrue(_ui.CabinGesturesBlocked);
    }

    [Test]
    public void PhotoGateKeepsActionablePhotoAndRecoveryWithoutOldMenu()
    {
        var state = State(); state.egg.photoRequired = true; state.photoAvailable = true;
        Apply(state); Call("BuildCabin");
        Assert.IsTrue(ButtonNamed("함께 사진 찍기").interactable);
        Assert.IsTrue(ButtonNamed("보류한 사진 확인").interactable);
        Assert.IsFalse(ButtonNamed("말 걸기").interactable);
        Assert.IsNull(ButtonNamed("행동"));
    }

    static AppState State() => new AppState
    {
        revision = 1, view = "cabin", ready = true, connected = true, speechAvailable = true,
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
    void RebuildCabin()
    {
        var content = (RectTransform)typeof(AppUi).GetField("_content", Private).GetValue(_ui);
        foreach (var child in content.Cast<Transform>().ToArray()) Object.DestroyImmediate(child.gameObject);
        Call("BuildCabin");
    }
    void Apply(AppState state) { state.revision = AppSession.State.revision + 1; AppSession.Receive(state); Call("OnState", AppSession.State); }
    Button ButtonNamed(string text) => _root.GetComponentsInChildren<Button>().SingleOrDefault(b => b.GetComponentInChildren<Text>()?.text == text);
    bool HasText(string text) => _root.GetComponentsInChildren<Text>().Any(t => t.text == text);
    void Call(string name, params object[] values) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, values);
}
