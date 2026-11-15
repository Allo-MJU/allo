using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class LiveSeaIntegrationTests
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
        _root = new GameObject("Live sea integration");
        _ui = _root.AddComponent<AppUi>();
        if (Get<RectTransform>("_safe") == null) Call("Awake");
    }

    [TearDown] public void TearDown()
    {
        Object.DestroyImmediate(_root);
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous);
    }

    [Test] public void NotebookTemporarilyOwnsRewardCabinAndRestoresSavedNoticeAfterHostClosesIt()
    {
        var state = State("cabin");
        state.collectionRewardForTrip = true;
        Apply(state); Build();
        Assert.NotNull(ButtonNamed("탐험 노트"));
        Assert.NotNull(Named("Collection completion gift"));

        state = Copy(state); state.story.notebookOpen = true;
        Apply(state); Build();
        Assert.IsTrue(_root.GetComponent<StoryOverlay>().ShowingNotebook);
        Assert.IsTrue(_ui.CabinGesturesBlocked);
        Assert.IsNull(Named("Collection completion gift"));
        Assert.IsNull(Named("Cabin item circles"));
        Assert.IsFalse(CabinEgg.CanInteract(state, "cabin", "egg"));
        Assert.AreEqual(AppBackAction.PauseStory, AppSession.BackActionFor(state));
        Allo.Bridge.FlutterBridge.HandleBack();
        Assert.IsTrue(state.story.notebookOpen, "Back requests host closure without changing authoritative state");

        state = Copy(state); state.story.notebookOpen = false;
        Apply(state); Build();
        Assert.IsFalse(StoryOverlay.CapturingInput);
        Assert.NotNull(ButtonNamed("탐험 노트"));
        Assert.NotNull(Named("Collection completion gift"));
    }

    [Test] public void SelectionDismissesQuestAndInspectorAndRejectsTheirRetainedOpenCallbacks()
    {
        Apply(State("home")); Build();
        Call("OpenVillageFriend", "friend");
        Call("OpenQuest", "friend", "quest");
        Assert.AreEqual("quest", Get<string>("_questId"));
        Assert.IsTrue(_ui.StoryUiBlocked, "actual opened quest blocks a competing notebook request");
        Call("OpenVillageSelection");
        Assert.IsTrue(Get<bool>("_villageSelectionOpen"));
        Assert.IsTrue(_ui.StoryUiBlocked);
        Assert.IsNull(Get<string>("_questId"));
        Assert.IsNull(Get<string>("_villageCreatureId"));
        Call("OpenQuest", "friend", "quest");
        Assert.IsNull(Get<string>("_questId"), "retained quest callback cannot compete with selection");
    }

    [Test] public void RetainedSelectionSaveCannotClearVillageFriendsDuringNotebookCapture()
    {
        Apply(State("home")); Build();
        Call("OpenVillageSelection"); Build();
        var save = ButtonNamed("저장").onClick;
        var cabin = State("cabin"); cabin.story.notebookOpen = true;
        Apply(cabin); Build();
        save.Invoke();
        Assert.IsNull(Get<string>("_villageSelectionPending"));
        CollectionAssert.AreEqual(new[] { "friend" }, cabin.villageCreatureIds);
        Assert.IsTrue(_root.GetComponent<StoryOverlay>().ShowingNotebook);
    }

    [TestCase(false)]
    [TestCase(true)]
    public void CabinNotebookSnapshotReleasesPreviousVillageOwnerBeforeStoryCapturesInput(bool selection)
    {
        Apply(State("home")); Build();
        if (selection) Call("OpenVillageSelection");
        else { Call("OpenVillageFriend", "friend"); Call("OpenQuest", "friend", "quest"); }
        var cabin = State("cabin"); cabin.story.notebookOpen = true;
        Apply(cabin); Build();
        Assert.IsFalse(Get<bool>("_villageSelectionOpen"));
        Assert.IsNull(Get<string>("_questId"));
        Assert.IsNull(Get<string>("_villageCreatureId"));
        Assert.IsTrue(_root.GetComponent<StoryOverlay>().ShowingNotebook);
        Assert.IsFalse(_ui.StoryUiBlocked, "story ownership must not feed into its own host blocking signal");
        Call("OpenVillageSelection"); Call("OpenQuest", "friend", "quest");
        Assert.IsFalse(Get<bool>("_villageSelectionOpen"));
        Assert.IsNull(Get<string>("_questId"));
        Assert.AreEqual(AppBackAction.PauseStory, AppSession.BackActionFor(cabin));
    }

    static AppState State(string view) => new AppState
    {
        view = view, ready = true, connected = true, villageSelectionReady = true,
        villageCreatureIds = new[] { "friend" },
        creatures = new[] { new CreatureState { id = "friend", speciesId = "road_sprout", name = "친구" } },
        quests = new[] { new QuestState { creatureId = "friend", questId = "quest", available = true, opened = true, status = "offered", kind = "story" } },
        egg = new EggState { id = "egg", active = true, phase = "caring" },
        story = new StoryState { ready = true, canOpen = true, canPlay = true }
    };
    static AppState Copy(AppState state) => JsonUtility.FromJson<AppState>(JsonUtility.ToJson(state));
    void Apply(AppState state) { state.revision = ++_revision; AppSession.Receive(state); Call("OnState", state); }
    void Build()
    {
        foreach (Transform child in Get<RectTransform>("_content").Cast<Transform>().ToArray()) Object.DestroyImmediate(child.gameObject);
        Call(AppSession.CurrentView == "cabin" ? "BuildCabin" : "BuildHome");
        Canvas.ForceUpdateCanvases();
    }
    Transform Named(string name) => _root.GetComponentsInChildren<Transform>().SingleOrDefault(t => t.name == name);
    Button ButtonNamed(string text) => _root.GetComponentsInChildren<Button>().SingleOrDefault(b => b.GetComponentInChildren<Text>()?.text == text);
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Call(string name, params object[] args) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, args);
}
