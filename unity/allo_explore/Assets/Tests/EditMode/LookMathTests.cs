using Allo.CameraRig;
using NUnit.Framework;
using UnityEngine;

public class LookMathTests
{
    [Test]
    public void YawWrapsAround()
    {
        var s = LookMath.Drag(new LookState { yaw = 350 }, new Vector2(20, 0));
        Assert.AreEqual(10f, s.yaw, 1e-3);
        s = LookMath.Drag(new LookState { yaw = 5 }, new Vector2(-10, 0));
        Assert.AreEqual(355f, s.yaw, 1e-3);
    }

    [Test]
    public void PitchIsClamped()
    {
        Assert.AreEqual(35f, LookMath.Drag(new LookState(), new Vector2(0, 90)).pitch);
        Assert.AreEqual(-35f, LookMath.Drag(new LookState(), new Vector2(0, -90)).pitch);
    }

    [Test]
    public void RailIsClamped()
    {
        Assert.AreEqual(1f, LookMath.Pinch(new LookState { rail = 0.9f }, 0.5f).rail);
        Assert.AreEqual(0f, LookMath.Pinch(new LookState { rail = 0.1f }, -0.5f).rail);
    }

    [Test]
    public void HoldingTheSameGyroPoseKeepsTheSameView()
    {
        var neutral = Quaternion.Euler(23, -49, 72);
        var turned = neutral * Quaternion.Euler(-12, 30, 0);
        var s = LookMath.GyroTarget(new LookState { rail = .6f }, neutral, turned);
        var held = LookMath.GyroTarget(s, neutral, turned);
        Assert.AreEqual(30f, held.yaw, .001f);
        Assert.AreEqual(12f, held.pitch, .001f);
        Assert.AreEqual(.6f, held.rail);
        var back = LookMath.GyroTarget(held, neutral, neutral);
        Assert.AreEqual(0f, Mathf.DeltaAngle(0, back.yaw), .001f);
        Assert.AreEqual(0f, back.pitch, .001f);
    }

    [TestCase(-90)]
    [TestCase(90)]
    public void TurningLeftAndLookingDownWorksFromEitherLandscapeNeutral(float roll)
    {
        var neutral = Quaternion.Euler(51, 29, roll);
        var moved = neutral * Quaternion.Euler(58, -33, 72);
        var look = LookMath.GyroTarget(default, neutral, moved);
        Assert.AreEqual(-33f, Mathf.DeltaAngle(0, look.yaw), .001f);
        Assert.AreEqual(-35f, look.pitch, .001f);
    }

    [Test]
    public void RollingWithoutTurningKeepsTheHorizonLevel()
    {
        var neutral = Quaternion.Euler(12, -51, 90);
        var look = LookMath.GyroTarget(default, neutral, neutral * Quaternion.Euler(0, 0, -85));
        Assert.AreEqual(0f, Mathf.DeltaAngle(0, look.yaw), .001f);
        Assert.AreEqual(0f, look.pitch, .001f);
    }

    [Test]
    public void SensorRotationUsesUnityHandednessAndRejectsInvalidSamples()
    {
        Assert.IsTrue(LookMath.TryAttitude(new Quaternion(0f, -.258819f, 0f, .965926f), out var attitude));
        var target = LookMath.GyroTarget(default, Quaternion.identity, attitude);
        Assert.AreEqual(30f, target.yaw, .001f);
        Assert.IsFalse(LookMath.TryAttitude(default, out _));
        Assert.IsFalse(LookMath.TryAttitude(new Quaternion(0f, float.NaN, 0f, 1f), out _));
        Assert.IsFalse(LookMath.TryAttitude(new Quaternion(float.PositiveInfinity, 0f, 0f, 1f), out _));
    }

    [Test]
    public void RailPositionLerpsBetweenAnchors()
    {
        var rear = new Vector3(0, 1, 0);
        var front = new Vector3(0, 1.1f, -1);
        Assert.AreEqual(rear, LookMath.RailPosition(0, rear, front));
        Assert.AreEqual(front, LookMath.RailPosition(1, rear, front));
        Assert.AreEqual(Vector3.Lerp(rear, front, 0.5f), LookMath.RailPosition(0.5f, rear, front));
    }

    [Test]
    public void TowardLooksAtPointAndClampsPitch()
    {
        var s = Allo.CameraRig.LookMath.Toward(default, Vector3.zero, new Vector3(1, 0, 1), 0);
        Assert.AreEqual(45f, s.yaw, 0.01f);
        Assert.AreEqual(0f, s.pitch, 0.01f);
        var down = Allo.CameraRig.LookMath.Toward(default, Vector3.zero, new Vector3(0, -5, 1), 0);
        Assert.AreEqual(-Allo.CameraRig.LookMath.PitchLimit, down.pitch, 0.01f);
        var based = Allo.CameraRig.LookMath.Toward(default, Vector3.zero, new Vector3(0, 0, 1), 90);
        Assert.AreEqual(270f, based.yaw, 0.01f);
    }

    [Test]
    public void BlendTurnsTheShortWay()
    {
        var a = new Allo.CameraRig.LookState { yaw = 350, pitch = 0 };
        var b = new Allo.CameraRig.LookState { yaw = 10, pitch = -20 };
        var m = Allo.CameraRig.LookMath.Blend(a, b, 0.5f);
        Assert.AreEqual(0f, Mathf.DeltaAngle(0, m.yaw), 0.01f);
        Assert.AreEqual(-10f, m.pitch, 0.01f);
    }
}
