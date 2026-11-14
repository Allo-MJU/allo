using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.UI;

public class AppUiScrollTests
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
        AppSession.Receive(State(1, "dex"));
        _root = new GameObject("Scroll test application");
        _ui = _root.AddComponent<AppUi>();
        if (Get<RectTransform>("_safe") == null) Call("Awake");
        Call("OnState", AppSession.State);
        var content = Get<RectTransform>("_content");
        content.anchorMin = content.anchorMax = new Vector2(.5f, .5f);
        content.sizeDelta = new Vector2(1200, 180);
        Render();
    }

    [TearDown]
    public void TearDown()
    {
        Object.DestroyImmediate(_root);
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous);
    }

    [Test]
    public void SnapshotKeepsBothActualPanelViewportOffsets()
    {
        var panels = Panels();
        SetOffsets(panels, .22f, .63f);
        var leftOffset = panels[0].content.anchoredPosition.y;
        var rightOffset = panels[1].content.anchoredPosition.y;
        AppSession.Receive(State(2, "dex"));
        Call("OnState", AppSession.State);
        Render();
        AssertOffsets(.22f, .63f, leftOffset, rightOffset);
    }

    [Test]
    public void LocalSelectionRerenderKeepsBothActualPanelViewportOffsets()
    {
        AppSession.Receive(State(2, "dex"));
        Call("OnState", AppSession.State);
        Render();
        var panels = Panels();
        SetOffsets(panels, .31f, .72f);
        var leftOffset = panels[0].content.anchoredPosition.y;
        var rightOffset = panels[1].content.anchoredPosition.y;
        var tile = panels[1].GetComponentsInChildren<Button>()
            .Last(button => button.transform.parent.name == "Dex grid");
        tile.onClick.Invoke();
        Assert.AreEqual("dex-23", Get<string>("_selectedDex"));
        Render();
        AssertOffsets(.31f, .72f, leftOffset, rightOffset);
    }

    [Test]
    public void ReturningToAViewRestoresItsOwnIndependentPanelOffsets()
    {
        SetOffsets(Panels(), .18f, .57f);
        AppSession.Receive(State(2, "settings"));
        Call("OnState", AppSession.State);
        Render();
        SetOffsets(Panels(), .44f, .81f);
        AppSession.Receive(State(3, "dex"));
        Call("OnState", AppSession.State);
        Render();
        var panels = Panels();
        Assert.That(panels[0].verticalNormalizedPosition, Is.EqualTo(.18f).Within(.002f));
        Assert.That(panels[1].verticalNormalizedPosition, Is.EqualTo(.57f).Within(.002f));
    }

    static AppState State(int revision, string view) => new AppState
    {
        revision = revision, view = view, ready = true, connected = true,
        speechAvailable = true, photoAvailable = true,
        egg = new EggState { id = "scroll-egg", active = true, phase = "incubating" },
        dex = Enumerable.Range(0, 24).Select(i => new DexState { id = "dex-" + i, name = "Friend " + i }).ToArray()
    };

    void AssertOffsets(float left, float right, float leftOffset, float rightOffset)
    {
        var panels = Panels();
        Assert.That(panels[0].verticalNormalizedPosition, Is.EqualTo(left).Within(.002f), "left normalized position");
        Assert.That(panels[1].verticalNormalizedPosition, Is.EqualTo(right).Within(.002f), "right normalized position");
        Assert.That(panels[0].content.anchoredPosition.y, Is.EqualTo(leftOffset).Within(1f), "left actual viewport offset");
        Assert.That(panels[1].content.anchoredPosition.y, Is.EqualTo(rightOffset).Within(1f), "right actual viewport offset");
    }

    static void SetOffsets(ScrollRect[] panels, float left, float right)
    {
        Assert.AreEqual(2, panels.Length);
        foreach (var panel in panels)
            Assert.Greater(panel.content.rect.height, panel.viewport.rect.height, "test panel must actually overflow");
        panels[0].verticalNormalizedPosition = left;
        panels[1].verticalNormalizedPosition = right;
        Canvas.ForceUpdateCanvases();
        Assert.Greater(panels[0].content.anchoredPosition.y, 0);
        Assert.Greater(panels[1].content.anchoredPosition.y, 0);
    }

    ScrollRect[] Panels() => Get<RectTransform>("_content").GetComponentsInChildren<ScrollRect>()
        .Where(p => p.gameObject.activeSelf).OrderBy(p => ((RectTransform)p.transform).anchorMin.x).ToArray();

    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Call(string name, params object[] args) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, args);
    void Render()
    {
        // Runtime Render defers destruction; EditMode needs immediate cleanup afterward.
        var content = Get<RectTransform>("_content");
        var panels = content.GetComponentsInChildren<ScrollRect>();
        // Expect only the known EditMode deferred-Destroy error; all other logs still fail.
        foreach (Transform child in content)
            LogAssert.Expect(LogType.Error, new Regex("^Destroy may not be called from edit mode! Use DestroyImmediate instead\\."));
        Call("Render");
        foreach (var panel in panels)
            if (panel != null && !panel.gameObject.activeSelf) Object.DestroyImmediate(panel.gameObject);
    }
}
