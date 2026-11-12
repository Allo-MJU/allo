using Allo.Critters;
using NUnit.Framework;

public class DialogueTests
{
    const string Json = @"{""items"":[
        {""key"":""name|road_sprout|*"",""lines"":[""길싹이""]},
        {""key"":""hatch|road_sprout|*"",""lines"":[""안녕! 나는 {name}. 세상이 다 처음이다!""]},
        {""key"":""scene|@normal|coast"",""lines"":[""바다다!"",""파도가 하얗다!""]},
        {""key"":""scene|*|*"",""lines"":[""창밖 좀 봐.""]},
        {""key"":""ball|*|*"",""lines"":[""받았다! 공은 ball.""]}
    ]}";

    [SetUp] public void Load() => Dialogue.Parse(Json);
    [TearDown] public void Clear() => Dialogue.Clear();

    [Test]
    public void SpeciesLineBeatsAttributeAndStar()
    {
        var rng = new System.Random(1);
        Assert.AreEqual("안녕! 나는 길싹이. 세상이 다 처음이다!", Dialogue.Pick("hatch", "road_sprout", "normal", "*", rng));
    }

    [Test]
    public void FallsBackToAttributeThenStarAndContextThenStar()
    {
        var rng = new System.Random(2);
        var coast = Dialogue.Pick("scene", "bridge_hopper", "normal", "coast", rng);
        Assert.IsTrue(coast == "바다다!" || coast == "파도가 하얗다!", coast);
        Assert.AreEqual("창밖 좀 봐.", Dialogue.Pick("scene", "bridge_hopper", "normal", "city", rng), "문맥이 없으면 *");
        Assert.AreEqual("받았다! 공은 ball.", Dialogue.Pick("ball", "sea_mist", "water", "night", rng), "종·속성이 없으면 *");
        Assert.IsNull(Dialogue.Pick("nothing", "sea_mist", "water", "night", rng));
    }

    [Test]
    public void AvoidsRepeatingTheSameLineTwice()
    {
        var rng = new System.Random(3);
        var a = Dialogue.Pick("scene", "x", "normal", "coast", rng);
        for (var i = 0; i < 10; i++)
        {
            var b = Dialogue.Pick("scene", "x", "normal", "coast", rng);
            Assert.AreNotEqual(a, b, $"i={i}");
            a = b;
        }
    }

    [Test]
    public void ParticlesFollowBatchim()
    {
        Assert.AreEqual("길싹이가 왔다", Dialogue.Fill("{name}{name:이/가} 왔다", "길싹이"));
        Assert.AreEqual("폭풍등이 왔다", Dialogue.Fill("{name}{name:이/가} 왔다", "폭풍등"));
        Assert.AreEqual("바다안개는", Dialogue.Fill("{name}{name:은/는}", "바다안개"));
        Assert.AreEqual("별부엉이야", Dialogue.Fill("{name}{name:아/야}", "별부엉이"));
        Assert.IsFalse(Dialogue.HasBatchim("sea"));
    }

    [Test]
    public void NameOfUsesBankOrId()
    {
        Assert.AreEqual("길싹이", Dialogue.NameOf("road_sprout"));
        Assert.AreEqual("sea_mist", Dialogue.NameOf("sea_mist"));
    }
}
