using System.Collections.Generic;
using Allo.App;
using Allo.Critters;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.UI;

public class CabinCareVisualTests
{
    [TestCase("snack", "Toy_Apple")]
    [TestCase("water", "Toy_Cup")]
    [TestCase("ball", "Toy_Ball")]
    [TestCase("pet", null)]
    [TestCase("plush", "Toy_Plush")]
    [TestCase("cushion", "Toy_Cushion")]
    [TestCase("blanket", "Toy_Blanket")]
    public void AcceptedEggCareShowsNonverbalVisualAndCleansUpOnLeaving(string action, string toyName)
    {
        var hidden = new List<Transform>();
        foreach (var t in Object.FindObjectsByType<Transform>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            if (t.name == "Cabin") { hidden.Add(t); t.name = "Other cabin during care test"; }
        var cabin = new GameObject("Cabin");
        var host = new GameObject("Egg care visual test");
        try
        {
            var floor = GameObject.CreatePrimitive(PrimitiveType.Cube);
            floor.name = CabinEgg.ZoneSurfaceName(0); floor.transform.SetParent(cabin.transform, false);
            var egg = host.AddComponent<CabinEgg>();
            egg.SetView("cabin"); egg.Apply(State(0, ""));
            var body = host.transform.Find("Cabin egg visuals/Cabin egg");
            var originalColor = body.GetComponent<Renderer>().sharedMaterial.color;
            var accepted = State(1, action); egg.Apply(accepted);
            Assert.AreNotEqual(originalColor, body.GetComponent<Renderer>().sharedMaterial.color, "a static highlight also works with reduced motion");
            if (toyName != null) Assert.IsNotNull(host.transform.Find("Cabin egg visuals/" + toyName), action);
            Assert.IsEmpty(host.GetComponentsInChildren<Text>(true), "egg reactions must not create dialogue");
            Assert.AreEqual(42, accepted.egg.score, "presentation never awards affinity");
            egg.SetView("home");
            if (toyName != null) Assert.IsNull(host.transform.Find("Cabin egg visuals/" + toyName));
            Assert.AreEqual(originalColor, body.GetComponent<Renderer>().sharedMaterial.color);
        }
        finally
        {
            Object.DestroyImmediate(host); Object.DestroyImmediate(cabin);
            foreach (var t in hidden) if (t != null) t.name = "Cabin";
        }
    }

    [Test]
    public void CompanionCareDoesNotFallBackToAnUnselectedActor()
    {
        var root = new GameObject("Care target guard");
        try
        {
            var director = root.AddComponent<CritterDirector>();
            Assert.IsFalse(director.PlayCommonCare("missing-species", "snack"));
            Assert.IsFalse(director.PlayCommonCare("", "pet"));
            Assert.IsFalse(director.PlayCommonCare("road_sprout", "feedFood"));
        }
        finally { Object.DestroyImmediate(root); }
    }

    static AppState State(long sequence, string action) => new AppState
    {
        ready = true, view = "cabin", reducedMotion = true,
        egg = new EggState { id = "current", active = true, score = 42 },
        learning = new LearningState { active = true, careSequence = sequence, careActionId = action }
    };
}
