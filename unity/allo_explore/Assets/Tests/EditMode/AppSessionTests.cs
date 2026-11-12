using Allo.App;
using NUnit.Framework;

public class AppSessionTests
{
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
