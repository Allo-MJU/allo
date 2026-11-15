using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppUiEggHudTests
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
        AppSession.Receive(new AppState
        {
            revision = 1, view = "cabin", ready = true, connected = true,
            speechAvailable = true, photoAvailable = true,
            egg = new EggState { id = "hud-egg", active = true, phase = "incubating", score = 42 }
        });
        _root = new GameObject("Egg HUD test");
        _ui = _root.AddComponent<AppUi>();
        if (typeof(AppUi).GetField("_safe", Private).GetValue(_ui) == null) Call("Awake");
        Call("OnState", AppSession.State);
    }

    [TearDown]
    public void TearDown()
    {
        Object.DestroyImmediate(_root);
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous);
    }

    [Test]
    public void AffinityIsOneFloatingGaugeWithoutAnEnclosingPanelOrSeparateCopy()
    {
        Call("BuildEggHud", AppSession.State.egg);
        var hud = Named("Cabin affinity HUD");
        Assert.IsNull(hud.GetComponent<Image>(), "the former cream panel must be removed");
        Assert.IsNull(hud.GetComponent<Outline>());
        Assert.LessOrEqual(hud.sizeDelta.y, 32, "the gauge must not reserve the former title/hint plate");
        Assert.AreEqual(2, hud.GetComponentsInChildren<Image>().Length, "only track and fill remain");
        var score = hud.GetComponentsInChildren<Text>().Single();
        Assert.AreEqual("42 / 100", score.text);
        Assert.AreEqual(Named("Affinity track"), score.transform.parent);
    }

    [TestCase(-10f, 0f)]
    [TestCase(42f, .42f)]
    [TestCase(120f, 1f)]
    public void GaugeKeepsConfirmedScoreAndClampsItsFill(float score, float fraction)
    {
        AppSession.State.egg.score = score;
        Call("BuildEggHud", AppSession.State.egg);
        Assert.AreEqual(fraction, Named("Confirmed affinity").anchorMax.x, .0001f);
    }

    [TestCase(false)]
    [TestCase(true)]
    public void CareAndPhotoControlsRemainReachableBelowTheGauge(bool photoRequired)
    {
        AppSession.State.egg.photoRequired = photoRequired;
        Call("BuildEggHud", AppSession.State.egg);
        var hud = Named("Cabin affinity HUD");
        var tools = Named("Egg care tools");
        Assert.Less(tools.offsetMax.y, hud.offsetMin.y);
        foreach (var label in new[] { "말 걸기", "글로 말하기", "자리와 돌보기" })
        {
            var button = ButtonNamed(label);
            Assert.IsNotNull(button, label);
            Assert.GreaterOrEqual(button.GetComponent<LayoutElement>().minHeight, 48, label);
        }
        Assert.AreEqual(!photoRequired, ButtonNamed("말 걸기").interactable);
        ButtonNamed("글로 말하기").onClick.Invoke();
        Assert.IsTrue((bool)typeof(AppUi).GetField("_speechDrawer", Private).GetValue(_ui));
        ButtonNamed("자리와 돌보기").onClick.Invoke();
        Assert.IsTrue((bool)typeof(AppUi).GetField("_zoneDrawer", Private).GetValue(_ui));
        if (!photoRequired) return;
        Assert.Less(Named("Photo quest tools").offsetMax.y, tools.offsetMin.y);
        foreach (var label in new[] { "함께 사진 찍기", "보류한 사진 확인" })
        {
            var button = ButtonNamed(label);
            Assert.IsTrue(button.interactable, label);
            Assert.GreaterOrEqual(button.GetComponent<LayoutElement>().minHeight, 48, label);
        }
    }

    RectTransform Named(string name) => _root.GetComponentsInChildren<RectTransform>().Single(t => t.name == name);
    Button ButtonNamed(string text) => _root.GetComponentsInChildren<Button>().SingleOrDefault(b => b.GetComponentInChildren<Text>()?.text == text);
    void Call(string name, params object[] values) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, values);
}
