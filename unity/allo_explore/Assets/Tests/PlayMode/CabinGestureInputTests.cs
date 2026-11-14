using System.Collections;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class CabinGestureInputTests
{
    GameObject _events, _canvas;

    [UnityTearDown]
    public IEnumerator TearDown()
    {
        if (_canvas != null) Object.Destroy(_canvas);
        if (_events != null) Object.Destroy(_events);
        yield return null;
    }

    [UnityTest]
    public IEnumerator UiHitTestingUsesTheCurrentScreenPositionWithoutACachedPointer()
    {
        if (EventSystem.current == null)
            _events = new GameObject("Fresh raycast events", typeof(EventSystem), typeof(StandaloneInputModule));
        _canvas = new GameObject("Fresh raycast canvas", typeof(Canvas), typeof(GraphicRaycaster));
        _canvas.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
        var button = new GameObject("Fresh raycast button", typeof(RectTransform), typeof(Image));
        button.transform.SetParent(_canvas.transform, false);
        var rect = button.GetComponent<RectTransform>();
        rect.anchorMin = rect.anchorMax = new Vector2(.5f, .5f);
        rect.sizeDelta = new Vector2(100, 100);
        yield return null; yield return null;
        Canvas.ForceUpdateCanvases();
        var inside = RectTransformUtility.WorldToScreenPoint(null, rect.TransformPoint(rect.rect.center));
        Assert.IsTrue(CabinInteraction.IsOverUi(inside), "actual rendered UI must win even without a cached pointer event");
        Assert.IsFalse(CabinInteraction.IsOverUi(new Vector2(-100, -100)));
    }
}
