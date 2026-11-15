using System.Collections;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using Rig = Allo.CameraRig.CameraRig;

public class CameraRigInputTests
{
    [UnityTest]
    public IEnumerator EggTouchKeepsTheCalibratedPoseAndPendingGlance()
    {
        const BindingFlags fields = BindingFlags.NonPublic | BindingFlags.Instance;
        var root = new GameObject("Egg touch camera test", typeof(Camera), typeof(Rig), typeof(CabinEgg));
        var previousLock = Rig.Locked;
        try
        {
            var camera = root.GetComponent<Camera>();
            var rig = root.GetComponent<Rig>();
            var input = root.GetComponent<CabinEgg>();
            var egg = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            egg.transform.SetParent(root.transform);
            egg.transform.localPosition = Vector3.forward * 4f;
            yield return null;

            input.SetView("cabin");
            input.Apply(new AppState { view = "cabin", ready = true, connected = true, egg = new EggState { id = "test", active = true } });
            typeof(CabinEgg).GetField("_egg", fields).SetValue(input, egg.transform);
            typeof(CabinEgg).GetField("_camera", fields).SetValue(input, camera);
            var neutral = Quaternion.Euler(25f, 40f, -80f);
            var calibration = typeof(Rig).GetField("_neutral", fields);
            calibration.SetValue(rig, neutral);
            var point = (Vector2)camera.WorldToScreenPoint(egg.transform.position);
            Rig.Glance(Vector3.right * 20f);
            Physics.SyncTransforms();

            typeof(CabinEgg).GetMethod("Begin", fields).Invoke(input, new object[] { point, -1 });
            Assert.IsTrue((bool)typeof(CabinEgg).GetField("_ownsPointer", fields).GetValue(input));
            typeof(CabinEgg).GetMethod("End", fields).Invoke(input, new object[] { point });
            Assert.AreEqual(neutral, calibration.GetValue(rig), "An egg gesture must keep the same physical forward pose");
            Assert.IsFalse((bool)typeof(Rig).GetField("_introWanted", fields).GetValue(rig));
            yield return new WaitForSeconds(1.1f);
            Assert.That(Vector3.Dot(Vector3.right, camera.transform.forward), Is.GreaterThan(.99f));
        }
        finally { Rig.Locked = previousLock; Object.Destroy(root); }
    }

    [UnityTest]
    public IEnumerator RecenterFacesTheDashboardFromTheCurrentSeat()
    {
        var root = new GameObject("Camera recenter test");
        try
        {
            var rear = new GameObject("Rear").transform;
            rear.SetParent(root.transform);
            var front = new GameObject("Front").transform;
            front.SetParent(root.transform);
            front.position = Vector3.forward * 2f;
            var camera = new GameObject("Cabin camera", typeof(Camera), typeof(Rig));
            camera.transform.SetParent(root.transform);
            var rig = camera.GetComponent<Rig>();
            rig.rearAnchor = rear;
            rig.frontAnchor = front;
            yield return null;
            Rig.Ride(.5f, .1f);
            Rig.Glance(Vector3.right * 100f);
            yield return new WaitForSeconds(1.1f);

            Assert.That(Vector3.Dot(Vector3.right, camera.transform.forward), Is.GreaterThan(.99f));
            Assert.AreEqual(1f, camera.transform.position.z, .001f);
            Rig.Recenter();
            yield return null;
            Assert.That(Vector3.Dot(Vector3.forward, camera.transform.forward), Is.GreaterThan(.999f));
            Assert.AreEqual(1f, camera.transform.position.z, .001f);
        }
        finally { Object.Destroy(root); }
    }
}
