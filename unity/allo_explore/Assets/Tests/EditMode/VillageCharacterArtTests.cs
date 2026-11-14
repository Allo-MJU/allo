using System;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class VillageCharacterArtTests
{
    GameObject _root;
    GameObject _fallback;
    Component _art;
    RawImage _image;
    Type _type;

    [SetUp]
    public void SetUp()
    {
        _type = typeof(AppUi).Assembly.GetType("Allo.App.VillageCharacterArt");
        Assert.NotNull(_type, "village artwork needs an authored-frame renderer");
        _root = new GameObject("Authored village artwork", typeof(RectTransform), typeof(RawImage), typeof(AspectRatioFitter));
        _image = _root.GetComponent<RawImage>();
        _fallback = new GameObject("Missing artwork");
        _art = _root.AddComponent(_type);
    }

    [TearDown]
    public void TearDown()
    {
        if (_root != null) Object.DestroyImmediate(_root);
        if (_fallback != null) Object.DestroyImmediate(_fallback);
    }

    [Test]
    public void SourceCellsCoverOddAtlasDimensionsTopRowFirstWithoutLosingPixels()
    {
        for (var frame = 0; frame < 8; frame++)
        {
            var rect = (Rect)_type.GetMethod("FrameUv").Invoke(null, new object[] { frame, 1774, 887 });
            var column = frame % 4; var row = frame / 4;
            var left = column * 1774 / 4; var right = (column + 1) * 1774 / 4;
            var top = row * 887 / 2; var bottom = (row + 1) * 887 / 2;
            Assert.That(rect.x, Is.EqualTo(left / 1774f).Within(.000001f));
            Assert.That(rect.y, Is.EqualTo(1 - bottom / 887f).Within(.000001f));
            Assert.That(rect.width, Is.EqualTo((right - left) / 1774f).Within(.000001f));
            Assert.That(rect.height, Is.EqualTo((bottom - top) / 887f).Within(.000001f));
        }
    }

    [Test]
    public void AuthoredFramesAdvanceEvery160MillisecondsAndUnchangedMotionKeepsPhase()
    {
        Bind("road_sprout"); Motion(true, true); Advance(.15f);
        Assert.AreEqual(0, Get<int>("FrameIndex"));
        Motion(true, true); Advance(.02f);
        Assert.AreEqual(1, Get<int>("FrameIndex"));
        Advance(.96f);
        Assert.AreEqual(7, Get<int>("FrameIndex"));
        Advance(.16f);
        Assert.AreEqual(0, Get<int>("FrameIndex"));
        Assert.IsTrue(Get<bool>("IsAnimated"));
        Assert.That(_root.GetComponent<AspectRatioFitter>().aspectRatio, Is.EqualTo(1).Within(.001f));
    }

    [TestCase("road_sprout", true)]
    [TestCase("puddle_pip", true)]
    [TestCase("lamp_moth", false)]
    [TestCase("storm_lantern", false)]
    [TestCase("highway_comet", false)]
    [TestCase("sea_mist", false)]
    public void FacingMirrorsOnlyArtworkRelativeToTheAuthoredSource(string species, bool sourceLeft)
    {
        Bind(species); Motion(true, sourceLeft);
        Assert.Greater(_image.uvRect.width, 0);
        Motion(true, !sourceLeft);
        Assert.Less(_image.uvRect.width, 0);
        Assert.AreEqual(!sourceLeft, Get<bool>("FacingLeft"));
        Assert.AreEqual(Vector3.one, _root.transform.localScale);
    }

    [Test]
    public void ReducedMotionUsesStaticIdleAndDoesNotAdvance()
    {
        Bind("road_sprout"); var idle = _image.texture;
        Motion(true, true); Advance(.4f);
        Assert.AreNotSame(idle, _image.texture);
        Motion(true, true, true); Advance(5);
        Assert.AreSame(idle, _image.texture);
        Assert.IsFalse(Get<bool>("IsAnimated"));
        Assert.AreEqual(0, Get<int>("FrameIndex"));
        Assert.IsFalse(_fallback.activeSelf);
    }

    [Test]
    public void UnsupportedSpeciesUsesOwnIdleOrFallbackAndNeverThePreviousAtlas()
    {
        Bind("road_sprout"); Motion(true, true); var atlas = _image.texture;
        Call("Bind", "unsupported", "species/lamp_moth.png", _fallback);
        Assert.AreNotSame(atlas, _image.texture);
        Assert.NotNull(_image.texture);
        Assert.IsFalse(Get<bool>("IsAnimated"));
        Assert.IsFalse(_fallback.activeSelf);
        Call("Bind", "unsupported", "species/does-not-exist.png", _fallback);
        Assert.IsTrue(_fallback.activeSelf);
        Assert.IsNull(_image.texture);
    }

    [Test]
    public void ActorsAndInspectorShareDecodedAtlasTexture()
    {
        Bind("road_sprout"); Motion(true, true); var atlas = _image.texture;
        var other = new GameObject("Inspector artwork", typeof(RectTransform), typeof(RawImage));
        try
        {
            var art = other.AddComponent(_type);
            _type.GetMethod("Bind").Invoke(art, new object[] { "road_sprout", "species/road_sprout.png", null });
            _type.GetMethod("SetMotion").Invoke(art, new object[] { true, true, false });
            Assert.AreSame(atlas, other.GetComponent<RawImage>().texture);
            Assert.IsFalse(((Texture2D)atlas).isReadable, "release decoded CPU pixels after uploading once");
        }
        finally { Object.DestroyImmediate(other); }
    }

    [Test]
    public void InactiveBindingDefersLoadingAndReturningKeepsLoadedArtAndFrame()
    {
        _root.SetActive(false);
        Bind("road_sprout"); Motion(true, true);
        Assert.IsNull(_image.texture, "inactive village markers must defer their load");
        Assert.IsTrue(_fallback.activeSelf);
        _root.SetActive(true);
        Lifecycle("OnEnable");
        Assert.NotNull(_image.texture);
        Assert.IsFalse(_fallback.activeSelf);
        Advance(.34f);
        var texture = _image.texture; var frame = Get<int>("FrameIndex");
        _root.SetActive(false); Lifecycle("OnDisable"); Advance(2);
        _root.SetActive(true); Lifecycle("OnEnable");
        Assert.AreSame(texture, _image.texture);
        Assert.AreEqual(frame, Get<int>("FrameIndex"));
    }

    void Bind(string species) => Call("Bind", species, "species/" + species + ".png", _fallback);
    void Motion(bool moving, bool left, bool reduced = false) => Call("SetMotion", moving, left, reduced);
    void Advance(float delta) => Call("Advance", delta);
    T Get<T>(string property) => (T)_type.GetProperty(property).GetValue(_art);
    void Lifecycle(string method) => _type.GetMethod(method, BindingFlags.Instance | BindingFlags.NonPublic).Invoke(_art, null);
    void Call(string method, params object[] args) => _type.GetMethod(method).Invoke(_art, args);
}
