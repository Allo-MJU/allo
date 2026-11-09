using System.Collections.Generic;
using Allo.Critters;
using NUnit.Framework;
using UnityEngine;

public class WalkGraphTests
{
    static WalkGraph Sample() => new WalkGraph(new List<WalkSurface>
    {
        new WalkSurface("Walk_RearSeat", new Vector3(0, 0.44f, 0.22f), new Vector2(1.26f, 0.4f)),
        new WalkSurface("Walk_Armrest", new Vector3(0, 0.56f, 0.24f), new Vector2(0.2f, 0.38f)),
        new WalkSurface("Walk_RearShelf", new Vector3(0, 0.75f, 0.72f), new Vector2(1.26f, 0.2f)),
        new WalkSurface("Walk_Dashboard", new Vector3(0, 0.98f, -1.74f), new Vector2(1.16f, 0.3f)),
        new WalkSurface("Walk_Far", new Vector3(10, 0, 10), new Vector2(0.2f, 0.2f)),
    });

    [Test]
    public void NearbySurfacesAreNeighbors()
    {
        var g = Sample();
        var seat = g.IndexOf("Walk_RearSeat");
        Assert.Contains(g.IndexOf("Walk_Armrest"), (System.Collections.ICollection)g.Neighbors(seat));
        Assert.Contains(g.IndexOf("Walk_RearShelf"), (System.Collections.ICollection)g.Neighbors(seat));
    }

    [Test]
    public void TooFarIsNotNeighbor()
    {
        var g = Sample();
        CollectionAssert.DoesNotContain((System.Collections.ICollection)g.Neighbors(g.IndexOf("Walk_RearSeat")), g.IndexOf("Walk_Dashboard"));
    }

    [Test]
    public void IsolatedSurfaceHasNoNeighbors()
    {
        var g = Sample();
        Assert.AreEqual(0, g.Neighbors(g.IndexOf("Walk_Far")).Count);
    }

    [Test]
    public void RandomPointStaysInside()
    {
        var g = Sample();
        var rng = new System.Random(3);
        var i = g.IndexOf("Walk_RearSeat");
        var s = g.Surfaces[i];
        for (var k = 0; k < 200; k++)
        {
            var p = g.RandomPoint(i, rng);
            Assert.LessOrEqual(Mathf.Abs(p.x - s.center.x), s.size.x / 2);
            Assert.LessOrEqual(Mathf.Abs(p.z - s.center.z), s.size.y / 2);
            Assert.AreEqual(s.center.y, p.y, 1e-4);
        }
    }

    [Test]
    public void NearestPicksClosestSurface()
    {
        var g = Sample();
        Assert.AreEqual(g.IndexOf("Walk_Dashboard"), g.Nearest(new Vector3(0.1f, 1f, -1.6f)));
        Assert.AreEqual(-1, g.IndexOf("nope"));
    }

    [Test]
    public void NarrowSurfaceUsesCenterOnly()
    {
        var g = new WalkGraph(new List<WalkSurface> { new WalkSurface("Walk_Headrest_FL", new Vector3(1, 1.2f, -0.6f), new Vector2(0.22f, 0.08f)) });
        var rng = new System.Random(1);
        for (var k = 0; k < 20; k++) Assert.AreEqual(g.Surfaces[0].center, g.RandomPoint(0, rng));
    }
}
