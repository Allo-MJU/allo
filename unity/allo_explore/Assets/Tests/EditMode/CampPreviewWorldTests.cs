using System;
using System.Collections.Generic;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.Rendering;
using Object = UnityEngine.Object;

public class CampPreviewWorldTests
{
    GameObject _host, _cameraObject, _sunObject;
    AppWorld _world;
    readonly List<GameObject> _originalMainCameras = new List<GameObject>();
    Camera _main;
    Light _sun;
    bool _fog;
    AmbientMode _ambientMode;
    Color _ambient;
    float _shadowDistance;
    ShadowQuality _shadows;

    [SetUp]
    public void SetUp()
    {
        _shadowDistance = QualitySettings.shadowDistance; _shadows = QualitySettings.shadows;
        _fog = RenderSettings.fog; _ambientMode = RenderSettings.ambientMode; _ambient = RenderSettings.ambientLight;
        // Full-suite runs can retain a loaded cabin scene. Reserve MainCamera for this fixture and restore its prior owners.
        foreach (var camera in Object.FindObjectsByType<Camera>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            if (camera.CompareTag("MainCamera")) { _originalMainCameras.Add(camera.gameObject); camera.tag = "Untagged"; }
        _cameraObject = new GameObject("Camp test cabin camera"); _main = _cameraObject.AddComponent<Camera>(); _cameraObject.tag = "MainCamera";
        _main.cullingMask = ~0; _main.transform.position = new Vector3(1, 2, 3);
        _sunObject = new GameObject("Camp test original sun"); _sun = _sunObject.AddComponent<Light>(); _sun.cullingMask = ~0;
        _host = new GameObject("Camp test host"); _world = _host.AddComponent<AppWorld>();
    }
    [TearDown]
    public void TearDown()
    {
        DestroyWorld(); Object.DestroyImmediate(_cameraObject); Object.DestroyImmediate(_sunObject);
        foreach (var camera in _originalMainCameras) if (camera != null) camera.tag = "MainCamera";
        _originalMainCameras.Clear();
        QualitySettings.shadowDistance = _shadowDistance; QualitySettings.shadows = _shadows;
        RenderSettings.fog = _fog; RenderSettings.ambientMode = _ambientMode; RenderSettings.ambientLight = _ambient;
    }
    void DestroyWorld()
    {
        if (_host == null) return;
        // Runtime MonoBehaviour lifecycle messages are not automatically dispatched by EditMode destruction.
        typeof(AppWorld).GetMethod("OnDestroy", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(_world, null);
        Object.DestroyImmediate(_host);
    }
    static RenderTexture Preview()
    {
        var property = typeof(AppWorld).GetProperty("CampPreview", BindingFlags.Static | BindingFlags.Public);
        Assert.NotNull(property, "AppWorld must expose the isolated camp RenderTexture to its UGUI layer");
        return (RenderTexture)property.GetValue(null);
    }
    Camera CampCamera() => Array.Find(Object.FindObjectsByType<Camera>(FindObjectsInactive.Include, FindObjectsSortMode.None), c => c.targetTexture == Preview());

    [Test]
    public void PreviewIsIsolatedFromCabinCameraAndReleasesItsTextureOnDestroy()
    {
        _world.SetView("home"); var texture = Preview(); Assert.NotNull(texture);
        var camp = CampCamera(); Assert.NotNull(camp); Assert.AreNotSame(_main, camp); Assert.AreEqual("Untagged", camp.tag);
        Assert.AreEqual(1 << 30, camp.cullingMask); Assert.IsTrue(camp.orthographic); Assert.AreSame(_main, Camera.main);
        Assert.AreEqual(16f / 9, (float)texture.width / texture.height, .001f); Assert.GreaterOrEqual(texture.width, 1920);
        Assert.GreaterOrEqual(texture.depth, 16); Assert.IsTrue(texture.IsCreated());
        Assert.AreEqual(0, _sun.cullingMask & (1 << 30), "original cabin lighting must not wash out camp");
        foreach (var renderer in camp.transform.parent.GetComponentsInChildren<Renderer>(true)) Assert.AreEqual(30, renderer.gameObject.layer);
        DestroyWorld(); Assert.IsTrue(texture == null); Assert.IsNull(Preview()); Assert.AreEqual(~0, _sun.cullingMask);
    }

    [Test]
    public void FacilityFeetProjectToTheSameAnchorsAsUiHitNodes()
    {
        _world.Apply(new AppState { view = "camp", facilities = new[] { new FacilityState { id = "workshop", level = 2 } } });
        var camp = CampCamera(); Assert.NotNull(camp);
        var anchor = typeof(AppWorld).GetMethod("FacilityAnchor", BindingFlags.Public | BindingFlags.Static); Assert.NotNull(anchor);
        foreach (var id in new[] { "workshop", "kitchen", "training" })
        {
            var root = camp.transform.parent.Find("Facility " + id); Assert.NotNull(root);
            var expected = (Vector2)anchor.Invoke(null, new object[] { id });
            var actual = camp.WorldToViewportPoint(root.position);
            Assert.Greater(actual.z, 0); Assert.Less(Vector2.Distance(expected, actual), .001f, id + " rendered feet must match the interactive map");
            Assert.IsNotEmpty(root.GetComponentsInChildren<Renderer>(), id + " must contain actual 3D work props");
        }
    }

    [Test]
    public void SnapshotLevelsAddOnlySavedUpgradesAndLostTextureIsRecreated()
    {
        var snapshot = new AppState { view = "home", facilities = new[] { new FacilityState { id = "workshop", level = 2 }, new FacilityState { id = "kitchen", level = 0 } } };
        _world.Apply(snapshot); var camp = CampCamera(); Assert.NotNull(camp);
        Assert.IsTrue(camp.transform.parent.Find("Facility workshop/Level 2").gameObject.activeSelf);
        Assert.IsFalse(camp.transform.parent.Find("Facility workshop/Level 3").gameObject.activeSelf);
        Assert.IsFalse(camp.transform.parent.Find("Facility kitchen/Level 2").gameObject.activeSelf);
        snapshot.facilities[0].level = 3; _world.Apply(snapshot);
        Assert.IsTrue(camp.transform.parent.Find("Facility workshop/Level 3").gameObject.activeSelf);
        Preview().Release(); Assert.IsFalse(Preview().IsCreated());
        _world.SetView("home"); Assert.IsTrue(Preview().IsCreated());
        Assert.AreEqual(3, snapshot.facilities[0].level, "rendering must never mutate the Core snapshot");
    }

    [Test]
    public void MenuAndCabinDisablePreviewAndRestoreOriginalEnvironment()
    {
        RenderSettings.fog = true; RenderSettings.ambientMode = AmbientMode.Flat; RenderSettings.ambientLight = Color.red;
        QualitySettings.shadowDistance = 20; QualitySettings.shadows = ShadowQuality.Disable;
        _world.SetView("home"); var camp = CampCamera(); Assert.NotNull(camp); Assert.IsTrue(camp.enabled);
        Assert.GreaterOrEqual(QualitySettings.shadowDistance, 60); Assert.AreEqual(ShadowQuality.All, QualitySettings.shadows);
        _world.SetView("inventory"); Assert.IsFalse(camp.enabled); Assert.AreEqual(~0, _sun.cullingMask);
        _world.SetView("camp"); Assert.IsTrue(camp.enabled);
        _world.SetView("cabin"); Assert.IsFalse(camp.enabled); Assert.AreEqual(~0, _main.cullingMask);
        Assert.AreEqual(new Vector3(1, 2, 3), _main.transform.position); Assert.AreEqual(~0, _sun.cullingMask);
        Assert.IsTrue(RenderSettings.fog); Assert.AreEqual(AmbientMode.Flat, RenderSettings.ambientMode); Assert.AreEqual(Color.red, RenderSettings.ambientLight);
        Assert.AreEqual(20, QualitySettings.shadowDistance); Assert.AreEqual(ShadowQuality.Disable, QualitySettings.shadows);
    }
}
