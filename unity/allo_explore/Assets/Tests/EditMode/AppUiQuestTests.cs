using System;
using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppUiQuestTests
{
    const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    GameObject _root;
    AppUi _ui;
    AppState _previous;
    int _revision;

    [SetUp] public void SetUp()
    {
        _previous = AppSession.State;
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, null);
        Receive(State());
        _root = new GameObject("Companion quest UI"); _ui = _root.AddComponent<AppUi>();
        if (Get<RectTransform>("_safe") == null) Call("Awake");
        Call("OnState", AppSession.State); BuildMap();
    }
    [TearDown] public void TearDown()
    {
        Object.DestroyImmediate(_root);
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous);
    }

    [Test] public void MarkerBadgeOpensExactDetailWithoutOpeningQuestBody()
    {
        var badge = Named("Quest marker owned-second");
        Assert.NotNull(badge); Assert.AreEqual("?", badge.GetComponentInChildren<Text>().text);
        Assert.IsFalse(badge.GetComponent<Image>().raycastTarget, "badge must preserve marker drag and tap");
        Marker("owned-second").GetComponent<Button>().onClick.Invoke(); BuildMap();
        Assert.AreEqual("owned-second", Get<string>("_villageCreatureId"));
        Assert.NotNull(Named("Quest invitation owned-second"));
        Assert.IsFalse(HasText("초록빛을 찾아볼까?"));
        Assert.IsNull(ButtonNamed("함께하기"));
    }

    [Test] public void EvenOpenedSnapshotWaitsForExplicitQuestionButton()
    {
        Receive(State(opened: true)); OpenDetail();
        Assert.IsFalse(HasText("초록빛을 찾아볼까?"));
        OpenQuest();
        Assert.IsTrue(HasText("초록빛을 찾아볼까?"));
        Assert.NotNull(ButtonNamed("함께하기")); Assert.NotNull(ButtonNamed("나중에"));
    }

    [Test] public void ExplicitOpenWaitsForHostAndBackClosesCardBeforeDetail()
    {
        OpenDetail(); OpenQuest();
        Assert.IsFalse(HasText("초록빛을 찾아볼까?"));
        Receive(State(opened: true)); BuildMap();
        Assert.IsTrue(HasText("초록빛을 찾아볼까?"));
        Allo.Bridge.FlutterBridge.HandleBack(); BuildMap();
        Assert.IsFalse(HasText("초록빛을 찾아볼까?"));
        Assert.AreEqual("owned-second", Get<string>("_villageCreatureId"));
        Allo.Bridge.FlutterBridge.HandleBack(); BuildMap();
        Assert.IsNull(Get<string>("_villageCreatureId"));
    }

    [Test] public void AcceptedStoryUsesExplicitSelfReportAndCompletedHasNoCompletionAction()
    {
        Receive(State(opened: true, status: "accepted")); OpenDetail(); OpenQuest();
        Assert.NotNull(ButtonNamed("찾아봤어"));
        Assert.IsTrue(HasText("주변의 초록빛을 찾아보고 직접 알려 주세요."));
        Assert.IsNull(ButtonNamed("함께하기"));
        Receive(State(opened: true, status: "completed")); BuildMap();
        Assert.IsTrue(HasText("함께해 줘서 고마워!")); Assert.IsNull(ButtonNamed("찾아봤어"));
        Assert.IsNull(Named("Quest marker owned-second"));
    }

    [Test] public void TravelSelectionAndGuardianProposalAreSeparateFromAcceptance()
    {
        Receive(State(opened: true, kind: "travel")); OpenDetail(); OpenQuest();
        Assert.NotNull(ButtonNamed("을왕리 · 바다"));
        Assert.IsFalse(ButtonNamed("함께하기").interactable, "choose an exact destination before accepting");
        ButtonNamed("을왕리 · 바다").onClick.Invoke(); BuildMap();
        Assert.IsTrue(ButtonNamed("함께하기").interactable);
        Assert.IsNull(ButtonNamed("보호자에게 여행 제안"));
        Receive(State(opened: true, kind: "travel", status: "accepted", target: true)); BuildMap();
        Assert.IsTrue(ButtonNamed("보호자에게 여행 제안").interactable);
        Assert.IsTrue(HasText("보호자가 차량에서 확인한 뒤 길 안내를 시작해요."));
    }

    [Test] public void BusyErrorAndFoodReuseExistingCareControls()
    {
        Receive(State(opened: true, status: "accepted", kind: "food")); OpenDetail(); OpenQuest();
        Receive(State(opened: true, status: "accepted", kind: "food", busy: true)); BuildMap();
        Assert.IsTrue(HasText("부탁을 확인하고 있어요."));
        Receive(State(opened: true, status: "accepted", kind: "food", error: "저장하지 못했어요.")); BuildMap();
        Assert.IsTrue(HasText("저장하지 못했어요."));
        Assert.IsTrue(HasText("아래 요리 주기에서 음식을 나눠 주세요."));
        Assert.NotNull(ButtonNamed("베리 간식  2개 · 1개 주기"));
        Assert.IsNull(ButtonNamed("찾아봤어"));
    }

    [Test] public void DexIncludesQuestForOwnedFriendOutsideVillageSelection()
    {
        var state = State(opened: true, view: "dex"); Receive(state);
        Set("_selectedCreature", "owned-hidden"); ClearContent(); Call("BuildDex");
        Assert.NotNull(Named("Quest invitation owned-hidden"));
        Assert.IsFalse(HasText("초록빛을 찾아볼까?"));
        LogAssert.Expect(LogType.Log, "[AndroidHost] Unity intent sent");
        Named("Quest invitation owned-hidden").GetComponent<Button>().onClick.Invoke();
        ClearContent(); Call("BuildDex");
        Assert.AreEqual("owned-hidden", Get<string>("_selectedCreature"));
        Assert.IsTrue(HasText("초록빛을 찾아볼까?"));
        Allo.Bridge.FlutterBridge.HandleBack(); ClearContent(); Call("BuildDex");
        Assert.IsFalse(HasText("초록빛을 찾아볼까?"));
    }

    [Test] public void QuestRemovalAndReplacementNeverReuseAnOpenedBody()
    {
        Receive(State(opened: true)); OpenDetail(); OpenQuest();
        var replacement = JsonUtility.ToJson(State(opened: true)).Replace("quest-second", "quest-replacement");
        Receive(JsonUtility.FromJson<AppState>(replacement)); BuildMap();
        Assert.IsFalse(HasText("초록빛을 찾아볼까?"));
        Receive(JsonUtility.FromJson<AppState>(JsonUtility.ToJson(State()).Replace("\"quests\":[", "\"ignoredQuests\":["))); BuildMap();
        Assert.IsNull(Named("Quest invitation owned-second"));
        Assert.NotNull(ButtonNamed("베리 간식  2개 · 1개 주기"));
    }

    [Test] public void DetailCloseButtonClosesOpenedQuestAndInspector()
    {
        Receive(State(opened: true)); OpenDetail(); OpenQuest();
        ButtonNamed("상세 닫기").onClick.Invoke(); BuildMap();
        Assert.IsNull(Get<string>("_villageCreatureId"));
        Assert.IsNull(Named("Village character detail"));
    }

    [Test] public void DexBackClosesFoodConfirmationBeforeQuestBody()
    {
        Receive(State(opened: true, view: "dex"));
        Set("_selectedCreature", "owned-hidden"); ClearContent(); Call("BuildDex");
        LogAssert.Expect(LogType.Log, "[AndroidHost] Unity intent sent");
        Named("Quest invitation owned-hidden").GetComponent<Button>().onClick.Invoke();
        Set("_confirmAction", (Action)(() => { })); Set("_confirmTitle", "요리 주기");
        Allo.Bridge.FlutterBridge.HandleBack();
        Assert.IsNull(Get<Action>("_confirmAction"));
        ClearContent(); Call("BuildDex");
        Assert.IsTrue(HasText("초록빛을 찾아볼까?"));
        Assert.AreEqual("owned-hidden", Get<string>("_selectedCreature"));
    }

    [TestCase("fold")]
    [TestCase("back")]
    [TestCase("header")]
    [TestCase("navigate")]
    [TestCase("friend")]
    [TestCase("busy")]
    public void ExplicitDismissNotifiesHostBeforeClearingCurrentQuest(string path)
    {
        Receive(State(opened: true, status: "completed")); OpenDetail(); OpenQuest();
        Assert.AreEqual("quest-second", Get<string>("_questId"));
        if (path == "busy")
        {
            var state = State(opened: true, status: "completed", busy: true); state.busy = true;
            Receive(state); BuildMap();
        }
        var intents = CountIntentsDuring(() =>
        {
            switch (path)
            {
                case "back": Allo.Bridge.FlutterBridge.HandleBack(); break;
                case "header": ButtonNamed("상세 닫기").onClick.Invoke(); break;
                case "navigate": Call("Navigate", "inventory"); break;
                case "friend": Call("OpenVillageFriend", "owned-first"); break;
                default: ButtonNamed("부탁 접기").onClick.Invoke(); break;
            }
        });
        Assert.AreEqual(path == "navigate" ? 2 : 1, intents, "dismiss emits one host intent; navigation additionally emits navigate");
        Assert.IsNull(Get<string>("_questId"));
    }

    [TestCase("species")]
    [TestCase("instance")]
    public void DexSelectionDismissesCurrentQuestOnHost(string path)
    {
        Receive(State(opened: true, status: "completed", view: "dex"));
        Set("_selectedCreature", "owned-hidden"); ClearContent(); Call("BuildDex");
        Named("Quest invitation owned-hidden").GetComponent<Button>().onClick.Invoke();
        ClearContent(); Call("BuildDex");
        var intents = CountIntentsDuring(() =>
        {
            if (path == "species") Named("Dex grid").GetComponentInChildren<Button>().onClick.Invoke();
            else ButtonNamed("첫 친구 · first").onClick.Invoke();
        });
        Assert.AreEqual(1, intents);
        Assert.IsNull(Get<string>("_questId"));
    }

    [Test] public void AuthoritativeQuestReplacementNeverEmitsStaleDismissal()
    {
        Receive(State(opened: true)); OpenDetail(); OpenQuest();
        var replacement = JsonUtility.FromJson<AppState>(JsonUtility.ToJson(State(opened: true)).Replace("quest-second", "quest-new"));
        Assert.AreEqual(0, CountIntentsDuring(() => Receive(replacement)));
        Assert.IsNull(Get<string>("_questId"));
    }

    [Test] public void ExplicitLaterEmitsExactlyOneHostIntent()
    {
        Receive(State(opened: true)); OpenDetail(); OpenQuest();
        Assert.AreEqual(1, CountIntentsDuring(() => ButtonNamed("나중에").onClick.Invoke()));
        Assert.IsNull(Get<string>("_questId"));
    }

    static int CountIntentsDuring(Action action)
    {
        var intents = 0;
        Application.LogCallback capture = (message, trace, kind) =>
        {
            if (message == "[AndroidHost] Unity intent sent") intents++;
        };
        Application.logMessageReceived += capture;
        try { action(); }
        finally { Application.logMessageReceived -= capture; }
        return intents;
    }

    [Test] public void IntentDtoCarriesStableQuestAndPlaceIds()
    {
        Assert.NotNull(typeof(AppAction).GetField("questId"));
        Assert.NotNull(typeof(AppAction).GetField("placeId"));
        var body = JsonUtility.FromJson<AppAction>("{\"creatureId\":\"owned-second\",\"questId\":\"quest-second\",\"placeId\":\"place-coast\"}");
        var json = JsonUtility.ToJson(AppSession.CreateAction("acceptQuest", body));
        StringAssert.Contains("\"questId\":\"quest-second\"", json);
        StringAssert.Contains("\"placeId\":\"place-coast\"", json);
    }

    AppState State(bool opened = false, string status = "offered", string kind = "story", bool busy = false, string error = "", string view = "home", bool target = false)
    {
        var quest = "\"available\":true,\"opened\":" + opened.ToString().ToLowerInvariant() + ",\"busy\":" + busy.ToString().ToLowerInvariant() +
            ",\"status\":\"" + status + "\",\"kind\":\"" + kind + "\",\"title\":\"작은 부탁\",\"text\":\"초록빛을 찾아볼까?\",\"error\":\"" + error +
            "\",\"requirement\":\"주변의 초록빛을 찾아보고 직접 알려 주세요.\",\"targetPlaceId\":\"" + (target ? "place-coast" : "") + "\",\"candidates\":[{\"placeId\":\"place-coast\",\"name\":\"을왕리\",\"region\":\"coast\"}]";
        return JsonUtility.FromJson<AppState>("{\"view\":\"" + view + "\",\"ready\":true,\"villageCreatureIds\":[\"owned-first\",\"owned-second\"],\"creatures\":[{\"id\":\"owned-first\",\"speciesId\":\"road_sprout\",\"name\":\"첫 친구\"},{\"id\":\"owned-second\",\"speciesId\":\"road_sprout\",\"name\":\"두 번째 친구\"},{\"id\":\"owned-hidden\",\"speciesId\":\"road_sprout\",\"name\":\"숨은 친구\"}],\"dex\":[{\"id\":\"road_sprout\",\"name\":\"길싹이\",\"collected\":true}],\"foods\":[{\"id\":\"berry_snack\",\"label\":\"베리 간식\",\"count\":2}],\"quests\":[{\"creatureId\":\"owned-second\",\"questId\":\"quest-second\"," + quest + "},{\"creatureId\":\"owned-hidden\",\"questId\":\"quest-hidden\"," + quest + "}]}");
    }
    void Receive(AppState state) { state.revision = ++_revision; AppSession.Receive(state); if (_ui != null) Call("OnState", state); }
    void OpenDetail() { Marker("owned-second").GetComponent<Button>().onClick.Invoke(); BuildMap(); }
    void OpenQuest()
    {
        LogAssert.Expect(LogType.Log, "[AndroidHost] Unity intent sent");
        Named("Quest invitation owned-second").GetComponent<Button>().onClick.Invoke(); BuildMap();
    }
    void BuildMap() { ClearContent(); Call("BuildVillageMap", 0f, true); Canvas.ForceUpdateCanvases(); }
    void ClearContent() { foreach (Transform child in Get<RectTransform>("_content").Cast<Transform>().ToArray()) Object.DestroyImmediate(child.gameObject); }
    Transform Marker(string id) => Get<RectTransform>("_villageContent").Find("Village friend " + id);
    Transform Named(string name) => _root.GetComponentsInChildren<Transform>().SingleOrDefault(t => t.name == name);
    Button ButtonNamed(string text) => _root.GetComponentsInChildren<Button>().SingleOrDefault(b => b.GetComponentInChildren<Text>()?.text == text);
    bool HasText(string text) => _root.GetComponentsInChildren<Text>().Any(t => t.text == text);
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Set(string name, object value) => typeof(AppUi).GetField(name, Private).SetValue(_ui, value);
    void Call(string name, params object[] args) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, args);
}
