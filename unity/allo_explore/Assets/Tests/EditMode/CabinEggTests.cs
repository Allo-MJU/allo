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
}
