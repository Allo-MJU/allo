using System;
using Allo.App;
using NUnit.Framework;
using UnityEngine;

public class CabinEggTests
{
    [TestCase("home", false)]
    [TestCase("camp", false)]
    [TestCase("dex", false)]
    [TestCase("inventory", false)]
    [TestCase("settings", false)]
    [TestCase("cabin", true)]
    public void ActiveEggExistsOnlyInCabin(string view, bool expected)
    {
        Assert.AreEqual(expected, CabinEgg.ShowEgg(view, new EggState { id = "egg-current", active = true }));
    }

    [Test]
    public void PhotoQuestKeepsTheEggInCabin()
    {
        var egg = new EggState { id = "egg-photo", active = true, photoRequired = true, photoBusy = true };
        Assert.IsTrue(CabinEgg.ShowEgg("cabin", egg));
        Assert.IsFalse(CabinEgg.ShowEgg("home", egg));
    }

    [Test]
    public void EmptyOrFinishedEggCannotLeaveAModel()
    {
        Assert.IsFalse(CabinEgg.ShowEgg("cabin", null));
        Assert.IsFalse(CabinEgg.ShowEgg("cabin", new EggState { active = true }));
        Assert.IsFalse(CabinEgg.ShowEgg("cabin", new EggState { id = "old", active = false, phase = "hatched" }));
    }

    [Test]
    public void SavedHatchRevealIsAlsoConfinedToCabin()
    {
        var egg = new EggState { id = "saved", active = false, phase = "hatched" };
        Assert.IsTrue(CabinEgg.ShowReveal("cabin", egg));
        Assert.IsFalse(CabinEgg.ShowReveal("home", egg));
        egg.phase = "failed";
        Assert.IsFalse(CabinEgg.ShowReveal("cabin", egg));
    }

    [Test]
    public void FourZonesUseDistinctExistingCabinSurfaces()
    {
        var surfaces = new string[4];
        for (var zone = 0; zone < 4; zone++) surfaces[zone] = CabinEgg.ZoneSurfaceName(zone);
        CollectionAssert.AreEquivalent(new[] { "Walk_Dashboard", "Walk_DoorSill_L", "Walk_DoorSill_R", "Walk_Floor" }, surfaces);
        Assert.Throws<ArgumentOutOfRangeException>(() => CabinEgg.ZoneSurfaceName(-1));
        Assert.Throws<ArgumentOutOfRangeException>(() => CabinEgg.ZoneSurfaceName(4));
    }

    [Test]
    public void PlacementUsesSurfaceBoundsAndRestsAboveTheSurface()
    {
        var surface = new Bounds(new Vector3(2f, 0.6f, 3f), new Vector3(0.2f, 0.02f, 1.8f));
        var position = CabinEgg.PositionOnSurface(surface);
        Assert.That(position.x, Is.InRange(surface.min.x, surface.max.x));
        Assert.That(position.z, Is.InRange(surface.min.z, surface.max.z));
        Assert.AreEqual(surface.max.y + CabinEgg.EggHeight * 0.5f, position.y, 0.0001f);
    }

    [Test]
    public void InactiveDisabledSurfaceBoundsComeFromTransformedMesh()
    {
        var root = new GameObject("Inactive surface parent");
        try
        {
            root.transform.position = new Vector3(2, 1, 3);
            root.transform.rotation = Quaternion.Euler(0, 90, 0);
            root.transform.localScale = new Vector3(2, 1, 0.5f);
            var surface = GameObject.CreatePrimitive(PrimitiveType.Cube);
            surface.transform.SetParent(root.transform, false);
            surface.transform.localPosition = new Vector3(1, 0.1f, -2);
            surface.transform.localScale = new Vector3(0.4f, 0.02f, 1.6f);
            var renderer = surface.GetComponent<Renderer>();
            renderer.enabled = false;
            root.SetActive(false);
            // Android can leave this renderer cache empty; geometry remains available.
            renderer.bounds = new Bounds(Vector3.zero, Vector3.zero);
            var bounds = CabinEgg.SurfaceBounds(renderer);
            Assert.Less(Vector3.Distance(new Vector3(1, 1.1f, 1), bounds.center), 0.0001f);
            Assert.Less(Vector3.Distance(new Vector3(0.8f, 0.02f, 0.8f), bounds.size), 0.0001f);
            Assert.AreEqual(1.23f, CabinEgg.PositionOnSurface(bounds).y, 0.0001f);
        }
        finally { UnityEngine.Object.DestroyImmediate(root); }
    }

