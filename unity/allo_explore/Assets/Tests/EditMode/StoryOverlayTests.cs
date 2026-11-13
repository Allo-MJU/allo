using System;
using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class StoryOverlayTests
{
    GameObject _host;
    RectTransform _safe;
    StoryOverlay _overlay;
    AppState _state;
    [SetUp] public void Setup()
    {
        _host = new GameObject("Story test", typeof(RectTransform));
        _safe = (RectTransform)_host.transform;
        _safe.sizeDelta = new Vector2(1600,720);
        _overlay = _host.AddComponent<StoryOverlay>();
        _overlay.Initialize(_safe, Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf"), null);
        _state = new AppState { ready=true, view="cabin", story = new StoryState { active=true, canPlay=true, instanceId="one", nodeId="react_a", revision=3, title="배", line="돛이 볼록!", visual="coast_sail",variant="a",choices=new[]{new StoryChoice{id="next",label="다음"}} } };
    }
    [TearDown] public void Teardown() { Object.DestroyImmediate(_host); }
    [Test] public void VehicleSnapshotDoesNotRebuildStoryOrExperiment()
    {
        _overlay.Apply(_state,false);
        var boat = _host.GetComponentsInChildren<RectTransform>().Single(r=>r.name=="Mail boat");
        _state.revision++; _state.story.revision++;
        _state.egg = new EggState { score=34 };
        _overlay.Apply(_state,false);
        Assert.AreSame(boat,_host.GetComponentsInChildren<RectTransform>().Single(r=>r.name=="Mail boat"));
    }
    [Test] public void StoryRevisionReplacesExperimentButDoesNotAddOverlays()
    {
        _overlay.Apply(_state,false);
        _state.story.revision++; _state.story.variant="b";
        _overlay.Apply(_state,false);
        Assert.AreEqual(1,_host.GetComponentsInChildren<RectTransform>().Count(r=>r.name=="Mail boat"));
        Assert.AreEqual(1,_host.GetComponentsInChildren<RectTransform>().Count(r=>r.name=="Story presentation"));
    }
    [Test] public void PausingOrLeavingCabinReleasesInputCapture()
    {
        _overlay.Apply(_state,false); Assert.IsTrue(StoryOverlay.CapturingInput);
        _state.story.paused=true;_overlay.Apply(_state,false); Assert.IsFalse(StoryOverlay.CapturingInput);
        _state.story.paused=false;_state.view="camp";_overlay.Apply(_state,false); Assert.IsFalse(StoryOverlay.CapturingInput);
    }
    [Test] public void ImportantModalHidesStoryPresentation()
    {
        _overlay.Apply(_state,true);
        Assert.IsFalse(_host.GetComponentsInChildren<RectTransform>(true).Single(r=>r.name=="Story play").gameObject.activeSelf);
    }
    [Test] public void UrgentCareClosesNotebookAndRestoresLayout()
    {
        _state.story.active=false;_overlay.Apply(_state,false);
        var book=(Button)typeof(StoryOverlay).GetField("_book",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(_overlay);
        int layoutChanges=0;_overlay.LayoutChanged+=()=>layoutChanges++;
        book.onClick.Invoke();Assert.IsTrue(_overlay.ShowingNotebook);
        _state.story.canPlay=false;_overlay.Apply(_state,false);
        Assert.IsFalse(_overlay.ShowingNotebook);Assert.IsFalse(StoryOverlay.CapturingInput);
        Assert.AreEqual(2,layoutChanges);
    }
    [Test] public void PausedNotebookOffersResumeAndCloseBeforeNewStory()
    {
        _state.story.paused=true;
        _state.story.library=new[]{new StoryCard{topicId="coast_sail",title="우편배"}};
        _overlay.Apply(_state,false);
        var book=(Button)typeof(StoryOverlay).GetField("_book",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(_overlay);
        book.onClick.Invoke();
        var buttons=_host.GetComponentsInChildren<Button>();
        Assert.IsTrue(buttons.Single(b=>b.name=="이어 하기").interactable);
        Assert.IsTrue(buttons.Single(b=>b.name=="이야기 마치기").interactable);
        Assert.IsFalse(buttons.Single(b=>b.name=="상상 탐험 · 우편배").interactable);
    }
    [TestCase(64,128)] [TestCase(160,128)] [TestCase(384,128)]
    public void PortraitTextureFitsBoundedViewportAndCannotCoverDialogue(int width,int height)
    {
        var canvas=_host.AddComponent<Canvas>();canvas.renderMode=RenderMode.WorldSpace;
        _overlay.Apply(_state,false);
        var guide=_host.GetComponentsInChildren<RawImage>().Single();
        var texture=new Texture2D(width,height);
        try
        {
            guide.texture=texture;
            guide.GetComponent<AspectRatioFitter>().aspectRatio=width/(float)height;
            Canvas.ForceUpdateCanvases();LayoutRebuilder.ForceRebuildLayoutImmediate(_safe);Canvas.ForceUpdateCanvases();
            var viewport=(RectTransform)guide.transform.parent;
            Assert.AreEqual("Story guide viewport",viewport.name);
            Assert.NotNull(viewport.GetComponent<RectMask2D>());
            Assert.Greater(guide.rectTransform.rect.width,0);Assert.Greater(guide.rectTransform.rect.height,0);
            Assert.LessOrEqual(guide.rectTransform.rect.width,viewport.rect.width+.1f);
            Assert.LessOrEqual(guide.rectTransform.rect.height,viewport.rect.height+.1f);
            var corners=new Vector3[4];guide.rectTransform.GetWorldCorners(corners);
            foreach(var corner in corners)
            {
                var local=viewport.InverseTransformPoint(corner);
                Assert.That(local.x,Is.InRange(viewport.rect.xMin-.1f,viewport.rect.xMax+.1f));
                Assert.That(local.y,Is.InRange(viewport.rect.yMin-.1f,viewport.rect.yMax+.1f));
            }
            var dock=_host.GetComponentsInChildren<RectTransform>().Single(r=>r.name=="Story dialogue dock");
            var viewportCorners=new Vector3[4];viewport.GetWorldCorners(viewportCorners);
            var dockCorners=new Vector3[4];dock.GetWorldCorners(dockCorners);
            Assert.GreaterOrEqual(viewportCorners[0].y,dockCorners[1].y);
        }
        finally { Object.DestroyImmediate(texture); }
    }
    [TestCase("road_seed")][TestCase("coast_sail")][TestCase("mountain_soil")][TestCase("city_bridge")]
    [TestCase("tunnel_shadow")][TestCase("rain_path")][TestCase("night_stars")][TestCase("highway_view")]
    public void EachPackDrawsBothExperimentVariants(string topic)
    {
        _state.story.visual=topic;_state.story.variant="both";
        _overlay.Apply(_state,false);
        Assert.AreEqual(2,_host.GetComponentsInChildren<RectTransform>().Count(r=>r.name=="Comparison"));
        foreach (var comparison in _host.GetComponentsInChildren<RectTransform>().Where(r=>r.name=="Comparison"))
            Assert.Greater(comparison.GetComponentsInChildren<StoryShape>().Length,0,"Each compared variant must have experiment artwork.");
    }
}
