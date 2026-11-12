using Allo.Bridge;
using Allo.Critters;
using NUnit.Framework;

public class EggTrackerTests
{
    static EggState E(string state, string id = "e1", float p = 0.3f) => new EggState { state = state, eggId = id, progress = p };

    [Test]
    public void IncubatingThenHatchedSameEggHatchesOnce()
    {
        var t = new EggTracker();
        Assert.AreEqual(EggTracker.Change.Appear, t.Apply(E("incubating")));
        Assert.AreEqual(EggTracker.Change.Update, t.Apply(E("incubating", p: 0.9f)));
        Assert.AreEqual(EggTracker.Change.Hatch, t.Apply(E("hatched")));
        Assert.IsFalse(t.Present);
        Assert.AreEqual(EggTracker.Change.None, t.Apply(E("hatched")), "같은 hatched 가 다시 와도 한 번만");
    }

    [Test]
    public void EnteringAfterHatchShowsNoEgg()
    {
        var t = new EggTracker();
        Assert.AreEqual(EggTracker.Change.None, t.Apply(E("hatched")));
        Assert.AreEqual(EggTracker.Change.None, t.Apply(E("idle")));
        Assert.IsFalse(t.Present);
    }

    [Test]
    public void DifferentEggHatchedVanishesWithoutShow()
    {
        var t = new EggTracker();
        t.Apply(E("incubating", "e1"));
        Assert.AreEqual(EggTracker.Change.Vanish, t.Apply(E("hatched", "e2")));
    }

    [Test]
    public void NextEggAfterHatchAppearsAgainAndNewIdReplaces()
    {
        var t = new EggTracker();
        t.Apply(E("incubating", "e1"));
        t.Apply(E("hatched", "e1"));
        Assert.AreEqual(EggTracker.Change.Appear, t.Apply(E("incubating", "e2")));
        Assert.AreEqual(EggTracker.Change.Replace, t.Apply(E("incubating", "e3")));
        Assert.AreEqual("e3", t.EggId);
    }

    [Test]
    public void IdleRemovesEgg()
    {
        var t = new EggTracker();
        t.Apply(E("incubating"));
        Assert.AreEqual(EggTracker.Change.Vanish, t.Apply(E("idle")));
    }

    [Test]
    public void CrackStagesFollowProgress()
    {
        Assert.AreEqual(0, EggTracker.CrackStage(0.49f));
        Assert.AreEqual(1, EggTracker.CrackStage(0.5f));
        Assert.AreEqual(2, EggTracker.CrackStage(0.85f));
        Assert.AreEqual(3, EggTracker.CrackStage(0.97f));
    }
}
