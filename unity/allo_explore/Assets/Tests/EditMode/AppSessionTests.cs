using Allo.App;
using NUnit.Framework;
using UnityEngine;

public class AppSessionTests
{
    [TestCase("storyNotebook")]
    [TestCase("storyStart")]
    [TestCase("storyChoose")]
    [TestCase("storyPause")]
    [TestCase("storyResume")]
    [TestCase("storyClose")]
    [TestCase("storyRetry")]
    [TestCase("storyUiBlocked")]
    public void StoryIntentsCarryCurrentPresentationTokenIndependentlyOfNodeRevision(string action)
    {
        var previous = AppSession.State;
        var stateProperty = typeof(AppSession).GetProperty(nameof(AppSession.State));
        try
        {
            stateProperty.SetValue(null, null);
            var snapshot = JsonUtility.FromJson<AppState>(
                "{\"revision\":1,\"view\":\"cabin\",\"story\":{\"instanceId\":\"trip-one\",\"nodeId\":\"intro\",\"topicId\":\"coast_sail\",\"revision\":3,\"presentationRevision\":17}}");
            AppSession.Receive(snapshot);
            var request = AppSession.CreateAction(action);
            var payload = JsonUtility.FromJson<PresentationToken>(JsonUtility.ToJson(request));
            Assert.AreEqual(17, payload.storyPresentationRevision);
            Assert.AreEqual(3, request.storyRevision);

            var next = JsonUtility.FromJson<AppState>(
                "{\"revision\":2,\"view\":\"cabin\",\"story\":{\"instanceId\":\"trip-one\",\"nodeId\":\"intro\",\"topicId\":\"coast_sail\",\"revision\":3,\"presentationRevision\":18}}");
            AppSession.Receive(next);
            request = AppSession.CreateAction(action, request);
            payload = JsonUtility.FromJson<PresentationToken>(JsonUtility.ToJson(request));
            Assert.AreEqual(18, payload.storyPresentationRevision, "a reused body must use the current host presentation token");
            Assert.AreEqual(3, request.storyRevision, "presentation changes do not require a node change");
        }
        finally { stateProperty.SetValue(null, previous); }
    }

    [System.Serializable]
    sealed class PresentationToken { public int storyPresentationRevision; }

    [TestCase("cabin")]
    [TestCase("settings")]
    [TestCase("camp")]
    [TestCase("dex")]
    [TestCase("inventory")]
    public void AppBackReturnsToHomeWithoutClosingTheUnityHost(string view)
    {
        Assert.AreEqual(AppBackAction.NavigateHome, AppSession.BackActionFor(new AppState { view = view }));
    }

    [Test]
    public void AppHomeBackBackgroundsTheTaskRatherThanExposingFlutter()
    {
        Assert.AreEqual(AppBackAction.BackgroundApp, AppSession.BackActionFor(new AppState { view = "home" }));
    }

    [Test]
    public void LegacyExploreBackStillClosesWhenNoAppSnapshotExists()
    {
        Assert.AreEqual(AppBackAction.CloseExplore, AppSession.BackActionFor(null));
    }

    [Test]
    public void OlderOrDuplicateSnapshotsCannotRewindTheApp()
    {
        var current = new AppState { revision = 8, view = "camp" };
        Assert.IsTrue(AppSession.Accepts(current, new AppState { revision = 9, view = "cabin" }));
        Assert.IsFalse(AppSession.Accepts(current, new AppState { revision = 7 }));
        Assert.IsFalse(AppSession.Accepts(current, new AppState { revision = 8 }));
    }

    [Test]
    public void UnknownEnvelopeOrViewNeverActivatesTheApp()
    {
        Assert.IsFalse(AppSession.Accepts(null, new AppState { v = 2 }));
        Assert.IsFalse(AppSession.Accepts(null, new AppState { type = "unexpected" }));
        Assert.IsFalse(AppSession.Accepts(null, new AppState { view = "unknown" }));
        Assert.IsFalse(AppSession.Accepts(null, null));
    }
}
