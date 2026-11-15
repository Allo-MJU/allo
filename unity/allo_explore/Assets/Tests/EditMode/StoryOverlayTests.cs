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
        _state = new AppState { ready=true, connected=true, view="cabin", story = new StoryState { ready=true, canOpen=true, notebookOpen=true, topicId="coast_sail", active=true, canPlay=true, instanceId="one", nodeId="react_a", revision=3, title="배", line="돛이 볼록!", visual="coast_sail",variant="a",choices=new[]{new StoryChoice{id="next",label="다음"}} } };
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
        _state.story.paused=true;_state.story.notebookOpen=false;_overlay.Apply(_state,false); Assert.IsFalse(StoryOverlay.CapturingInput);
        _state.story.paused=false;_state.view="camp";_overlay.Apply(_state,false); Assert.IsFalse(StoryOverlay.CapturingInput);
    }
    [Test] public void ImportantModalHidesStoryPresentation()
    {
        _overlay.Apply(_state,true);
        Assert.IsFalse(_host.GetComponentsInChildren<RectTransform>(true).Single(r=>r.name=="Story play").gameObject.activeSelf);
    }
    [Test] public void NotebookToggleWaitsForAuthoritativeHostState()
    {
        _state.story.active=false; _state.story.notebookOpen=false; _overlay.Apply(_state,false);
        _overlay.ToggleNotebook(); Assert.IsFalse(_overlay.ShowingNotebook);
        _state.story.notebookOpen=true; _overlay.Apply(_state,false); Assert.IsTrue(_overlay.ShowingNotebook);
        _overlay.ToggleNotebook(); Assert.IsTrue(_overlay.ShowingNotebook);
        _state.story.notebookOpen=false; _overlay.Apply(_state,false); Assert.IsFalse(_overlay.ShowingNotebook);
    }
    [Test] public void PhotoPriorityAndUnpairedCabinNeverCaptureInput()
    {
        _overlay.Apply(_state,false); Assert.IsTrue(StoryOverlay.CapturingInput);
        _state.connected=false; _overlay.Apply(_state,false); Assert.IsFalse(StoryOverlay.CapturingInput);
        _state.connected=true; _state.egg=new EggState{photoRequired=true};
        _overlay.Apply(_state,false); Assert.IsFalse(StoryOverlay.CapturingInput);
    }
    [Test] public void StaleStoryWithoutPilotReadinessDoesNotCapture()
    {
        _state.story.ready=false; _state.story.notebookOpen=false; _overlay.Apply(_state,false);
        Assert.IsFalse(StoryOverlay.CapturingInput); Assert.IsFalse(StoryOverlay.ShowsStory(_state));
    }
    [Test] public void StartedPilotKeepsPresentationAfterHostClosesNotebook()
    {
        _state.story.notebookOpen=false; _overlay.Apply(_state,false);
        Assert.IsTrue(StoryOverlay.ShowsStory(_state)); Assert.IsTrue(StoryOverlay.CapturingInput);
        Assert.IsFalse(_overlay.ShowingNotebook);
    }
    [Test] public void PausedNotebookOffersResumeAndCloseBeforeNewStory()
    {
        _state.story.paused=true;
        _state.story.library=new[]{new StoryCard{topicId="coast_sail",title="우편배"}};
        _overlay.Apply(_state,false);
        var buttons=_host.GetComponentsInChildren<Button>();
        Assert.IsTrue(buttons.Single(b=>b.name=="이어 하기").interactable);
        Assert.IsTrue(buttons.Single(b=>b.name=="탐험 마치기").interactable);
        Assert.IsFalse(buttons.Single(b=>b.name=="상상 탐험 · 우편배").interactable);
    }
    [Test] public void LegacyCardIsReadableButOnlySeaCanReplay()
    {
        _state.story.active=false;
        _state.story.savedCards=new[]{new StoryCard{topicId="road_seed",title="씨앗",text="날개 원리"}};
        _overlay.Apply(_state,false);
        _host.GetComponentsInChildren<Button>().Single(b=>b.name=="발견 · 씨앗").onClick.Invoke();
        Assert.IsTrue(_host.GetComponentsInChildren<Text>().Any(t=>t.text=="날개 원리"));
        Assert.IsFalse(_host.GetComponentsInChildren<Button>().Single(b=>b.name=="다시 실험하기").interactable);
    }
    [Test] public void NotebookReplayStartsFreshPredictionWithoutAnActiveSession()
    {
        _state.story.active=false; _state.story.instanceId=null; _state.story.nodeId=null;
        var card=new StoryCard{topicId="coast_sail",title="배"};
        var intent=StoryOverlay.CardReplayIntent(_state,card);
        Assert.NotNull(intent); Assert.AreEqual("storyStart",intent.action); Assert.AreEqual("coast_sail",intent.topicId);
        _state.story.paused=true; Assert.IsNull(StoryOverlay.CardReplayIntent(_state,card));
        _state.story.paused=false; card.topicId="road_seed"; Assert.IsNull(StoryOverlay.CardReplayIntent(_state,card));
    }
    [TestCase(1600)] [TestCase(1280)] public void PersonalCardUsesBoundedScrollableRowsAndRefreshesWithSameCardCount(int width)
    {
        _safe.sizeDelta=new Vector2(width,720);
        _host.AddComponent<Canvas>().renderMode=RenderMode.WorldSpace;
        _state.story.active=false; _state.story.cardCount=1;
        var card=new StoryCard{topicId="coast_sail",title="배",text="바람 원리",prediction="접은 배",firstAction="펼치기",observation="펼친 배가 더 멀리",principle="바람이 돛을 밀어",nextQuestion="다른 물건은?"};
        _state.story.savedCards=new[]{card}; _overlay.Apply(_state,false);
        _host.GetComponentsInChildren<Button>().Single(b=>b.name=="발견 · 배").onClick.Invoke();
        var scroll=_host.GetComponentsInChildren<ScrollRect>().Single();
        Assert.NotNull(scroll.viewport.GetComponent<RectMask2D>());
        Canvas.ForceUpdateCanvases(); LayoutRebuilder.ForceRebuildLayoutImmediate(_safe); Canvas.ForceUpdateCanvases();
        Assert.Greater(scroll.viewport.rect.width,0); Assert.Greater(scroll.viewport.rect.height,0);
        foreach(var row in scroll.content.GetComponentsInChildren<Text>())
            Assert.GreaterOrEqual(row.rectTransform.rect.height,row.preferredHeight-.1f,"Evidence rows must fit their wrapped Korean copy.");
        foreach(var value in new[]{"내 예상: 접은 배","먼저 해본 것: 펼치기","비교한 결과: 펼친 배가 더 멀리","알아본 원리: 바람이 돛을 밀어","다음에 생각해 볼 것: 다른 물건은?"})
            Assert.IsTrue(scroll.content.GetComponentsInChildren<Text>().Any(t=>t.text==value),value);
        card.prediction="펼친 배"; _state.story.revision++; _overlay.Apply(_state,false);
        Assert.IsTrue(_host.GetComponentsInChildren<Text>().Any(t=>t.text=="내 예상: 펼친 배"));
        Assert.IsFalse(_host.GetComponentsInChildren<Text>().Any(t=>t.text=="내 예상: 접은 배"));
    }
    [Test] public void InitializationFailureShowsRetryAndLeavesReturnAvailable()
    {
        _state.story.active=false; _state.story.ready=false; _state.story.error="load_failed";
        _overlay.Apply(_state,false);
        Assert.IsTrue(_host.GetComponentsInChildren<Button>().Single(b=>b.name=="다시 불러오기").interactable);
        Assert.IsTrue(_host.GetComponentsInChildren<Button>().Single(b=>b.name=="돌봄으로").interactable);
    }
    [TestCase(64,128)] [TestCase(160,128)] [TestCase(384,128)]
    public void PortraitTextureFitsBoundedViewportAndCannotCoverDialogue(int width,int height)
    {
        var canvas=_host.AddComponent<Canvas>();canvas.renderMode=RenderMode.WorldSpace;
        _overlay.Apply(_state,false);
        var guide=_host.GetComponentsInChildren<RawImage>().Single(image=>image.name=="Story guide artwork");
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
        {
            if (topic == "coast_sail")
                Assert.NotNull(comparison.GetComponentsInChildren<RawImage>().Single(image=>image.name=="Boat illustration").texture);
            else Assert.Greater(comparison.GetComponentsInChildren<StoryShape>().Length,0,"Each compared variant must have experiment artwork.");
        }
    }
    [Test] public void SeaIllustrationsAreRequiredBundledTextures()
    {
        var boats=Resources.Load<Texture2D>("StoryArt/Sea/boat-states");
        var ocean=Resources.Load<Texture2D>("StoryArt/Sea/ocean-stage");
        Assert.NotNull(boats,"The sea experiment must bundle its illustrated boat atlas.");
        Assert.NotNull(ocean,"The sea experiment must bundle its illustrated ocean backdrop.");
        Assert.AreEqual(0,boats.width%2,"Boat atlas cells must have identical dimensions.");
        Assert.Greater(boats.height,0); Assert.Greater(ocean.width,ocean.height);
    }
    [TestCase("a",0f)] [TestCase("b",.5f)]
    public void SeaUsesAtlasHalfWithoutPrimitiveHullMastSailOrWater(string variant,float left)
    {
        _state.story.variant=variant; _overlay.Apply(_state,false);
        var boat=_host.GetComponentsInChildren<RawImage>().Single(image=>image.name=="Boat illustration");
        var atlas=Resources.Load<Texture2D>("StoryArt/Sea/boat-states");
        Assert.AreSame(atlas,boat.texture); Assert.AreEqual(new Rect(left,0,.5f,1),boat.uvRect);
        Assert.AreEqual(atlas.width*.5f/atlas.height,boat.rectTransform.rect.width/boat.rectTransform.rect.height,.001f);
        Assert.GreaterOrEqual(boat.rectTransform.rect.height,200,"The illustrated boat must remain legible in the comparison panels.");
        Assert.IsFalse(boat.raycastTarget);
        var ocean=_host.GetComponentsInChildren<RawImage>().Single(image=>image.name=="Ocean illustration");
        Assert.AreSame(Resources.Load<Texture2D>("StoryArt/Sea/ocean-stage"),ocean.texture);
        Assert.AreEqual(0,_host.GetComponentsInChildren<StoryShape>().Length,"Sea art must use the real illustrations rather than shape stand-ins.");
    }
    [Test] public void SeaComparisonKeepsSameAtlasSizeStartAndLongerOpenSailTravel()
    {
        _state.story.variant="both"; _overlay.Apply(_state,false);
        var boats=_host.GetComponentsInChildren<RawImage>().Where(image=>image.name=="Boat illustration").OrderBy(image=>image.uvRect.x).ToArray();
        Assert.AreEqual(2,boats.Length); Assert.AreSame(boats[0].texture,boats[1].texture);
        Assert.AreEqual(boats[0].rectTransform.rect.size,boats[1].rectTransform.rect.size);
        var open=(RectTransform)boats[0].transform.parent; var furled=(RectTransform)boats[1].transform.parent;
        Assert.AreEqual("Mail boat",open.name); Assert.AreEqual("Mail boat",furled.name);
        var motions=(System.Collections.Generic.List<Action<float>>)typeof(StoryOverlay).GetField("_motions",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(_overlay);
        foreach(var motion in motions) motion(0);
        Assert.AreEqual(new Vector2(-210,-15),open.anchoredPosition); Assert.AreEqual(open.anchoredPosition,furled.anchoredPosition);
        foreach(var motion in motions) motion(1);
        Assert.AreEqual(new Vector2(200,-15),open.anchoredPosition); Assert.AreEqual(new Vector2(-100,-15),furled.anchoredPosition);
        foreach(var boat in boats)
        {
            var r=boat.rectTransform.rect; var position=((RectTransform)boat.transform.parent).anchoredPosition;
            Assert.LessOrEqual(position.x+r.xMax,340); Assert.GreaterOrEqual(position.x+r.xMin,-340);
        }
    }
    [Test] public void SeaNeutralStaysAtStartAndReducedMotionShowsFinalStaticResult()
    {
        _state.story.variant="neutral"; _overlay.Apply(_state,false);
        typeof(StoryOverlay).GetMethod("Update",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(_overlay,null);
        Assert.AreEqual(new Vector2(-210,-15),_host.GetComponentsInChildren<RectTransform>().Single(r=>r.name=="Mail boat").anchoredPosition);
        _state.story.variant="a"; _state.reducedMotion=true; _overlay.Apply(_state,false);
        typeof(StoryOverlay).GetMethod("Update",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(_overlay,null);
        Assert.AreEqual(new Vector2(200,-15),_host.GetComponentsInChildren<RectTransform>().Single(r=>r.name=="Mail boat").anchoredPosition);
    }

}
