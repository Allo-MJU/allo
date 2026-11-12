using Allo.App;
using NUnit.Framework;

public class AppSessionTests
{
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
