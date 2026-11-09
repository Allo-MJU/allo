using System.Linq;
using Allo.World;
using NUnit.Framework;

public class ChunkTrackTests
{
    static ChunkTrack T() => new ChunkTrack(chunkLength: 30, ahead: 300, behind: 60, commit: 25);

    [Test]
    public void FirstSceneFillsBehindToAhead()
    {
        var t = T();
        var (spawn, despawn) = t.SetScene("road");
        Assert.IsEmpty(despawn);
        Assert.AreEqual(-2, spawn.Min(c => c.index));
        Assert.AreEqual(10, spawn.Max(c => c.index));
        Assert.IsTrue(spawn.All(c => c.kind == "road"));
    }

    [Test]
    public void AdvanceAddsAheadAndDropsBehind()
    {
        var t = T();
        t.SetScene("road");
        var (spawn, despawn) = t.Advance(60);
        CollectionAssert.AreEquivalent(new[] { 11, 12 }, spawn.Select(c => c.index));
        CollectionAssert.AreEquivalent(new[] { -2, -1 }, despawn);
    }

    [Test]
    public void SceneChangeRebuildsOnlyBeyondCommit()
    {
        var t = T();
        t.SetScene("road");
        var (spawn, despawn) = t.SetScene("coast");
        // 25m 안쪽(0번 조각)은 그대로 두고 그 너머(1번부터)를 바다로 다시 만든다
        Assert.IsFalse(despawn.Contains(0));
        Assert.IsTrue(despawn.Contains(1));
        Assert.IsTrue(spawn.All(c => c.kind == "coast" && c.index >= 1));
        Assert.AreEqual("road", t.Live[0].kind);
    }

    [Test]
    public void TunnelGetsEntranceAndExit()
    {
        var t = T();
        t.SetScene("road");
        t.SetScene("tunnel");
        Assert.IsTrue(t.Live[1].entrance);
        Assert.IsFalse(t.Live[2].entrance);
        t.Advance(150);
        t.SetScene("city");
        var firstCity = t.Live.Values.Where(c => c.kind == "city").Min(c => c.index);
        Assert.IsTrue(t.Live[firstCity].exit);
    }

    [Test]
    public void SameSceneTwiceDoesNothing()
    {
        var t = T();
        t.SetScene("city");
        var (spawn, despawn) = t.SetScene("city");
        Assert.IsEmpty(spawn);
        Assert.IsEmpty(despawn);
    }

    [Test]
    public void BackwardsOrHugeStepsAreSafe()
    {
        var t = T();
        t.SetScene("road");
        var (s1, d1) = t.Advance(-10);
        Assert.IsEmpty(s1);
        Assert.IsEmpty(d1);
        var (s2, _) = t.Advance(100000);
        Assert.LessOrEqual(t.Live.Count, 13);
        Assert.AreEqual(13, t.Live.Count);
    }
}
