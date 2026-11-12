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
    public void LeavesZeroWeightSurfaceForWeightedNeighbor()
    {
        // 둥지 콘솔(비중 0) ↔ 발판(0.6) ↔ 옆자리(1). 콘솔에서 깨어나면 곧 아이 곁으로 온다
        var g = new WalkGraph(new List<WalkSurface>
        {
            new WalkSurface("Walk_Console", new Vector3(0, 0.38f, 1.06f), new Vector2(0.2f, 0.2f)),
            new WalkSurface("Walk_Floor", new Vector3(0, 0.01f, 0.5f), new Vector2(1.2f, 0.25f)),
            new WalkSurface("Walk_RearSeat_R", new Vector3(0.33f, 0.445f, -0.17f), new Vector2(0.36f, 0.3f)),
        });
        g.Weight = i => CritterDirector.RoamWeight(g.Surfaces[i].name);
        var b = new CritterBrain(g, 0, 11);
        var onConsole = 0f;
        for (var t = 0f; t < 60; t += 0.05f)
        {
            b.Tick(0.05f, Day);
            if (b.Surface == 0) onConsole += 0.05f;
        }
        Assert.Less(onConsole, 6f, "콘솔에 오래 머물지 않는다");
        Assert.AreNotEqual(0, b.Surface, "60초 뒤에는 콘솔이 아니다");
        // 돌아온 뒤에는 콘솔로 스스로 가지 않는다
        for (var t = 0f; t < 120; t += 0.05f)
        {
            b.Tick(0.05f, Day);
            Assert.AreNotEqual(0, b.Surface, $"t={t}");
        }
    }

    [Test]
    public void ComesHomeFromNestEvenAtNightOrInTunnel()
    {
        var g = new WalkGraph(new List<WalkSurface>
        {
            new WalkSurface("Walk_Console", new Vector3(0, 0.38f, 1.06f), new Vector2(0.2f, 0.2f)),
            new WalkSurface("Walk_Floor", new Vector3(0, 0.01f, 0.5f), new Vector2(1.2f, 0.25f)),
        });
        g.Weight = i => CritterDirector.RoamWeight(g.Surfaces[i].name);
        foreach (var m in new[] { new Mood { night = true, moving = true }, new Mood { tunnel = true, moving = true } })
        {
            var b = new CritterBrain(g, 0, 13);
            Run(b, m, 20);
            Assert.AreEqual(1, b.Surface, $"night={m.night} tunnel={m.tunnel}: 둥지에서 잠들지 않고 발판으로 내려온다");
        }
    }

    [Test]
    public void StrollsStayShortAndSlow()
    {
        var g = new WalkGraph(new List<WalkSurface> { new WalkSurface("Walk_RearSeat_R", new Vector3(0, 0.44f, 0), new Vector2(1.2f, 1.2f)) });
        var b = new CritterBrain(g, 0, 12);
        var walks = 0;
        var last = CritterState.Idle;
        var from = b.Position;
        for (var t = 0f; t < 120; t += 0.05f)
        {
            if (b.State != CritterState.Walk) from = b.Position;
            b.Tick(0.05f, Day);
            if (b.State == CritterState.Walk && last != CritterState.Walk)
            {
                walks++;
                Assert.LessOrEqual((b.Target - from).magnitude, CritterBrain.StrollRadius + 1e-3f, $"t={t}: 한 번에 멀리 가지 않는다");
            }
            last = b.State;
        }
        Assert.Greater(walks, 3, "그래도 가끔은 걷는다");
        Assert.LessOrEqual(CritterBrain.WalkSpeed, 0.25f, "아기 걸음");
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
