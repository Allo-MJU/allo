using Allo.App;
using Allo.Critters;
using System.Reflection;
using NUnit.Framework;
using UnityEngine;

public class CabinInteractionTests
{
    const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    [TestCase("snack", true)] [TestCase("water", true)] [TestCase("ball", true)] [TestCase("plush", true)]
    [TestCase("pet", false)] [TestCase("cushion", false)] [TestCase("blanket", false)] [TestCase("feedFood", false)]
    public void OnlyFourItemsCanBeHeld(string id, bool expected) => Assert.AreEqual(expected, CabinInteraction.IsThrowable(id));

    [Test]
    public void SwipeAllowsUpwardAndSidewaysThrowsButRejectsTapsAndPullingBack()
    {
        Assert.IsFalse(CabinInteraction.IsThrowGesture(Vector2.zero, new Vector2(0, 20), .2f, 720));
        Assert.IsTrue(CabinInteraction.IsThrowGesture(Vector2.zero, new Vector2(220, 30), .2f, 720));
        Assert.IsTrue(CabinInteraction.IsThrowGesture(Vector2.zero, new Vector2(160, 0), .2f, 720));
        Assert.IsTrue(CabinInteraction.IsThrowGesture(Vector2.zero, new Vector2(-160, 0), .2f, 720));
        Assert.IsTrue(CabinInteraction.IsThrowGesture(Vector2.zero, new Vector2(-120, 140), .2f, 720));
        Assert.IsTrue(CabinInteraction.IsThrowGesture(Vector2.zero, new Vector2(120, 140), .2f, 720));
        Assert.IsFalse(CabinInteraction.IsThrowGesture(Vector2.zero, new Vector2(0, -160), .2f, 720));
        Assert.IsFalse(CabinInteraction.IsThrowGesture(Vector2.zero, new Vector2(30, -160), .2f, 720));
        Assert.IsTrue(CabinInteraction.IsThrowGesture(Vector2.zero, new Vector2(40, 160), .35f, 720));
    }

    [Test]
    public void RubAndDeliberateMoveDoNotBecomeTheSameGesture()
    {
        Assert.AreEqual("pet", CabinInteraction.BuddyGesture(240, 20, .7f, 720));
        Assert.AreEqual("", CabinInteraction.BuddyGesture(210, 180, .8f, 720), "a long hold no longer starts moving");
        Assert.AreEqual("", CabinInteraction.BuddyGesture(210, 180, .15f, 720));
        Assert.AreEqual("", CabinInteraction.BuddyGesture(10, 8, .2f, 720));
    }

    [Test]
    public void DoubleTapNeedsBothATimeAndSpatialMatch()
    {
        Assert.IsTrue(CabinInteraction.IsDoubleTap(Vector2.zero, new Vector2(10, 10), .2f, 720));
        Assert.IsFalse(CabinInteraction.IsDoubleTap(Vector2.zero, new Vector2(10, 10), .4f, 720));
        Assert.IsFalse(CabinInteraction.IsDoubleTap(Vector2.zero, new Vector2(100, 100), .2f, 720));
        Assert.IsFalse(CabinInteraction.IsDoubleTap(Vector2.zero, Vector2.zero, -.1f, 720));
    }

    [Test]
    public void IntentPreservesExactOwnedTargetAndRejectsStaleSessions()
    {
        var state = State();
        var intent = CabinInteraction.CareIntent(state, "owned-1", "ball");
        Assert.AreEqual("owned-1", intent.creatureId);
        Assert.AreEqual("commonCare", intent.action);
        Assert.IsNull(CabinInteraction.CareIntent(state, "other-owned", "ball"));
        state.sessionEnded = true;
        Assert.IsNull(CabinInteraction.CareIntent(state, "owned-1", "ball"));
        state.sessionEnded = false; state.connected = false;
        Assert.IsNull(CabinInteraction.CareIntent(state, "owned-1", "ball"));
    }

    [Test]
    public void EggOnlyItemsDoNotCreatePetRewardsAndNeedCurrentEgg()
    {
        var state = State(); state.learning.creatureId = ""; state.learning.speciesId = "";
        var intent = CabinInteraction.CareIntent(state, "", "water");
        Assert.AreEqual("egg-1", intent.eggId);
        Assert.IsNull(CabinInteraction.CareIntent(state, "", "pet"));
        state.egg.active = false;
        Assert.IsNull(CabinInteraction.CareIntent(state, "", "water"));
    }

