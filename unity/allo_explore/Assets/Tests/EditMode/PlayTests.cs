using System.Collections.Generic;
using Allo.Critters;
using NUnit.Framework;
using UnityEngine;

/// 차 안 놀이: 던진 물건이 떨어질 자리, 놀이 중 캐릭터 행동
public class PlayTests
{
    static WalkGraph Graph() => new(new List<WalkSurface>
    {
        new("Walk_Floor", new Vector3(0, 0.01f, 0.56f), new Vector2(1.2f, 0.32f)),
        new("Walk_DoorSill_R", new Vector3(0.69f, 0.665f, 0.6f), new Vector2(0.06f, 2.2f)),
    });

    [Test]
    public void ThrowLandsWhereTheRayMeetsASurface()
    {
        var g = Graph();
        var eye = new Vector3(0, 0.9f, -0.2f);
        var target = new Vector3(0.1f, 0.01f, 0.6f);
        var (at, surf, missed) = CritterDirector.Landing(g, new Ray(eye, (target - eye).normalized));
        Assert.IsFalse(missed);
        Assert.AreEqual("Walk_Floor", g.Surfaces[surf].name);
        Assert.Less(Vector3.Distance(at, target), 0.02f);
    }

    [Test]
    public void ThrowThatMissesStillLandsOnTheNearestSurface()
    {
        var g = Graph();
        var eye = new Vector3(0, 0.9f, -0.2f);
        // 천장으로 곧게 던지면 어느 면에도 안 닿고, 노린 곳과도 멀다
        var (at, surf, missed) = CritterDirector.Landing(g, new Ray(eye, new Vector3(0, 1, 0.1f).normalized));
        Assert.IsTrue(missed);
        var s = g.Surfaces[surf];
        Assert.LessOrEqual(Mathf.Abs(at.x - s.center.x), s.size.x / 2);
        Assert.AreEqual(s.center.y, at.y, 1e-4f);
    }

    [Test]
    public void MoveToOtherSurfaceLeapsThere()
    {
        var g = Graph();
        var b = new CritterBrain(g, 0, 1);
        b.Hold = true;
        b.MoveTo(new Vector3(0.69f, 0.665f, 0.9f), 1);
        Assert.AreEqual(CritterState.Jump, b.State);
        Assert.AreEqual(1, b.Surface);
        for (var i = 0; i < 40; i++) b.Tick(0.05f, new Mood { moving = true });
        Assert.IsTrue(b.AtTarget);
        // 놀이 중(Hold)에는 도착해도 제멋대로 떠나지 않는다
        var at = b.Position;
        for (var i = 0; i < 100; i++) b.Tick(0.05f, new Mood { moving = true });
        Assert.AreEqual(at, b.Position);
    }

    [Test]
    public void BlanketKeepsItAsleepUntilRemoved()
    {
        var b = new CritterBrain(Graph(), 0, 2);
        b.Nap(1);
        b.StayAsleep = true;
        for (var i = 0; i < 200; i++) b.Tick(0.05f, new Mood { moving = true });
        Assert.AreEqual(CritterState.Sleep, b.State);
        b.StayAsleep = false;
        for (var i = 0; i < 100; i++) b.Tick(0.05f, new Mood { moving = true });
        Assert.AreNotEqual(CritterState.Sleep, b.State);
    }

    [Test]
    public void SnackMatchesTheScene()
    {
        Assert.AreEqual(Toys.Kind.Shell, Toys.SnackFor("coast"));
        Assert.AreEqual(Toys.Kind.Acorn, Toys.SnackFor("mountain"));
        Assert.AreEqual(Toys.Kind.FishBun, Toys.SnackFor("city"));
        Assert.AreEqual(Toys.Kind.Apple, Toys.SnackFor("road"));
        Assert.AreEqual("fishbun", Toys.Code(Toys.Kind.FishBun));
    }
}
