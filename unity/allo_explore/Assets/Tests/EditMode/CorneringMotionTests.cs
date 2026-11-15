using Allo.Bridge;
using Allo.World;
using NUnit.Framework;
using UnityEditor.SceneManagement;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

public class CorneringMotionTests
{
    const long Epoch = 1_700_000_000_000L;
    static CorneringState Sample(float bend, long stamp = Epoch, int version = 1) =>
        new() { version = version, bend = bend, receivedAtMs = stamp };

    [Test]
    public void FreshNeutralTakesPriorityAndReversalEasesAcrossFrames()
    {
        var motion = new CorneringMotion();
        motion.Receive(Sample(1), Epoch, 0);
        Assert.IsTrue(motion.Active(0, true));
        var initial = motion.Step(true, .016f);
        Assert.That(initial, Is.InRange(.00001f, .99f));
        motion.Receive(Sample(-1, Epoch + 1000), Epoch + 1000, 1);
        Assert.Less(motion.Step(true, .25f), 0);
        motion.Receive(Sample(0, Epoch + 2000), Epoch + 2000, 2);
        Assert.IsTrue(motion.Active(2, true));
        Assert.That(motion.Step(true, .25f), Is.GreaterThan(-.5f));
    }

    [Test]
    public void RepeatedOrOlderMessagesCannotRefreshOrReverseAnExpiredSample()
    {
        var motion = new CorneringMotion();
        motion.Receive(Sample(1), Epoch, 10);
        motion.Receive(Sample(-1, Epoch - 100), Epoch + 2000, 12);
        motion.Receive(Sample(-1), Epoch + 3200, 13.2);
        Assert.Greater(motion.Step(true, .5f), 0);
        Assert.IsFalse(motion.Active(13.51, true));
        var fading = motion.Step(false, .016f);
        Assert.That(fading, Is.InRange(.01f, .99f));
        Assert.Less(motion.Step(false, 2f), .001f);
    }

    [TestCase(-5001, 1, 0f)]
    [TestCase(1001, 1, 0f)]
    [TestCase(0, 2, 0f)]
    [TestCase(0, 1, 1.1f)]
    [TestCase(0, 1, float.NaN)]
    [TestCase(0, 1, float.PositiveInfinity)]
    public void InvalidInputReleasesNavigation(int offsetMs, int version, float bend)
    {
        var motion = new CorneringMotion();
        motion.Receive(Sample(bend, Epoch + offsetMs, version), Epoch, 0);
        Assert.IsFalse(motion.Active(0, true));
    }

    [Test]
    public void StoppingOrClearingDropsTheSampleUntilANewerReadingArrives()
    {
        var motion = new CorneringMotion();
        motion.Receive(Sample(-1), Epoch, 0);
        Assert.IsTrue(motion.Active(0, true));
        Assert.IsFalse(motion.Active(.1, false));
        motion.Receive(Sample(-1), Epoch + 500, .5);
        Assert.IsFalse(motion.Active(.5, true));
        motion.Receive(Sample(1, Epoch + 1000), Epoch + 1000, 1);
        Assert.IsTrue(motion.Active(1, true));
        motion.Receive(null, Epoch + 1000, 1.1);
        Assert.IsFalse(motion.Active(1.1, true));
    }

    static WorldDirector MovingCabin(Scene scene)
    {
        WorldDirector world = null;
        foreach (var root in scene.GetRootGameObjects())
            if ((world = root.GetComponentInChildren<WorldDirector>(true)) != null) break;
        Assert.IsNotNull(world);
        // In EditMode the scene references authoring assets. Lighting is irrelevant to this route test.
        world.sky = world.cabinGlass = null;
        world.propGlows = System.Array.Empty<UnityEngine.Material>();
        world.Apply(new SceneState { kind = "road", moving = true, speedKph = 60 });
        return world;
    }