    [Test]
    public void SelectionCancelsOnTargetChangeButSurvivesOrdinarySnapshots()
    {
        var host = new GameObject("Cabin interaction test");
        try
        {
            var input = CreateInput(host);
            input.Apply(State());
            CabinInteraction.SelectItem("ball");
            Assert.AreEqual("ball", CabinInteraction.SelectedItem);
            input.Apply(State());
            Assert.AreEqual("ball", CabinInteraction.SelectedItem);
            var busy = State(); busy.busy = true; input.Apply(busy);
            Assert.AreEqual("ball", CabinInteraction.SelectedItem, "temporary host work does not discard held input");
            Assert.IsTrue(CabinInteraction.CanKeepInteraction(busy));
            Assert.IsFalse(CabinInteraction.CanUse(busy), "care submission still waits for ready state");
            var replaced = State(); replaced.learning.creatureId = "owned-2";
            input.Apply(replaced);
            Assert.IsEmpty(CabinInteraction.SelectedItem);
            input.Apply(State()); CabinInteraction.SelectItem("cushion");
            Assert.IsEmpty(CabinInteraction.SelectedItem);
        }
        finally { DestroyInput(host); }
        Assert.IsEmpty(CabinInteraction.SelectedItem);
    }

    [Test]
    public void ThrowArcStartsAndEndsAtTheChosenPoints()
    {
        var from = Vector3.zero; var to = new Vector3(2, 0, 1);
        Assert.AreEqual(from, CabinInteraction.ArcPoint(from, to, 0, .5f));
        Assert.That(Vector3.Distance(to, CabinInteraction.ArcPoint(from, to, 1, .5f)), Is.LessThan(.00001f));
        Assert.Greater(CabinInteraction.ArcPoint(from, to, .5f, .5f).y, .4f);
    }

    [Test]
    public void ReleaseVelocityAddsBoundedFollowThroughToTheAim()
    {
        var released = new Vector2(500, 350);
        Assert.AreEqual(released, CabinInteraction.ThrowAim(released, Vector2.zero, 1600, 720));
        var faster = CabinInteraction.ThrowAim(released, new Vector2(1000, 2000), 1600, 720);
        Assert.Greater(faster.x, released.x); Assert.Greater(faster.y, released.y);
        Assert.LessOrEqual(Vector2.Distance(released, faster), 720 * .22f + .001f);
        Assert.AreEqual(new Vector2(1600, 720), CabinInteraction.ThrowAim(new Vector2(1599, 719), new Vector2(1000, 1000), 1600, 720));
        var left = CabinInteraction.ThrowAim(new Vector2(400, 200), new Vector2(-1000, 0), 1600, 720);
        var right = CabinInteraction.ThrowAim(new Vector2(1200, 200), new Vector2(1000, 0), 1600, 720);
        Assert.Less(left.x, 400); Assert.Greater(right.x, 1200);
        Assert.AreEqual(200, left.y); Assert.AreEqual(200, right.y, "sideways throws retain the release direction instead of aiming at screen center");
    }

    [Test]
    public void SelectingAnItemDoesNotSendCareBeforeAThrow()
    {
        var host = new GameObject("Selection intent boundary");
        var sent = 0;
        Application.LogCallback observe = (message, trace, type) => { if (message.Contains("[AndroidHost]")) sent++; };
        Application.logMessageReceived += observe;
        try
        {
            var input = CreateInput(host); input.Apply(State());
            CabinInteraction.SelectItem("snack");
            Assert.AreEqual("snack", CabinInteraction.SelectedItem);
            CabinInteraction.SelectItem("water");
            Assert.AreEqual("water", CabinInteraction.SelectedItem);
            Assert.AreEqual(0, sent, "item selection is presentation only");
        }
        finally { Application.logMessageReceived -= observe; DestroyInput(host); }
    }

    [Test]
    public void NavigationReleasesCameraOwnershipBeforeTheWorldSuspendsIt()
    {
        var host = new GameObject("Pointer owner");
        var camera = new GameObject("Pointer camera", typeof(Camera));
        try
        {
            var input = CreateInput(host); input.Apply(State());
            var rig = camera.AddComponent<Allo.CameraRig.CameraRig>();
            var tap = camera.AddComponent<Allo.TapInput>();
            rig.enabled = tap.enabled = false;
            Set(input, "_capturing", true); Set(input, "_rig", rig); Set(input, "_tap", tap);
            Set(input, "_rigEnabled", true); Set(input, "_tapEnabled", true);
            Assert.IsTrue(CabinInteraction.IsCapturing);
            Assert.IsFalse(CabinEgg.CanInteract(State(), "cabin", "egg-1"), "egg cannot claim the companion pointer");
            var home = State(); home.view = "home";
            input.BeforeWorldChange(home);
            Assert.IsTrue(rig.enabled); Assert.IsTrue(tap.enabled);
            Assert.IsFalse((bool)typeof(CabinInteraction).GetField("_capturing", Private).GetValue(input));
            Assert.IsTrue(CabinInteraction.IsCapturing, "the release frame still blocks legacy input");
            // AppWorld is now able to cache enabled=true before suspending the camera for home.
            rig.enabled = tap.enabled = false;
            input.Apply(home);
            Assert.IsFalse(rig.enabled); Assert.IsFalse(tap.enabled, "a second cancellation must not undo world suspension");
        }
        finally { DestroyInput(host); Object.DestroyImmediate(camera); }
    }

