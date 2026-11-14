using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppUiVehicleCompanionTests
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
        _root = new GameObject("Vehicle companion Dex UI"); _ui = _root.AddComponent<AppUi>();
        if (Get<RectTransform>("_safe") == null) Call("Awake");
        Call("OnState", AppSession.State);
    }
    [TearDown]
    public void TearDown() { Object.DestroyImmediate(_root); typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous); }

    [Test]
    public void ConnectedOwnedDetailKeepsTheSelectedInstanceAndOffersVehicleCompanion()
    {
        typeof(AppUi).GetField("_selectedCreature", Private).SetValue(_ui, "owned-second");
        Call("BuildDex");
        Assert.AreEqual("owned-second", Get<string>("_selectedCreature"));
        var choose = ButtonNamed("차 안으로 데리고 오기");
        Assert.NotNull(choose); Assert.IsTrue(choose.interactable);
    }

    [Test]
    public void DisconnectedDetailDisablesSelectionAndExplainsHowToConnect()
    {
        var state = State(); state.revision = 2; state.connected = false;
        AppSession.Receive(state); Call("OnState", AppSession.State); Call("BuildDex");
        var choose = ButtonNamed("차 안으로 데리고 오기");
        Assert.NotNull(choose); Assert.IsFalse(choose.interactable);
        Assert.IsTrue(HasText("차량과 연결한 뒤 함께할 친구를 선택할 수 있어요."));
        Assert.IsTrue(ButtonNamed("낚시 저장 다시 확인").interactable, "pending local-save recovery remains available offline");
    }

    [Test]
    public void DetailShowsActualFishingCountErrorAndSaveRetry()
    {
        Call("BuildDex");
        Assert.IsTrue(HasText("차량 친구의 관찰 기록 7건"));
        Assert.IsTrue(HasText("관찰 기록을 저장하지 못했어요."));
        var retry = ButtonNamed("낚시 저장 다시 확인"); Assert.NotNull(retry); Assert.IsTrue(retry.interactable);
    }

    [Test]
    public void UncollectedDetailDisplaysExistingHintWithoutOwnedCompanionSelection()
    {
        var state = State(); state.revision = 2; state.dex[0].collected = false;
        AppSession.Receive(state); Call("OnState", AppSession.State); Call("BuildDex");
        Assert.IsTrue(HasText("비 오는 길에서 만나 보세요."));
        Assert.IsNull(ButtonNamed("차 안으로 데리고 오기"));
    }

    static AppState State() => new AppState
    {
        revision = 1, view = "dex", ready = true, connected = true, fishingRecords = 7, fishingError = "관찰 기록을 저장하지 못했어요.",
        dex = new[] { new DexState { id = "road_sprout", name = "도로새싹", collected = true, description = "비 오는 길에서 만나 보세요." } },
        creatures = new[] { new CreatureState { id = "owned-first", speciesId = "road_sprout", name = "첫 친구" }, new CreatureState { id = "owned-second", speciesId = "road_sprout", name = "두 번째 친구" } }
    };
    Button ButtonNamed(string text) => _root.GetComponentsInChildren<Button>().SingleOrDefault(b => b.GetComponentInChildren<Text>()?.text == text);
    bool HasText(string text) => _root.GetComponentsInChildren<Text>().Any(t => t.text == text);
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Call(string name, params object[] values) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, values);
}
