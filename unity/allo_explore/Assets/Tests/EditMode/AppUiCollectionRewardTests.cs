using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppUiCollectionRewardTests
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
        _root = new GameObject("Collection reward view test");
        _ui = _root.AddComponent<AppUi>();
        if (Get<RectTransform>("_safe") == null) Call("Awake");
    }

    [TearDown]
    public void TearDown()
    {
        Object.DestroyImmediate(_root);
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous);
    }

    [Test]
    public void SavedRewardShowsSnackNoticeAndSelectsFoodTab()
    {
        Show(true, true);
        var notice = Get<RectTransform>("_content").Find("Collection completion gift");
        Assert.NotNull(notice, "a trip without an egg needs its saved snack reward explained");
        Assert.IsTrue(notice.GetComponentsInChildren<Text>().Any(t => t.text.Contains("베리 간식 3개")));
        LogAssert.Expect(LogType.Log, "[AndroidHost] Unity intent sent");
        notice.GetComponentsInChildren<Button>().Single(b => b.GetComponentInChildren<Text>().text == "간식 확인").onClick.Invoke();
        Assert.AreEqual("foods", Get<string>("_supplyTab"));
        Assert.AreEqual("berry_snack", Get<string>("_selectedSupply"));
        Assert.AreEqual("cabin", AppSession.CurrentView, "navigation waits for the host snapshot");
    }

    [Test]
    public void UnsavedOrDisconnectedRewardDoesNotShowSuccess()
    {
        Show(false, true);
        Assert.IsNull(Get<RectTransform>("_content").Find("Collection completion gift"));
        Show(true, false);
        Assert.IsNull(Get<RectTransform>("_content").Find("Collection completion gift"));
    }

    void Show(bool rewarded, bool connected)
    {
        var state = JsonUtility.FromJson<AppState>("{\"revision\":1,\"view\":\"cabin\",\"ready\":true,\"connected\":" +
            (connected ? "true" : "false") + ",\"collectionRewardForTrip\":" + (rewarded ? "true" : "false") + "}");
        AppSession.Receive(state);
        Call("OnState", state);
        Call("UpdateChrome");
        Call("Render");
        Canvas.ForceUpdateCanvases();
    }

    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Call(string name, params object[] args) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, args);
}