    [Test]
    public void PendingCareKeepsItsLandingUntilTheAcceptedSnapshot()
    {
        var host = new GameObject("Care receipt correlation");
        try
        {
            var input = CreateInput(host); input.Apply(State());
            Set(input, "_pendingCare", true); Set(input, "_pendingSequence", 0L);
            CabinInteraction.SelectItem("ball");
            Assert.IsEmpty(CabinInteraction.SelectedItem, "a second throw must wait for the first receipt");
            input.Apply(State());
            Assert.IsTrue((bool)typeof(CabinInteraction).GetField("_pendingCare", Private).GetValue(input));
            var accepted = State(); accepted.learning.careSequence = 1;
            input.Apply(accepted);
            CabinInteraction.SelectItem("ball");
            Assert.AreEqual("ball", CabinInteraction.SelectedItem);
        }
        finally { DestroyInput(host); }
    }

    [Test]
    public void ClaimedAndReleaseFramesClearCameraInertiaWithoutTurning()
    {
        var host = new GameObject("Gesture camera guard");
        var camera = new GameObject("Guarded camera", typeof(Camera));
        try
        {
            var input = CreateInput(host); input.Apply(State());
            var rig = camera.AddComponent<Allo.CameraRig.CameraRig>();
            var rigType = typeof(Allo.CameraRig.CameraRig);
            var velocity = rigType.GetField("_velocity", Private);
            var update = rigType.GetMethod("Update", Private);
            var before = camera.transform.rotation;
            Set(input, "_capturing", true);
            velocity.SetValue(rig, new Vector2(80, 50));
            update.Invoke(rig, null);
            Assert.AreEqual(Vector2.zero, velocity.GetValue(rig));
            Assert.AreEqual(before, camera.transform.rotation);
            Set(input, "_capturing", false); Set(input, "_releasedFrame", Time.frameCount);
            velocity.SetValue(rig, new Vector2(80, 50));
            update.Invoke(rig, null);
            Assert.AreEqual(Vector2.zero, velocity.GetValue(rig), "restoring the camera on pointer-up must not resume old momentum");
            Assert.AreEqual(before, camera.transform.rotation);
        }
        finally { DestroyInput(host); Object.DestroyImmediate(camera); }
    }

    [Test]
    public void MoveModeAndDeferredSingleTapAreCanceledByIdentityOrNavigation()
    {
        var host = new GameObject("Move mode lifetime");
        var pending = new GameObject("Deferred tap actor");
        try
        {
            var input = CreateInput(host); input.Apply(State());
            Set(input, "_moveArmed", true); Set(input, "_pendingTapActor", pending.AddComponent<CritterView>());
            input.Apply(State());
            Assert.IsTrue(CabinInteraction.MoveArmed);
            Assert.NotNull(typeof(CabinInteraction).GetField("_pendingTapActor", Private).GetValue(input));
            var home = State(); home.view = "home"; input.BeforeWorldChange(home);
            Assert.IsFalse(CabinInteraction.MoveArmed);
            Assert.IsNull(typeof(CabinInteraction).GetField("_pendingTapActor", Private).GetValue(input));
            input.Apply(State()); Set(input, "_moveArmed", true);
            var other = State(); other.learning.creatureId = "owned-2"; input.Apply(other);
            Assert.IsFalse(CabinInteraction.MoveArmed);
        }
        finally { DestroyInput(host); Object.DestroyImmediate(pending); }
    }

