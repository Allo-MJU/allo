using System.Collections.Generic;
using Allo.Critters;
using NUnit.Framework;
using UnityEngine;

public class CritterBrainTests
{
    static WalkGraph G() => new WalkGraph(new List<WalkSurface>
    {
        new WalkSurface("Walk_RearSeat", new Vector3(0, 0.44f, 0.22f), new Vector2(1.26f, 0.4f)),
        new WalkSurface("Walk_Armrest", new Vector3(0, 0.56f, 0.24f), new Vector2(0.2f, 0.38f)),
        new WalkSurface("Walk_RearShelf", new Vector3(0, 0.75f, 0.72f), new Vector2(1.26f, 0.2f)),
        new WalkSurface("Walk_DoorSill_L", new Vector3(0.69f, 0.67f, -0.6f), new Vector2(0.06f, 2.2f)),
    });

    static readonly Mood Day = new Mood { moving = true };

    static HashSet<CritterState> Run(CritterBrain b, Mood m, float seconds)
    {
        var seen = new HashSet<CritterState>();
        for (var t = 0f; t < seconds; t += 0.05f)
        {
            b.Tick(0.05f, m);
            seen.Add(b.State);
        }
        return seen;
    }

    [Test]
    public void RoamsWalksAndJumpsOnADay()
    {
        var seen = Run(new CritterBrain(G(), 0, 1), Day, 120);
        Assert.IsTrue(seen.Contains(CritterState.Walk), "CritterState.Walk");
        Assert.IsTrue(seen.Contains(CritterState.Jump), "CritterState.Jump");
        Assert.IsTrue(seen.Contains(CritterState.Idle), "CritterState.Idle");
        Assert.IsFalse(seen.Contains(CritterState.Sleep), "CritterState.Sleep");
    }

    [Test]
    public void SleepsAtNight()
    {
        var seen = Run(new CritterBrain(G(), 0, 2), new Mood { night = true, moving = true }, 60);
        Assert.IsTrue(seen.Contains(CritterState.Sleep), "CritterState.Sleep");
    }

    [Test]
    public void PeeksAtWindowWhenRaining()
    {
        var seen = Run(new CritterBrain(G(), 0, 3), new Mood { rain = true, moving = true }, 120);
        Assert.IsTrue(seen.Contains(CritterState.Peek), "CritterState.Peek");
    }

    [Test]
    public void HuddlesInTunnel()
    {
        var seen = Run(new CritterBrain(G(), 0, 4), new Mood { tunnel = true, moving = true }, 60);
        Assert.IsTrue(seen.Contains(CritterState.Huddle), "CritterState.Huddle");
    }

    [Test]
    public void JoltTumblesThenRecovers()
    {
        var b = new CritterBrain(G(), 0, 5);
        b.Jolt();
        Assert.AreEqual(CritterState.Tumble, b.State);
        Run(b, Day, CritterBrain.TumbleSeconds + 0.2f);
        Assert.AreNotEqual(CritterState.Tumble, b.State);
    }

    [Test]
    public void JoltWhileTumblingRestarts()
    {
        var b = new CritterBrain(G(), 0, 6);
        b.Jolt();
        b.Tick(CritterBrain.TumbleSeconds * 0.8f, Day);
        b.Jolt();
        b.Tick(CritterBrain.TumbleSeconds * 0.5f, Day);
        Assert.AreEqual(CritterState.Tumble, b.State);
    }

    [Test]
    public void TargetIsAlwaysOnItsSurface()
    {
        var g = G();
        var b = new CritterBrain(g, 0, 7);
        for (var t = 0f; t < 200; t += 0.05f)
        {
            b.Tick(0.05f, Day);
            var s = g.Surfaces[b.Surface];
            Assert.AreEqual(s.center.y, b.Target.y, 1e-4, $"t={t}");
            Assert.LessOrEqual(Mathf.Abs(b.Target.x - s.center.x), s.size.x / 2 + 1e-4f);
            Assert.LessOrEqual(Mathf.Abs(b.Target.z - s.center.z), s.size.y / 2 + 1e-4f);
        }
    }

    [Test]
    public void IsolatedSurfaceNeverJumps()
    {
        var g = new WalkGraph(new List<WalkSurface> { new WalkSurface("A", Vector3.zero, Vector2.one) });
        var seen = Run(new CritterBrain(g, 0, 8), Day, 120);
        Assert.IsFalse(seen.Contains(CritterState.Jump), "CritterState.Jump");
    }

    [Test]
    public void AwakeForKeepsNewbornUpAtNight()
    {
        var g = new Allo.Critters.WalkGraph(new[] { new Allo.Critters.WalkSurface("a", Vector3.zero, new Vector2(1, 1)) });
        var b = new Allo.Critters.CritterBrain(g, 0, 3) { AwakeFor = 8 };
        var night = new Allo.Critters.Mood { night = true };
        for (var t = 0f; t < 6; t += 0.1f) b.Tick(0.1f, night);
        Assert.AreNotEqual(Allo.Critters.CritterState.Sleep, b.State);
        for (var t = 0f; t < 20; t += 0.1f) b.Tick(0.1f, night);
        Assert.AreEqual(Allo.Critters.CritterState.Sleep, b.State, "깨어 있는 시간이 지나면 밤에는 다시 존다");
    }
}
