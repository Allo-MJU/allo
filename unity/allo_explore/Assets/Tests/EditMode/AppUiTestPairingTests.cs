using System;
using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppUiTestPairingTests
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
        AppSession.Receive(new AppState { revision = 1, view = "pairing", ready = true, isDemo = true });
        _root = new GameObject("Test pairing UI");
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
    public void DemoCanRequestATestConnectionWithoutTypingPairingDetails()
    {
        Call("BuildPairing");
        Assert.IsTrue(string.IsNullOrEmpty(Get<string>("_sessionId")));
        Assert.IsTrue(string.IsNullOrEmpty(Get<string>("_pairCode")));
        var button = TestConnectionButton();
        Assert.NotNull(button);
        Assert.IsTrue(button.interactable);
        LogAssert.Expect(LogType.Log, "[AndroidHost] Unity intent sent");
        button.onClick.Invoke();
    }

    [Test]
    public void RealVehicleModeDoesNotOfferATestConnection()
    {
        Receive(ready: true, busy: false, demo: false);
        Call("BuildPairing");
        Assert.IsNull(TestConnectionButton());
    }

    [TestCase(true, true)]
    [TestCase(false, false)]
    public void UnavailableActionsDisableTestConnectionAndRejectItsIntent(bool ready, bool busy)
    {
        Receive(ready, busy, demo: true);
        Call("BuildPairing");
        var button = TestConnectionButton();
        Assert.NotNull(button);
        Assert.IsFalse(button.interactable);
        button.onClick.Invoke();
        LogAssert.NoUnexpectedReceived();
    }

    [TestCase(true, "테스트 연결됨")]
    [TestCase(false, "차량 연결")]
    public void ConnectionChipDistinguishesSuccessfulDemoAndVehicleConnections(bool demo, string label)
    {
        AppSession.Receive(new AppState { revision = 2, view = "cabin", ready = true, connected = true, isDemo = demo });
        Call("OnState", AppSession.State); Call("UpdateChrome");
        Assert.AreEqual(label, Get<Text>("_connection").text);
    }

    void Receive(bool ready, bool busy, bool demo)
    {
        AppSession.Receive(new AppState { revision = 2, view = "pairing", ready = ready, busy = busy, isDemo = demo });
        Call("OnState", AppSession.State);
    }
    Button TestConnectionButton() => _root.GetComponentsInChildren<Button>().SingleOrDefault(b => b.GetComponentInChildren<Text>()?.text == "테스트 연결");
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Call(string name, params object[] values) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, values);
}