    [Test]
    public void FreePlacementClampsToAValidSurfaceWithoutSendingCare()
    {
        var root = new GameObject("Free placement actor");
        var mat = new Material(Shader.Find("Allo/Toon"));
        var sent = 0;
        Application.LogCallback observe = (message, trace, type) => { if (message.Contains("[AndroidHost]")) sent++; };
        Application.logMessageReceived += observe;
        try
        {
            var director = root.AddComponent<CritterDirector>(); director.critterMaterial = mat; director.shadowMaterial = mat;
            var graph = new WalkGraph(new[] { new WalkSurface("bench", new Vector3(0, 1, 0), new Vector2(1, 1)) });
            var actor = director.EditorSpawn(graph, "test_free_placement", "missing-test-art", "bench");
            Assert.IsTrue(director.PlaceCabinCompanion(actor.Id, new Vector3(20, 20, 20), 0));
            Assert.AreEqual(WalkGraph.Clamp(new Vector3(20, 20, 20), graph.Surfaces[0]), actor.Brain.Position);
            Assert.AreEqual(0, sent);
            Assert.IsFalse(director.PlaceCabinCompanion("wrong-species", Vector3.zero, 0));
            Assert.IsFalse(director.PlaceCabinCompanion(actor.Id, Vector3.zero, 3));
        }
        finally { Application.logMessageReceived -= observe; Object.DestroyImmediate(root); Object.DestroyImmediate(mat); }
    }

    [Test]
    public void FirstTapDefersConversationAndSecondTapArmsMovingWithoutAnIntent()
    {
        var root = new GameObject("Double tap actor");
        var host = new GameObject("Double tap input");
        var camera = new GameObject("Double tap camera", typeof(Camera));
        var mat = new Material(Shader.Find("Allo/Toon"));
        var sent = 0;
        Application.LogCallback observe = (message, trace, type) => { if (message.Contains("[AndroidHost]")) sent++; };
        Application.logMessageReceived += observe;
        try
        {
            var director = root.AddComponent<CritterDirector>(); director.critterMaterial = mat; director.shadowMaterial = mat;
            var graph = new WalkGraph(new[] { new WalkSurface("bench", Vector3.zero, new Vector2(1, 1)) });
            var actor = director.EditorSpawn(graph, "test_double_tap", "missing-test-art", "bench");
            actor.Brain.Place(Vector3.zero, 0);
            var cam = camera.GetComponent<Camera>(); camera.transform.position = new Vector3(0, .15f, -2); camera.transform.LookAt(Vector3.up * .15f);
            var input = CreateInput(host); var state = State(); state.learning.speciesId = actor.Id; state.learning.creatures[0].speciesId = actor.Id;
            input.Apply(state); Set(input, "_camera", cam); Set(input, "_director", director);
            Physics.SyncTransforms();
            var point = (Vector2)cam.WorldToScreenPoint(Vector3.up * .15f);
            typeof(CabinInteraction).GetMethod("Begin", Private).Invoke(input, new object[] { point, -1 });
            typeof(CabinInteraction).GetMethod("End", Private).Invoke(input, new object[] { point });
            Assert.AreSame(actor, typeof(CabinInteraction).GetField("_pendingTapActor", Private).GetValue(input));
            Assert.IsFalse(CabinInteraction.MoveArmed); Assert.AreEqual(0, sent, "first tap waits for the double-tap window");
            typeof(CabinInteraction).GetMethod("Begin", Private).Invoke(input, new object[] { point, -1 });
            typeof(CabinInteraction).GetMethod("End", Private).Invoke(input, new object[] { point });
            Assert.IsTrue(CabinInteraction.MoveArmed, "releasing the second tap leaves moving armed for the next drag");
            Assert.IsNull(typeof(CabinInteraction).GetField("_pendingTapActor", Private).GetValue(input));
            Assert.AreEqual(0, sent, "double tap never starts AI conversation or grants care");
        }
        finally { Application.logMessageReceived -= observe; DestroyInput(host); Object.DestroyImmediate(root); Object.DestroyImmediate(camera); Object.DestroyImmediate(mat); }
    }

    static CabinInteraction CreateInput(GameObject host)
    {
        var input = host.AddComponent<CabinInteraction>();
        typeof(CabinInteraction).GetMethod("OnEnable", Private).Invoke(input, null);
        return input;
    }

    static void DestroyInput(GameObject host)
    {
        var input = host.GetComponent<CabinInteraction>();
        if (input != null) typeof(CabinInteraction).GetMethod("OnDisable", Private).Invoke(input, null);
        Object.DestroyImmediate(host);
    }

    static void Set(CabinInteraction input, string field, object value) => typeof(CabinInteraction).GetField(field, Private).SetValue(input, value);

    static AppState State() => new AppState
    {
        ready = true, connected = true, view = "cabin",
        egg = new EggState { id = "egg-1", active = true },
        learning = new LearningState { active = true, creatureId = "owned-1", speciesId = "road_sprout",
            creatures = new[] { new LearningCreatureState { creatureId = "owned-1", speciesId = "road_sprout" } } }
    };
}
