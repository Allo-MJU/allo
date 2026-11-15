using System.Linq;
using Allo.World;
using NUnit.Framework;
using UnityEngine;

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

    static Allo.World.ChunkInfo Junction(ChunkTrack t) => t.Live.Values.FirstOrDefault(c => c.turn != null);

    [Test]
    public void TurnBecomesJunctionAtThatDistance()
    {
        var t = T();
        t.SetScene("road");
        t.SetTurns(new[] { ("right", 200f) });
        var j = Junction(t);
        Assert.IsNotNull(j);
        Assert.AreEqual("right", j.turn);
        Assert.That(j.start, Is.InRange(170f, 200f));
        // 회전 뒤 조각은 오른쪽(+x)으로 90도 돈 방향이다
        var after = t.Live[j.index + 1];
        Assert.AreEqual(90f, after.path.yaw, 0.01f);
        Assert.IsTrue(after.trimRight);
        Assert.IsTrue(t.Live[j.index + 2].trimRight);
        Assert.IsFalse(t.Live[j.index + 3].trimRight);
    }

    [Test]
    public void PathIsContinuousThroughTurns()
    {
        var t = T();
        t.SetScene("road");
        t.SetTurns(new[] { ("left", 120f), ("uturn", 260f) });
        var chunks = t.Live.Values.OrderBy(c => c.index).ToList();
        for (var i = 1; i < chunks.Count; i++)
        {
            var end = ChunkTrack.PoseIn(chunks[i - 1], chunks[i - 1].length);
            Assert.Less(Vector3.Distance(end.pos, chunks[i].path.pos), 0.01f, $"조각 {chunks[i].index}");
            Assert.AreEqual(0f, Mathf.DeltaAngle(end.yaw, chunks[i].path.yaw), 0.01f);
        }
    }

    [Test]
    public void SameTurnWithJitterDoesNotRebuild()
    {
        var t = T();
        t.SetScene("road");
        t.SetTurns(new[] { ("right", 200f) });
        t.Advance(10);
        var (spawn, despawn) = t.SetTurns(new[] { ("right", 203f) });
        Assert.IsEmpty(spawn);
        Assert.IsEmpty(despawn);
    }

    [Test]
    public void ClearingTurnsStraightensRoadBeyondCommit()
    {
        var t = T();
        t.SetScene("road");
        t.SetTurns(new[] { ("left", 200f) });
        t.SetTurns(new (string, float)[0]);
        Assert.IsNull(Junction(t));
        Assert.IsTrue(t.Live.Values.All(c => Mathf.Approximately(c.path.yaw, 0)));
    }

    [Test]
    public void UturnRetracesPassedChunks()
    {
        var t = T();
        t.SetScene("road");
        t.SetTurns(new[] { ("uturn", 150f) });
        var j = Junction(t);
        var back = t.Live[j.index + 1];
        Assert.AreEqual(j.index - 1, back.reuseOf);
        Assert.AreEqual(t.Live[j.index - 1].seed, back.seed);
        Assert.AreEqual(180f, Mathf.Abs(Mathf.DeltaAngle(0, back.path.yaw)), 0.01f);
        Assert.AreEqual(j.index - 2, t.Live[j.index + 2].reuseOf);
    }

    [Test]
    public void NoTurnsInTunnelOrHighway()
    {
        var t = T();
        t.SetScene("tunnel");
        t.SetTurns(new[] { ("right", 200f) });
        Assert.IsNull(Junction(t));
    }

    [Test]
    public void CarSlowsGraduallyBeforeJunction()
    {
        var t = T();
        t.SetScene("road");
        t.SetTurns(new[] { ("right", 150f) });
        var j = Junction(t);
        Assert.AreEqual(ChunkTrack.TurnKph, t.SpeedCapAt(j.start + 1), 0.01f);
        // 앞으로 갈수록 상한이 줄어든다 (뚝 떨어지지 않는다)
        var far = t.SpeedCapAt(j.start - 80);
        var mid = t.SpeedCapAt(j.start - 30);
        Assert.Greater(far, mid);
        Assert.Greater(mid, ChunkTrack.TurnKph);
        Assert.IsTrue(float.IsPositiveInfinity(t.SpeedCapAt(j.End + 1)));
    }

    [Test]
    public void TurnShapesEndWhereGeometrySaysAndStartStraight()
    {
        foreach (var turn in new[] { "right", "left", "uturn" })
        {
            var len = TurnShape.Length(turn);
            var end = TurnShape.Pose(turn, len);
            Assert.AreEqual(turn == "right" ? 90f : turn == "left" ? -90f : -180f, end.yaw, 0.01f, turn);
            // 처음에는 곧게 들어가고, 방향은 서서히 바뀐다 (1m 동안 3도 넘게 꺾이지 않는다)
            for (var s = 0f; s < len - 1; s += 1f)
                Assert.Less(Mathf.Abs(TurnShape.Pose(turn, s + 1).yaw - TurnShape.Pose(turn, s).yaw), turn == "uturn" ? 60f : 6f, $"{turn} {s}");
        }
        Assert.AreEqual(ChunkTrack.UturnShift, TurnShape.Pose("uturn", TurnShape.Length("uturn")).pos.x, 0.05f);
        Assert.AreEqual(0f, TurnShape.Pose("uturn", TurnShape.Length("uturn")).pos.z, 0.05f);
    }

    [Test]
    public void KeepRightIsGentleSCurve()
    {
        var t = T();
        t.SetScene("highway");
        t.SetTurns(new[] { ("keepRight", 150f) });
        var k = t.Live.Values.First(c => c.keep == "keepRight");
        Assert.AreEqual(ChunkTrack.KeepBend, k.bend, 0.01f);
        var tail = t.Live[k.index + 1];
        Assert.IsTrue(tail.keepTail);
        Assert.AreEqual(-ChunkTrack.KeepBend, tail.bend, 0.01f);
        // S자를 지나면 방향은 그대로, 오른쪽으로 비켜 있다
        var after = t.Live[k.index + 2].path;
        Assert.AreEqual(0f, Mathf.DeltaAngle(0, after.yaw), 0.01f);
        Assert.Greater(after.pos.x, 3f);
    }

    [Test]
    public void SteerBendsFirstChunkBeyondCommitAndMovesTheRest()
    {
        var t = T();
        t.SetScene("road");
        var res = t.SteerTo(10f);
        Assert.IsTrue(res.HasValue);
        var (bent, moved) = res.Value;
        Assert.That(bent.start, Is.GreaterThanOrEqualTo(25f));
        Assert.AreEqual(10f * ChunkTrack.SteerGain, bent.bend, 0.01f);
        Assert.IsNotEmpty(moved);
        Assert.AreEqual(10f * ChunkTrack.SteerGain, moved[0].path.yaw, 0.01f);
        // 차이가 3도 안쪽이면 다시 휘지 않는다
        Assert.IsFalse(t.SteerTo(10f * ChunkTrack.SteerGain + 2f).HasValue);
        PathContinuous(t);
    }

    [Test]
    public void BendIsClamped()
    {
        var t = T();
        t.SetScene("road");
        var res = t.SteerTo(80f);
        Assert.AreEqual(ChunkTrack.MaxBend, res.Value.bent.bend, 0.01f);
    }

    [Test]
    public void SensorCanReverseOrCenterTheSameUpcomingBendWithoutMovingTheCar()
    {
        var t = T();
        t.SetScene("city");
        t.Advance(8);
        var before = t.CarPose;
        var right = t.SetCorneringBend(1).Value.bent;
        Assert.Greater(right.bend, 0);
        Assert.GreaterOrEqual(right.start, t.Offset + 25);
        var left = t.SetCorneringBend(-.5f).Value.bent;
        Assert.AreSame(right, left);
        Assert.Less(left.bend, 0);
        PathContinuous(t);
        Assert.AreEqual(0, t.SetCorneringBend(0).Value.bent.bend, .001);
        Assert.AreEqual(before.pos, t.CarPose.pos);
        Assert.AreEqual(before.yaw, t.CarPose.yaw);
        PathContinuous(t);
    }

    [Test]
    public void SensorDoesNotOverlayNavigationTurnAlreadyCommittedToTheRoad()
    {
        var t = T();
        t.SetScene("road");
        t.SetTurns(new[] { ("right", 120f) });
        var junction = Junction(t);
        t.Advance(junction.start - 10);
        t.SetTurns(new (string, float)[0]);
        Assert.IsTrue(t.HasCommittedManeuver);
        Assert.IsNull(t.SetCorneringBend(-1));
        t.Advance(junction.End - t.Offset + 1);
        Assert.IsFalse(t.HasCommittedManeuver);
        Assert.Less(t.SetCorneringBend(-1).Value.bent.bend, 0);
        PathContinuous(t);
    }

    static void PathContinuous(ChunkTrack t)
    {
        var chunks = t.Live.Values.OrderBy(c => c.index).ToList();
        for (var i = 1; i < chunks.Count; i++)
        {
            var end = ChunkTrack.PoseIn(chunks[i - 1], chunks[i - 1].length);
            Assert.Less(Vector3.Distance(end.pos, chunks[i].path.pos), 0.01f, $"조각 {chunks[i].index}");
            Assert.AreEqual(0f, Mathf.DeltaAngle(end.yaw, chunks[i].path.yaw), 0.01f);
        }
    }
}
