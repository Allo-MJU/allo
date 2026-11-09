using Allo.Bridge;
using NUnit.Framework;

public class MessageParserTests
{
    [Test]
    public void ParsesScene()
    {
        Assert.IsTrue(MessageParser.TryParse(
            "{\"v\":1,\"type\":\"scene\",\"kind\":\"coast\",\"night\":false,\"highway\":false,\"rain\":2,\"speedKph\":62.0,\"moving\":true}",
            out var type, out var payload));
        Assert.AreEqual("scene", type);
        var s = (SceneState)payload;
        Assert.AreEqual("coast", s.kind);
        Assert.AreEqual(2, s.rain);
        Assert.AreEqual(62f, s.speedKph);
        Assert.IsTrue(s.moving);
    }

    [Test]
    public void ParsesCastWithNullCompanion()
    {
        Assert.IsTrue(MessageParser.TryParse(
            "{\"v\":1,\"type\":\"cast\",\"companion\":null,\"friends\":[{\"id\":\"b\",\"sprite\":\"species/b.png\",\"attribute\":\"water\"}]}",
            out var type, out var payload));
        var c = (CastState)payload;
        Assert.AreEqual("cast", type);
        Assert.IsTrue(c.companion == null || string.IsNullOrEmpty(c.companion.id));
        Assert.AreEqual(1, c.friends.Length);
        Assert.AreEqual("species/b.png", c.friends[0].sprite);
    }

    [Test]
    public void ParsesJoltAndSettings()
    {
        Assert.IsTrue(MessageParser.TryParse("{\"v\":1,\"type\":\"jolt\",\"kind\":\"brake\"}", out _, out var jolt));
        Assert.AreEqual("brake", ((JoltState)jolt).kind);
        Assert.IsTrue(MessageParser.TryParse("{\"v\":1,\"type\":\"settings\",\"gyro\":false,\"reducedMotion\":true}", out _, out var st));
        Assert.IsFalse(((SettingsState)st).gyro);
        Assert.IsTrue(((SettingsState)st).reducedMotion);
    }

    [Test]
    public void UnknownFieldsAndVersionAreTolerated()
    {
        Assert.IsTrue(MessageParser.TryParse("{\"v\":2,\"type\":\"scene\",\"kind\":\"city\",\"newThing\":[1,2]}", out _, out var p));
        Assert.AreEqual("city", ((SceneState)p).kind);
    }

    [Test]
    public void UnknownTypeIsIgnoredNotThrown()
    {
        Assert.IsTrue(MessageParser.TryParse("{\"v\":1,\"type\":\"dance\"}", out var type, out var p));
        Assert.AreEqual("dance", type);
        Assert.IsNull(p);
    }

    [Test]
    public void BrokenJsonReturnsFalse()
    {
        Assert.IsFalse(MessageParser.TryParse("{oops", out _, out _));
        Assert.IsFalse(MessageParser.TryParse("", out _, out _));
        Assert.IsFalse(MessageParser.TryParse(null, out _, out _));
    }
}
