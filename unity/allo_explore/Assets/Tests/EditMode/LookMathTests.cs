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
    public void GyroOffDoesNothingAndOnIsScaled()
    {
        var s = new LookState { yaw = 10 };
        Assert.AreEqual(10f, LookMath.AddGyro(s, new Vector2(5, 5), false).yaw);
        Assert.AreEqual(10f + 5f * LookMath.GyroScale, LookMath.AddGyro(s, new Vector2(5, 0), true).yaw, 1e-4);
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
}
