using System.Collections.Generic;
using Allo.Critters;
using NUnit.Framework;
using UnityEngine;

/// 3D 캐릭터 모델: 모델이 있으면 그림 대신 세우고, 걸을 땐 가는 쪽을 본다
public class CritterModelTests
{
    readonly List<Object> _made = new();

    [TearDown]
    public void Clean()
    {
        foreach (var o in _made) if (o != null) Object.DestroyImmediate(o);
        _made.Clear();
    }

    GameObject FakePrefab()
    {
        var root = new GameObject("C_fake");
        _made.Add(root);
        var info = root.AddComponent<CharacterModel>();
        info.height = 0.3f;
        info.footprint = new Vector2(0.2f, 0.3f);
        var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
        Object.DestroyImmediate(cube.GetComponent<Collider>());
        cube.transform.SetParent(root.transform, false);
        cube.transform.localScale = new Vector3(0.2f, 0.3f, 0.3f);
        cube.transform.localPosition = Vector3.up * 0.15f;
        return root;
    }

    CritterView View(CritterBrain brain, GameObject prefab)
    {
        var go = new GameObject("Critter");
        _made.Add(go);
        var v = go.AddComponent<CritterView>();
        var mat = new Material(Shader.Find("Allo/Sprite"));
        _made.Add(mat);
        v.Init("fake", brain, CritterArt.Placeholder("water", 1), mat, mat, prefab);
        return v;
    }

    static CritterBrain Brain() =>
        new(new WalkGraph(new List<WalkSurface> { new("Walk_A", Vector3.zero, new Vector2(3, 3)) }), 0, 1);

    [Test]
    public void ModelReplacesPictureAndStandsOnFeet()
    {
        var brain = Brain();
        var v = View(brain, FakePrefab());
        Assert.IsTrue(v.Is3D);
        v.Pose(null, 0.01f);
        var r = v.GetComponentInChildren<MeshRenderer>();
        Assert.AreEqual(CritterView.Height, r.bounds.size.y, 0.03f);
        Assert.AreEqual(brain.Position.y, r.bounds.min.y, 0.03f);
    }

    [Test]
    public void WalkingFacesWhereItGoes()
    {
        var brain = Brain();
        var v = View(brain, FakePrefab());
        brain.GoTo(brain.Position + Vector3.right * 1.2f);
        var mood = new Mood { moving = true };
        for (var i = 0; i < 20; i++)
        {
            brain.Tick(0.05f, mood);
            v.Pose(null, 0.05f);
        }
        var fwd = v.transform.Find("Body").forward;
        fwd.y = 0;
        Assert.Greater(Vector3.Dot(fwd.normalized, Vector3.right), 0.9f);
    }

    [Test]
    public void NoModelKeepsPicture()
    {
        var v = View(Brain(), null);
        Assert.IsFalse(v.Is3D);
        Assert.IsNotNull(v.transform.Find("Body").GetComponent<MeshRenderer>());
    }
}