    // The preview scene has no player loop. Advance the same frame callback as the cabin runtime.
    static void Frame(WorldDirector world) => typeof(WorldDirector)
        .GetMethod("Update", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
        .Invoke(world, null);

    [Test]
    public void CabinUsesSensorInsteadOfUpcomingNavigationAndRestoresItOnClear()
    {
        var scene = EditorSceneManager.OpenPreviewScene("Assets/Scenes/Explore.unity");
        try
        {
            var world = MovingCabin(scene);
            var route = new RouteState { turns = new[] { new TurnInfo { type = "right", inM = 140 } } };
            world.OnRoute(route);
            Assert.IsFalse(float.IsInfinity(world.NextTurnStart));
            route.cornering = Sample(0, System.DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            world.OnRoute(route);
            Assert.IsTrue(float.IsInfinity(world.NextTurnStart), "A fresh straight steering signal owns the road");
            route.cornering = null;
            world.OnRoute(route);
            Assert.IsFalse(float.IsInfinity(world.NextTurnStart), "Legacy navigation resumes on clear");
            route.cornering = Sample(-1, System.DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() + 1);
            world.OnRoute(route);
            Assert.IsTrue(float.IsInfinity(world.NextTurnStart));
            world.Apply(new SceneState { kind = "road", moving = false, speedKph = 0 });
            world.OnRoute(route);
            Assert.IsFalse(float.IsInfinity(world.NextTurnStart), "Turning the wheel at a stop cannot own the road");
        }
        finally { EditorSceneManager.ClosePreviewScene(scene); }
    }

    [UnityTest]
    public System.Collections.IEnumerator ReplayedNavigationCannotResurrectPassedTurnWhenSteeringExpires()
    {
        var scene = EditorSceneManager.OpenPreviewScene("Assets/Scenes/Explore.unity");
        try
        {
            var world = MovingCabin(scene);
            var stamp = System.DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            RouteState Packet(float distance) => new() {
                turns = new[] { new TurnInfo { type = "right", inM = distance } },
                heading = 30,
                cornering = Sample(0, stamp)
            };
            world.OnRoute(Packet(45));
            var expires = UnityEngine.Time.realtimeSinceStartupAsDouble + 3.51;
            world.EditorStep(50);
            world.OnRoute(Packet(45)); // UI sent a newly decoded copy after the 45 m turn was passed.
            world.EditorStep(8);
            while (UnityEngine.Time.realtimeSinceStartupAsDouble < expires) yield return null;
            Frame(world);
            Assert.IsTrue(float.IsPositiveInfinity(world.NextTurnStart),
                "Navigation fallback must discard the turn that was already passed");

            world.OnRoute(Packet(140));
            Assert.That(world.NextTurnStart - world.Travelled, Is.InRange(110f, 140f),
                "Changed navigation distance is measured from the current position");
        }
        finally { EditorSceneManager.ClosePreviewScene(scene); }
    }

    [Test]
    public void EnablingReducedMotionDuringSensorTurnRestoresNavigation()
    {
        var scene = EditorSceneManager.OpenPreviewScene("Assets/Scenes/Explore.unity");
        var previous = FlutterBridge.LastSettings;
        try
        {
            FlutterBridge.Inject(new SettingsState { reducedMotion = false });
            var world = MovingCabin(scene);
            var route = new RouteState {
                turns = new[] { new TurnInfo { type = "right", inM = 140 } },
                cornering = Sample(-1, System.DateTimeOffset.UtcNow.ToUnixTimeMilliseconds())
            };
            world.OnRoute(route);
            Assert.IsTrue(float.IsInfinity(world.NextTurnStart));
            FlutterBridge.Inject(new SettingsState { reducedMotion = true });
            Frame(world);
            Assert.IsFalse(float.IsInfinity(world.NextTurnStart), "Reduced motion releases sensor authority");
            world.OnRoute(route);
            Assert.IsFalse(float.IsInfinity(world.NextTurnStart));
        }
        finally
        {
            if (previous != null) FlutterBridge.Inject(previous);
            else typeof(FlutterBridge).GetProperty(nameof(FlutterBridge.LastSettings)).SetValue(null, null);
            EditorSceneManager.ClosePreviewScene(scene);
        }
    }
}
