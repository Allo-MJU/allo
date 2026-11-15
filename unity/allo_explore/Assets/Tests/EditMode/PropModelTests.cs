using System.Collections.Generic;
using Allo.Critters;
using NUnit.Framework;
using UnityEngine;

/// 소품 3D 모델(Resources/Props/P_{ID}): 프리팹이 있으면 Toys.Make 가 도형 대신 쓰고, 크기·발밑 원점이 기존 도형과 맞는다
public class PropModelTests
{
    readonly List<Object> _made = new();

    [TearDown]
    public void Clean()
    {
        foreach (var o in _made) if (o != null) Object.DestroyImmediate(o);
        _made.Clear();
    }

    Transform Make(Toys.Kind k)
    {
        var t = Toys.Make(k);
        _made.Add(t.gameObject);
        return t;
    }

    [Test]
    public void EggModelStandsOnItsFootAtEggSize()
    {
        if (Toys.PropModel(Toys.Kind.Egg) == null) Assert.Ignore("P_egg 없음 (scripts/import_props.sh)");
        var egg = Make(Toys.Kind.Egg);
        Assert.IsNotNull(egg.Find("Model"), "프리팹이 있으면 모델을 쓴다");
        var b = Toys.BoundsOf(egg);
        Assert.AreEqual(Toys.EggH, b.size.y, 0.005f);
        Assert.AreEqual(0, b.min.y, 0.003f);
        Assert.AreEqual(Toys.EggW, b.size.x, 0.01f);
    }

    [Test]
    public void EggHalvesStackBackIntoTheEgg()
    {
        if (Toys.PropModel(Toys.Kind.EggTop) == null || Toys.PropModel(Toys.Kind.EggBottom) == null) Assert.Ignore("P_egg_top·bottom 없음");
        var bottom = Toys.BoundsOf(Make(Toys.Kind.EggBottom));
        var top = Toys.BoundsOf(Make(Toys.Kind.EggTop));
        // 아래 껍데기는 바닥에서, 윗껍데기는 원점(금 높이)에서 시작한다. 둘을 금 높이에 맞춰 쌓으면 알 키
        Assert.AreEqual(0, bottom.min.y, 0.003f);
        Assert.AreEqual(0, top.min.y, 0.006f);
        Assert.Less(bottom.size.y, Toys.EggH);
        Assert.Less(top.size.y, Toys.EggH * 0.5f);
    }

    [Test]
    public void GivenPlushIsSmallerThanSeatPlush()
    {
        if (Toys.PropModel(Toys.Kind.Plush) == null) Assert.Ignore("P_plush 없음");
        var b = Toys.BoundsOf(Make(Toys.Kind.Plush));
        Assert.AreEqual(0.13f, b.size.y, 0.01f);
    }

    [Test]
    public void DestroyedSharedTemplateIsRecreatedForShapeFallback()
    {
        Make(Toys.Kind.Cup);
        var field = typeof(Toys).GetField("_toon", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
        Object.DestroyImmediate((Material)field.GetValue(null));
        var cup = Make(Toys.Kind.Cup);
        Assert.Greater(cup.GetComponentsInChildren<Renderer>().Length, 0);
    }

    [Test]
    public void KindsWithoutModelKeepShapes()
    {
        var cup = Make(Toys.Kind.Cup);
        Assert.IsNull(cup.Find("Model"));
        Assert.Greater(cup.GetComponentsInChildren<Renderer>().Length, 0);
    }
}
