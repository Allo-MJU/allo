using Allo.Bridge;
using Allo.Critters;
using NUnit.Framework;

public class CastDiffTests
{
    static CastMember M(string id) => new CastMember { id = id, sprite = $"species/{id}.png", attribute = "water" };

    [Test]
    public void AddsNewRemovesGoneKeepsSame()
    {
        var current = new[] { "a", "b" };
        var cast = new CastState { companion = M("a"), friends = new[] { M("c") } };
        var (add, remove) = CastDiff.Compute(current, cast);
        CollectionAssert.AreEquivalent(new[] { "c" }, add);
        CollectionAssert.AreEquivalent(new[] { "b" }, remove);
    }

    [Test]
    public void EmptyCastRemovesAll()
    {
        var (add, remove) = CastDiff.Compute(new[] { "a" }, new CastState { friends = new CastMember[0] });
        Assert.IsEmpty(add);
        CollectionAssert.AreEquivalent(new[] { "a" }, remove);
    }

    [Test]
    public void DuplicateIdsAppearOnce()
    {
        var cast = new CastState { companion = M("a"), friends = new[] { M("a"), M("b") } };
        var (add, _) = CastDiff.Compute(new string[0], cast);
        CollectionAssert.AreEquivalent(new[] { "a", "b" }, add);
    }
}
