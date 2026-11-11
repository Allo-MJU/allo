using System.Collections.Generic;
using System.Linq;
using Allo.Critters;
using NUnit.Framework;
using UnityEditor.SceneManagement;
using UnityEngine;

/// 캐릭터가 갈 수 있는 면: 아이 눈에서 가려진 면은 빼고, 앞뒤 좌석 사이 바닥은 넣는다
public class CritterVisibilityTests
{
    readonly List<GameObject> _made = new();

    [TearDown]
    public void Clean()
    {
        foreach (var g in _made) Object.DestroyImmediate(g);
        _made.Clear();
    }

    MeshCollider Wall(Vector3 center, Vector3 size)
    {
        var g = GameObject.CreatePrimitive(PrimitiveType.Cube);
        _made.Add(g);
        g.transform.position = center;
        g.transform.localScale = size;
        Object.DestroyImmediate(g.GetComponent<Collider>());
        var c = g.AddComponent<MeshCollider>();
        c.sharedMesh = g.GetComponent<MeshFilter>().sharedMesh;
        Physics.SyncTransforms();
        return c;
    }

    static readonly Vector3 Eye = new(0, 0.9f, 0);
    static Bounds Shelf => new(new Vector3(0, 0.74f, -0.5f), new Vector3(1.2f, 0.01f, 0.2f));

    [Test]
    public void SurfaceBehindTallSeatBackIsHidden()
    {
        // 아이가 기댄 등받이: 눈보다 높다
        var back = Wall(new Vector3(0, 0.72f, -0.25f), new Vector3(1.4f, 0.62f, 0.14f));
        Assert.IsTrue(CritterDirector.HiddenFromChild(Shelf, Eye, new[] { back }));
    }

    [Test]
    public void SurfaceIsVisibleWithoutOccluder()
    {
        var back = Wall(new Vector3(5, 0, 5), Vector3.one * 0.1f);
        Assert.IsFalse(CritterDirector.HiddenFromChild(Shelf, Eye, new[] { back }));
    }

    [Test]
    public void ExistingTapCollidersDoNotCount()
    {
        // 유리처럼 탭용 충돌체가 이미 있는 물체는 가림으로 세지 않는다
        Wall(new Vector3(0, 0.72f, -0.25f), new Vector3(1.4f, 0.62f, 0.14f));
        Assert.IsFalse(CritterDirector.HiddenFromChild(Shelf, Eye, new MeshCollider[0]));
    }

    [Test]
    public void FloorConnectsToSeatAndSills()
    {
        var g = new WalkGraph(new List<WalkSurface>
        {
            new("Walk_Floor", new Vector3(0, 0.012f, 0.56f), new Vector2(1.22f, 0.32f)),
            new("Walk_RearSeat_R", new Vector3(0.33f, 0.445f, -0.17f), new Vector2(0.36f, 0.3f)),
            new("Walk_DoorSill_L", new Vector3(-0.69f, 0.665f, 0.6f), new Vector2(0.06f, 2.23f)),
        });
        var floor = g.IndexOf("Walk_Floor");
        CollectionAssert.Contains((System.Collections.ICollection)g.Neighbors(floor), g.IndexOf("Walk_RearSeat_R"));
        CollectionAssert.Contains((System.Collections.ICollection)g.Neighbors(floor), g.IndexOf("Walk_DoorSill_L"));
    }

    [Test]
    public void ComfortZoneKeepsCharacterInFrontAndNotTooClose()
    {
        var eye = new Vector3(0, 0.9f, 0);
        var fwd = Vector3.forward;
        Assert.IsTrue(CritterDirector.Comfortable(new Vector3(0, 0.01f, 1.0f), eye, fwd), "앞 바닥");
        Assert.IsFalse(CritterDirector.Comfortable(new Vector3(0.3f, 0.45f, 0.1f), eye, fwd), "바로 옆 자리(너무 가깝다)");
        Assert.IsFalse(CritterDirector.Comfortable(new Vector3(0.9f, 0.45f, 0f), eye, fwd), "옆(정면에서 90도)");
        Assert.IsFalse(CritterDirector.Comfortable(new Vector3(0, 0.01f, 0.5f), eye, fwd), "발밑(너무 가깝고 아래)");
    }

    [Test]
    public void RandomPointPrefersComfortableSpots()
    {
        var g = new WalkGraph(new List<WalkSurface> { new("Walk_Floor", new Vector3(0, 0, 1), new Vector2(1.2f, 1.2f)) });
        g.Comfortable = p => p.z > 1.2f;
        var rng = new System.Random(3);
        for (var i = 0; i < 50; i++) Assert.Greater(g.RandomPoint(0, rng).z, 1.2f);
    }

    [Test]
    public void BakedSceneHasFloorAndNoHiddenShelf()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/Explore.unity");
        var d = Object.FindFirstObjectByType<CritterDirector>();
        var names = d.BuildGraph().Surfaces.Select(s => s.name).ToList();
        CollectionAssert.Contains(names, "Walk_Floor");
        CollectionAssert.Contains(names, "Walk_Dashboard");
        CollectionAssert.DoesNotContain(names, "Walk_RearShelf");
        CollectionAssert.DoesNotContain(names, "Walk_RearSeat_R"); // 아이 바로 옆: 너무 가깝고 정면에서 90도
        var g = d.BuildGraph();
        Assert.IsNotEmpty(g.Neighbors(g.IndexOf("Walk_Floor")));
    }
}