    [Test]
    public void HomeBeforeCabinKeepsFourInactiveSurfaceLocationsAndFullEggHeight()
    {
        var existing = new System.Collections.Generic.List<Transform>();
        foreach (var t in UnityEngine.Object.FindObjectsByType<Transform>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            if (t.name == "Cabin") { existing.Add(t); t.name = "Existing cabin during bounds test"; }
        var cabin = new GameObject("Cabin");
        var host = new GameObject("Cabin egg regression host");
        try
        {
            for (var i = 0; i < 4; i++)
            {
                var surface = GameObject.CreatePrimitive(PrimitiveType.Cube);
                surface.name = CabinEgg.ZoneSurfaceName(i);
                surface.transform.SetParent(cabin.transform, false);
                surface.transform.position = new Vector3(i + 1, 0.5f + i * 0.1f, i + 2);
                surface.transform.localScale = new Vector3(0.2f, 0.02f, 0.4f);
                var renderer = surface.GetComponent<Renderer>();
                renderer.enabled = false;
                renderer.bounds = new Bounds(Vector3.zero, Vector3.zero);
            }
            cabin.SetActive(false);
            var component = host.AddComponent<CabinEgg>();
            component.SetView("home");
            component.Apply(new AppState { view = "home" });
            var state = new AppState { view = "cabin", ready = true, egg = new EggState { id = "current", active = true } };
            component.SetView("cabin");
            component.Apply(state);
            var visuals = host.transform.Find("Cabin egg visuals");
            Assert.IsTrue(visuals.gameObject.activeSelf);
            for (var i = 0; i < 4; i++)
            {
                var marker = visuals.Find("Egg zone " + i);
                Assert.AreEqual(i + 1, marker.position.x, 0.0001f);
                Assert.AreEqual(i + 2, marker.position.z, 0.0001f);
                Assert.AreEqual(0.515f + i * 0.1f, marker.position.y, 0.0001f);
            }
            var egg = visuals.Find("Cabin egg");
            Assert.IsTrue(egg.gameObject.activeSelf);
            var local = egg.GetComponent<MeshFilter>().sharedMesh.bounds;
            Assert.AreEqual(CabinEgg.EggHeight, local.size.y * egg.lossyScale.y, 0.0001f);
            Assert.AreEqual(0.64f, egg.position.y, 0.0001f);
        }
        finally
        {
            UnityEngine.Object.DestroyImmediate(host);
            UnityEngine.Object.DestroyImmediate(cabin);
            foreach (var t in existing) if (t != null) t.name = "Cabin";
        }
    }

    [Test]
    public void GestureRequiresCurrentEggIdentityAndCabin()
    {
        var state = new AppState { ready = true, egg = new EggState { id = "current", active = true } };
        Assert.IsTrue(CabinEgg.CanInteract(state, "cabin", "current"));
        Assert.IsFalse(CabinEgg.CanInteract(state, "home", "current"));
        Assert.IsFalse(CabinEgg.CanInteract(state, "cabin", "previous"));
        state.busy = true;
        Assert.IsFalse(CabinEgg.CanInteract(state, "cabin", "current"));
    }

    [Test]
    public void IntentCarriesTheCurrentEggIdAndValidatedZone()
    {
        var state = new AppState { ready = true, egg = new EggState { id = "current", active = true } };
        var action = CabinEgg.EggIntent(state, "cabin", "current", "placeEgg", 3);
        Assert.AreEqual("current", action.eggId);
        Assert.AreEqual("placeEgg", action.action);
        Assert.AreEqual(3, action.zone);
        Assert.IsNull(CabinEgg.EggIntent(state, "cabin", "previous", "petEgg", 0));
        Assert.IsNull(CabinEgg.EggIntent(state, "cabin", "current", "placeEgg", 4));
        Assert.IsNull(CabinEgg.EggIntent(state, "cabin", "current", "discardEgg", 0));
    }

    [Test]
    public void RubbingAndMovingResolveToOneIntent()
    {
        Assert.AreEqual("petEgg", CabinEgg.GestureAction(120, 10, false, 100));
        Assert.AreEqual("placeEgg", CabinEgg.GestureAction(120, 80, true, 100));
        Assert.AreEqual("", CabinEgg.GestureAction(2, 2, false, 100));
        Assert.AreEqual("", CabinEgg.GestureAction(120, 80, false, 100));
    }
    [Test]
    public void FullAppClearsLegacyEggAndRejectsLateLegacyUpdatesButLegacyExploreStillWorks()
    {
        var previousApp = AppSession.State;
        var bridgeType = typeof(Allo.Bridge.FlutterBridge);
        var previousSettings = Allo.Bridge.FlutterBridge.LastSettings;
        var previousEgg = Allo.Bridge.FlutterBridge.LastEgg;
        var events = bridgeType.GetField("EggChanged", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic);
        var previousEvents = events.GetValue(null);
        var root = new GameObject("Legacy egg integration bridge");
        try
        {
            typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, null);
            bridgeType.GetProperty("LastSettings").SetValue(null, null);
            bridgeType.GetProperty("LastEgg").SetValue(null, null);
            events.SetValue(null, null);
            var observed = new System.Collections.Generic.List<Allo.Bridge.EggState>();
            Allo.Bridge.FlutterBridge.EggChanged += observed.Add;
            var bridge = root.AddComponent<Allo.Bridge.FlutterBridge>();
            bridge.OnFlutterMessage("{\"v\":1,\"type\":\"egg\",\"state\":\"incubating\",\"eggId\":\"legacy-first\"}");
            Assert.AreEqual("legacy-first", Allo.Bridge.FlutterBridge.LastEgg.eggId);
            bridge.OnFlutterMessage("{\"v\":1,\"type\":\"settings\",\"appMode\":true}");
            Assert.AreEqual("idle", Allo.Bridge.FlutterBridge.LastEgg.state);
            bridge.OnFlutterMessage("{\"v\":1,\"type\":\"egg\",\"state\":\"incubating\",\"eggId\":\"late-settings\"}");
            Assert.AreEqual("idle", Allo.Bridge.FlutterBridge.LastEgg.state);
            bridge.OnFlutterMessage("{\"v\":1,\"type\":\"settings\",\"appMode\":false}");
            bridge.OnFlutterMessage("{\"v\":1,\"type\":\"egg\",\"state\":\"incubating\",\"eggId\":\"legacy-return\"}");
            Assert.AreEqual("legacy-return", Allo.Bridge.FlutterBridge.LastEgg.eggId);
            bridge.OnFlutterMessage("{\"v\":2,\"type\":\"app\",\"revision\":1,\"view\":\"cabin\"}");
            Assert.IsNull(AppSession.State);
            Assert.AreEqual("legacy-return", Allo.Bridge.FlutterBridge.LastEgg.eggId);
            bridge.OnFlutterMessage("{\"v\":1,\"type\":\"app\",\"revision\":1,\"view\":\"cabin\"}");
            Assert.AreEqual("idle", Allo.Bridge.FlutterBridge.LastEgg.state);
            bridge.OnFlutterMessage("{\"v\":1,\"type\":\"egg\",\"state\":\"hatched\",\"eggId\":\"late-app\"}");
            Assert.AreEqual("idle", Allo.Bridge.FlutterBridge.LastEgg.state);
            Assert.IsFalse(observed.Exists(e => e.eggId == "late-settings" || e.eggId == "late-app"));
        }
        finally
        {
            UnityEngine.Object.DestroyImmediate(root);
            typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, previousApp);
            bridgeType.GetProperty("LastSettings").SetValue(null, previousSettings);
            bridgeType.GetProperty("LastEgg").SetValue(null, previousEgg);
            events.SetValue(null, previousEvents);
        }
    }

    [Test]
    public void AppSnapshotHidesLegacyCareHudBeforeItsSettingsArrive()
    {
        var previousApp = AppSession.State;
        var root = new GameObject("Legacy care HUD regression");
        Allo.Hud hud = null;
        var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        try
        {
            typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, null);
            hud = root.AddComponent<Allo.Hud>();
            if (root.transform.Find("Canvas") == null) typeof(Allo.Hud).GetMethod("Awake", flags).Invoke(hud, null);
            typeof(Allo.Hud).GetMethod("OnDisable", flags).Invoke(hud, null);
            typeof(Allo.Hud).GetMethod("OnEnable", flags).Invoke(hud, null);
            typeof(Allo.Hud).GetMethod("OnSettings", flags).Invoke(hud, new object[] { new Allo.Bridge.SettingsState() });
            Assert.IsTrue(root.transform.Find("Canvas").gameObject.activeSelf);
            AppSession.Receive(new AppState { revision = 1, view = "cabin" });
            Assert.IsFalse(root.transform.Find("Canvas").gameObject.activeSelf);
            typeof(Allo.Hud).GetMethod("OnSettings", flags).Invoke(hud, new object[] { new Allo.Bridge.SettingsState() });
            Assert.IsFalse(root.transform.Find("Canvas").gameObject.activeSelf);
        }
        finally
        {
            if (hud != null) typeof(Allo.Hud).GetMethod("OnDisable", flags).Invoke(hud, null);
            UnityEngine.Object.DestroyImmediate(root);
            typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, previousApp);
        }
    }

    [TestCase("cabin")]
    [TestCase("home")]
    public void AppTransitionCancelsAnAlreadyTrackedLegacyHatchVisual(string firstView)
    {
        var previousApp = AppSession.State;
        var bridgeType = typeof(Allo.Bridge.FlutterBridge);
        var previousSettings = Allo.Bridge.FlutterBridge.LastSettings;
        var previousEgg = Allo.Bridge.FlutterBridge.LastEgg;
        var events = bridgeType.GetField("EggChanged", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic);
        var previousEvents = events.GetValue(null);
        var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var directorType = typeof(Allo.Critters.CritterDirector);
        var root = new GameObject("Legacy hatch transition regression");
        Allo.Critters.CritterDirector director = null;
        GameObject worldRoot = null, cameraRoot = null;
        AppWorld world = null;
        Action<AppState> applyWorld = null;
        try
        {
            typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, null);
            bridgeType.GetProperty("LastSettings").SetValue(null, null);
            bridgeType.GetProperty("LastEgg").SetValue(null, new Allo.Bridge.EggState { state = "hatched", eggId = "legacy" });
            events.SetValue(null, null);
            director = root.AddComponent<Allo.Critters.CritterDirector>();
            directorType.GetMethod("OnDisable", flags).Invoke(director, null);
            directorType.GetField("_graph", flags).SetValue(director, new Allo.Critters.WalkGraph(new System.Collections.Generic.List<Allo.Critters.WalkSurface>()));
            var tracker = (Allo.Critters.EggTracker)directorType.GetField("_eggTracker", flags).GetValue(director);
            tracker.Apply(new Allo.Bridge.EggState { state = "incubating", eggId = "legacy" });
            tracker.Apply(new Allo.Bridge.EggState { state = "hatched", eggId = "legacy" });
            Assert.IsFalse(tracker.Present, "The legacy tracker drops Present before its hatch animation finishes.");
            var shell = new GameObject("Legacy egg still animating");
            shell.transform.SetParent(root.transform);
            directorType.GetField("_egg", flags).SetValue(director, shell.transform);
            directorType.GetField("_hatching", flags).SetValue(director, true);
            directorType.GetMethod("OnEnable", flags).Invoke(director, null);
            var bridge = root.AddComponent<Allo.Bridge.FlutterBridge>();
            if (firstView == "home")
            {
                if (Camera.main == null)
                {
                    cameraRoot = new GameObject("Legacy transition camera");
                    cameraRoot.tag = "MainCamera";
                    cameraRoot.AddComponent<Camera>();
                }
                worldRoot = new GameObject("Legacy transition app world");
                world = worldRoot.AddComponent<AppWorld>();
                applyWorld = state =>
                {
                    world.Apply(state);
                    // AppSession skips runtime installation in EditMode, so replay lifecycle explicitly.
                    directorType.GetMethod("OnDisable", flags).Invoke(director, null);
                    if (root.activeInHierarchy) directorType.GetMethod("OnEnable", flags).Invoke(director, null);
                };
                AppSession.Changed += applyWorld;
            }
            bridge.OnFlutterMessage("{\"v\":1,\"type\":\"app\",\"revision\":1,\"view\":\"" + firstView + "\"}");
            if (firstView == "home")
            {
                Assert.IsFalse(root.activeSelf, "The app hides the legacy director before bridge egg clearing.");
                bridge.OnFlutterMessage("{\"v\":1,\"type\":\"app\",\"revision\":2,\"view\":\"cabin\"}");
                Assert.IsTrue(root.activeSelf);
            }
            Assert.IsFalse(director.Hatching);
            Assert.IsTrue(shell == null, "The legacy shell must be removed, leaving the app egg as the only presentation.");
        }
        finally
        {
            if (applyWorld != null) AppSession.Changed -= applyWorld;
            if (world != null) world.SetView("cabin");
            if (director != null) directorType.GetMethod("OnDisable", flags).Invoke(director, null);
            UnityEngine.Object.DestroyImmediate(worldRoot);
            UnityEngine.Object.DestroyImmediate(cameraRoot);
            UnityEngine.Object.DestroyImmediate(root);
            typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, previousApp);
            bridgeType.GetProperty("LastSettings").SetValue(null, previousSettings);
            bridgeType.GetProperty("LastEgg").SetValue(null, previousEgg);
            events.SetValue(null, previousEvents);
        }
    }

    [Test]
    public void InvalidBridgePayloadIsNotWrittenToTheLog()
    {
        var root = new GameObject("Private bridge payload regression");
        try
        {
            UnityEngine.TestTools.LogAssert.Expect(LogType.Warning, "[FlutterBridge] 읽지 못한 메시지");
            root.AddComponent<Allo.Bridge.FlutterBridge>().OnFlutterMessage("pair-code-and-private-speech");
        }
        finally { UnityEngine.Object.DestroyImmediate(root); }
    }

}
