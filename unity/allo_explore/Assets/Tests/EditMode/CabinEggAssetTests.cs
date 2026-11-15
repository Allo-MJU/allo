using System.Collections.Generic;
using System.Linq;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using Object = UnityEngine.Object;

public class CabinEggAssetTests
{
    readonly List<Transform> _hiddenCabins = new List<Transform>();
    GameObject _cabin, _host;
    CabinEgg _egg;

    [SetUp]
    public void SetUp()
    {
        foreach (var t in Object.FindObjectsByType<Transform>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            if (t.name == "Cabin") { _hiddenCabins.Add(t); t.name = "Other cabin during asset test"; }
        _cabin = new GameObject("Cabin");
        for (var i = 0; i < 4; i++)
        {
            var surface = GameObject.CreatePrimitive(PrimitiveType.Cube);
            surface.name = CabinEgg.ZoneSurfaceName(i);
            surface.transform.SetParent(_cabin.transform, false);
            surface.transform.position = new Vector3(i * 2, .5f, 0);
            surface.GetComponent<Renderer>().enabled = false;
        }
        _host = new GameObject("Egg asset test");
        _egg = _host.AddComponent<CabinEgg>();
        _egg.SetView("cabin");
        _egg.Apply(State());
    }
    [TearDown]
    public void TearDown()
    {
        Object.DestroyImmediate(_host); Object.DestroyImmediate(_cabin);
        foreach (var t in _hiddenCabins) if (t != null) t.name = "Cabin";
        _hiddenCabins.Clear();
    }

    [Test]
    public void ActiveEggReusesTheExistingMeshTextureAndIndependentMaterial()
    {
        var prefab = Resources.Load<GameObject>("Props/P_egg");
        Assert.IsNotNull(prefab);
        var source = prefab.GetComponentInChildren<MeshFilter>();
        var sourceMaterial = prefab.GetComponentInChildren<Renderer>().sharedMaterial;
        var body = _host.transform.Find("Cabin egg visuals/Cabin egg");
        Assert.IsTrue(body.GetComponentsInChildren<MeshFilter>().Any(f => f.sharedMesh == source.sharedMesh));
        var renderer = body.GetComponentInChildren<Renderer>();
        Assert.AreSame(sourceMaterial.mainTexture, renderer.sharedMaterial.mainTexture);
        Assert.AreNotSame(sourceMaterial, renderer.sharedMaterial);
        var color = sourceMaterial.color;
        var state = State(); state.egg.photoRequired = true; _egg.Apply(state);
        Assert.AreEqual(color, sourceMaterial.color, "photo feedback must not recolor the shared authored asset");
    }

    [Test]
    public void AuthoredEggFitsTheExistingInteractionHeightAndCenteredCollider()
    {
        var body = _host.transform.Find("Cabin egg visuals/Cabin egg");
        var renderer = body.GetComponentInChildren<Renderer>();
        var bounds = CabinEgg.SurfaceBounds(renderer);
        Assert.That(bounds.size.y, Is.EqualTo(CabinEgg.EggHeight).Within(.001f));
        Assert.That(Vector3.Distance(bounds.center, body.position), Is.LessThan(.001f));
        var collider = body.GetComponent<Collider>(); Assert.IsNotNull(collider);
        Physics.SyncTransforms();
        Assert.IsTrue(collider.bounds.Contains(bounds.min));
        Assert.IsTrue(collider.bounds.Contains(bounds.max));
    }

    static AppState State() => new AppState
    {
        view = "cabin", ready = true, connected = true,
        egg = new EggState { id = "authored-egg", active = true, zone = 0 }
    };
}
