using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class PlayModeCabinEggGestureTests
{
    const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    GameObject _root, _cabin, _cameraObject, _events, _canvas;
    CabinEgg _input;
    Camera _camera;
    Transform _egg;
    AppState _previous, _state;
    int _sent;
    bool _previousLock;

    [UnitySetUp]
    public IEnumerator SetUp()
    {
        _previous = AppSession.State;
        _previousLock = Allo.CameraRig.CameraRig.Locked;
        _state = State();
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _state);
        _events = new GameObject("Egg gesture events", typeof(EventSystem), typeof(StandaloneInputModule));
        _events.GetComponent<StandaloneInputModule>().enabled = false;
        _cameraObject = new GameObject("Egg gesture camera", typeof(Camera));
        _cameraObject.tag = "MainCamera";
        _camera = _cameraObject.GetComponent<Camera>();
        _camera.transform.position = new Vector3(0, .14f, -2);
        _camera.transform.rotation = Quaternion.identity;
        _cabin = new GameObject("Cabin");
        var positions = new[] { Vector3.zero, new Vector3(.7f, 0, 0), new Vector3(-.7f, 0, 0), new Vector3(0, -.35f, .3f) };
        for (var i = 0; i < 4; i++)
        {
            var surface = GameObject.CreatePrimitive(PrimitiveType.Cube);
            surface.name = CabinEgg.ZoneSurfaceName(i);
            surface.transform.SetParent(_cabin.transform, false);
            surface.transform.position = positions[i];
            surface.transform.localScale = new Vector3(.3f, .02f, .3f);
            surface.GetComponent<Renderer>().enabled = false;
            Object.Destroy(surface.GetComponent<Collider>());
        }
        _root = new GameObject("Egg gesture host");
        _input = _root.AddComponent<CabinEgg>();
        _input.SetView("cabin");
        _input.Apply(_state);
        _egg = _root.transform.Find("Cabin egg visuals/Cabin egg");
        Application.logMessageReceived += ObserveIntent;
        yield return null;
        Physics.SyncTransforms();
        _sent = 0;
    }

    [UnityTearDown]
    public IEnumerator TearDown()
    {
        Application.logMessageReceived -= ObserveIntent;
        Object.Destroy(_root); Object.Destroy(_cabin); Object.Destroy(_cameraObject);
        Object.Destroy(_events); if (_canvas != null) Object.Destroy(_canvas);
        yield return null;
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous);
        Allo.CameraRig.CameraRig.Locked = _previousLock;
    }

    [Test]
    public void CurrentEggHitIgnoresThePreviousUiPointerCache()
    {
        var ui = UiAt(new Vector2(20, 20));
        var pointers = (Dictionary<int, PointerEventData>)typeof(PointerInputModule).GetField("m_PointerData", Private)
            .GetValue(_events.GetComponent<StandaloneInputModule>());
        pointers[-1] = new PointerEventData(EventSystem.current) { pointerEnter = ui };
        typeof(EventSystem).GetField("m_CurrentInputModule", Private).SetValue(EventSystem.current, _events.GetComponent<StandaloneInputModule>());
        Assert.IsTrue(EventSystem.current.IsPointerOverGameObject(-1), "fixture contains the stale UI contact");
        Begin(EggPoint());
        Move(EggPoint() + Vector2.right * 20);
        Assert.Greater(Vector3.Distance(_egg.position, new Vector3(0, .14f, 0)), .01f,
            "current world input must capture and follow despite the previous UI tap");
    }

    [UnityTest]
    public IEnumerator CurrentUiHitCannotCaptureTheEggWithoutAPointerCache()
    {
        UiAt(EggPoint());
        yield return null;
        Canvas.ForceUpdateCanvases();
        Assert.IsTrue(CabinInteraction.IsOverUi(EggPoint()), "fixture has rendered UI over the egg");
        var at = _egg.position;
        Begin(EggPoint()); Move(EggPoint() + Vector2.right * 30);
        Assert.AreEqual(at, _egg.position);
        Assert.IsFalse(Allo.CameraRig.CameraRig.Locked);
    }

    [Test]
    public void DragFollowsFingerAndSurvivesSnapshotAndUpdateWithoutChangingZone()
    {
        var from = EggPoint(); var original = _egg.position;
        Begin(from); Move(from + Vector2.right * 36);
        Assert.That(((Vector2)_camera.WorldToScreenPoint(_egg.position) - from).x, Is.EqualTo(36).Within(1));
        var preview = _egg.position;
        _input.Apply(State());
        Call("Update");
        Assert.That(Vector3.Distance(preview, _egg.position), Is.LessThan(.001f));
        Assert.AreEqual(0, _state.egg.zone); Assert.AreEqual(0, _sent);
        Call("CancelGesture");
        Assert.That(Vector3.Distance(original, _egg.position), Is.LessThan(.001f));
    }

    [Test]
    public void DragPreviewStaysInFrontOfCabinOccludersWithoutChangingItsScreenSize()
    {
        var from = EggPoint(); var to = from + Vector2.right * 40;
        var originalScale = _egg.localScale;
        var height = ProjectedEggHeight();
        Begin(from);
        var blocker = GameObject.CreatePrimitive(PrimitiveType.Cube);
        try
        {
            blocker.transform.position = _camera.ScreenToWorldPoint(new Vector3(to.x, to.y, 1));
            blocker.transform.localScale = new Vector3(.4f, .4f, .1f);
            Move(to); Physics.SyncTransforms();
            Assert.IsTrue(Physics.Raycast(_camera.ScreenPointToRay(to), out var hit, 10));
            Assert.IsTrue(hit.transform == _egg || hit.transform.IsChildOf(_egg), "the cabin must not hide the held egg");
            var renderer = _egg.GetComponentInChildren<Renderer>();
            var bounds = CabinEgg.SurfaceBounds(renderer);
            var previewHeight = Mathf.Abs(_camera.WorldToScreenPoint(bounds.center + Vector3.up * bounds.extents.y).y -
                _camera.WorldToScreenPoint(bounds.center - Vector3.up * bounds.extents.y).y);
            Assert.That(previewHeight, Is.EqualTo(height).Within(1f), "moving toward the camera must not enlarge the held egg");
            Call("CancelGesture");
            Assert.AreEqual(originalScale, _egg.localScale);
        }
        finally { Object.DestroyImmediate(blocker); }
    }

    [Test]
    public void GentleVisibleEggRubSendsOnePetThenReturnsToItsConfirmedPosition()
    {
        var point = EggPoint(); var original = _egg.position;
        var height = ProjectedEggHeight();
        Begin(point);
        Move(point + Vector2.right * height * .35f);
        Move(point - Vector2.right * height * .35f);
        End(point);
        Assert.AreEqual(1, _sent, "a gentle back-and-forth rub must send petEgg on release");
        Assert.AreEqual(0, _state.egg.zone);
        Assert.That(Vector3.Distance(original, _egg.position), Is.LessThan(.001f));
        End(point); Assert.AreEqual(1, _sent, "the released pointer cannot send twice");
    }

    [Test]
    public void FarDragBackToItsOriginDoesNotBecomeAPet()
    {
        var point = EggPoint(); var original = _egg.position;
        Begin(point); Move(ZonePoint(1)); End(point);
        Assert.AreEqual(0, _sent, "returning a long drag is cancellation, not a rub");
        Assert.That(Vector3.Distance(original, _egg.position), Is.LessThan(.001f));
    }

    [Test]
    public void RubStartingOnTheCurrentZoneMarkerCannotPetTheEgg()
    {
        var marker = _root.transform.Find("Cabin egg visuals/Egg zone 0");
        marker.localScale = new Vector3(.6f, .004f, .6f);
        Physics.SyncTransforms();
        var point = (Vector2)_camera.WorldToScreenPoint(marker.position + Vector3.right * .25f);
        Assert.IsTrue(Physics.Raycast(_camera.ScreenPointToRay(point), out var hit, 80));
        Assert.AreSame(marker, hit.transform, "fixture starts on the exposed marker rim, outside the egg collider");
        var height = ProjectedEggHeight();
        Begin(point); Move(point + Vector2.right * height * .35f);
        Move(point - Vector2.right * height * .35f); End(point);
        Assert.AreEqual(0, _sent, "only a gesture that starts on the egg may pet it");
    }

    [Test]
    public void MarkerTapStillRequestsPlacementWithoutChangingTheSnapshot()
    {
        var point = ZonePoint(1);
        Begin(point); End(point);
        Assert.AreEqual(1, _sent);
        Assert.AreEqual(0, _state.egg.zone);
    }

    [Test]
    public void ValidOtherZoneDropWinsOverRubShapeAndPetCooldown()
    {
        var marker = _root.transform.Find("Cabin egg visuals/Egg zone 1");
        marker.position = new Vector3(.06f, .015f, 0);
        Physics.SyncTransforms();
        _state.egg.petCooldown = 10;
        var point = EggPoint(); var height = ProjectedEggHeight();
        var target = ZonePoint(1);
        Assert.Less(Vector2.Distance(point, target), height * .75f, "nearby zone makes the final displacement look like a rub");
        Begin(point); Move(point + Vector2.right * height * .5f);
        Move(point - Vector2.right * height * .5f); End(target);
        Assert.AreEqual(1, _sent, "a valid zone drop must send placeEgg even while petEgg is cooling down");
        Assert.AreEqual(0, _state.egg.zone, "placement still waits for the host snapshot");
    }

    [Test]
    public void DifferentZoneDropSendsOnceAndWaitsForAuthoritativePlacement()
    {
        var original = _egg.position;
        Begin(EggPoint()); End(ZonePoint(1));
        Assert.AreEqual(1, _sent);
        Assert.AreEqual(0, _state.egg.zone, "dragging cannot mutate the host snapshot");
        Assert.That(Vector3.Distance(original, _egg.position), Is.LessThan(.001f));
        var accepted = State(); accepted.egg.zone = 1;
        _input.Apply(accepted);
        Assert.That(_egg.position.x, Is.EqualTo(.7f).Within(.001f));
    }

    [UnityTest]
    public IEnumerator UiReleaseAndInvalidDropRestorePositionWithoutSendingAnIntent()
    {
        var original = _egg.position;
        var point = ZonePoint(1); UiAt(point);
        yield return null;
        Canvas.ForceUpdateCanvases();
        Assert.IsTrue(CabinInteraction.IsOverUi(point), "fixture has rendered UI over the drop zone");
        Begin(EggPoint()); Move(point); End(point);
        Assert.AreEqual(0, _sent);
        Assert.That(Vector3.Distance(original, _egg.position), Is.LessThan(.001f));
        Begin(EggPoint()); End(new Vector2(-200, -200));
        Assert.AreEqual(0, _sent);
        Assert.That(Vector3.Distance(original, _egg.position), Is.LessThan(.001f));
    }

    [Test]
    public void PhotoGateAndCooldownCannotSendRubOrMoveIntents()
    {
        var point = EggPoint(); var height = ProjectedEggHeight();
        _state.egg.photoRequired = true; _input.Apply(_state);
        Begin(point); End(ZonePoint(1));
        Assert.IsFalse(Allo.CameraRig.CameraRig.Locked, "photo-gated egg does not own input");
        Assert.AreEqual(0, _sent);
        _state.egg.photoRequired = false; _state.egg.petCooldown = 10; _state.egg.moveCooldown = 15;
        _input.Apply(_state);
        Begin(point); Move(point + Vector2.right * height * .35f); Move(point - Vector2.right * height * .35f); End(point);
        Begin(point); End(ZonePoint(1));
        Assert.AreEqual(0, _sent);
    }

    [Test]
    public void ChangedEggCancelsThePreviewAndReleasesTheCamera()
    {
        var rig = _cameraObject.AddComponent<Allo.CameraRig.CameraRig>();
        var tap = _cameraObject.AddComponent<Allo.TapInput>();
        Begin(EggPoint()); Move(EggPoint() + Vector2.right * 35);
        Assert.IsTrue(rig.enabled); Assert.IsTrue(EggOwnsPointer(rig)); Assert.IsFalse(tap.enabled);
        var next = State(); next.egg.id = "replacement";
        _input.Apply(next);
        Assert.IsTrue(rig.enabled); Assert.IsFalse(EggOwnsPointer(rig)); Assert.IsTrue(tap.enabled);
        End(ZonePoint(1)); Assert.AreEqual(0, _sent);
    }

    [TestCase(false)]
    [TestCase(true)]
    public void HostStoryCaptureRestoresPreviewWithoutResettingCameraCalibration(bool playing)
    {
        var rig = _cameraObject.AddComponent<Allo.CameraRig.CameraRig>();
        var neutral = Quaternion.Euler(25, 40, -80);
        var rigType = typeof(Allo.CameraRig.CameraRig);
        rigType.GetField("_neutral", Private).SetValue(rig, neutral);
        rigType.GetField("_introWanted", Private).SetValue(rig, false);
        var originalPosition = _egg.position;
        var originalScale = _egg.localScale;
        var point = EggPoint(); Begin(point); Move(point + Vector2.right * 35);
        Assert.IsTrue(EggOwnsPointer(rig));
        var next = State();
        next.story = new StoryState { ready = true, notebookOpen = !playing, active = playing, topicId = "coast_sail" };
        _input.Apply(next);
        Assert.IsTrue(rig.enabled);
        Assert.IsFalse(EggOwnsPointer(rig));
        Assert.AreEqual(neutral, rigType.GetField("_neutral", Private).GetValue(rig));
        Assert.IsFalse((bool)rigType.GetField("_introWanted", Private).GetValue(rig));
        Assert.AreEqual(originalScale, _egg.localScale);
        Assert.That(Vector3.Distance(originalPosition, _egg.position), Is.LessThan(.001f));
        End(ZonePoint(1)); Assert.AreEqual(0, _sent);
    }

    [Test]
    public void ReleaseFrameClearsCameraInertiaAndLegacyTapBeforeTheyCanHandleTheSamePointer()
    {
        var rig = _cameraObject.AddComponent<Allo.CameraRig.CameraRig>();
        var tap = _cameraObject.AddComponent<Allo.TapInput>();
        var velocity = typeof(Allo.CameraRig.CameraRig).GetField("_velocity", Private);
        velocity.SetValue(rig, new Vector2(70, 40));
        Begin(EggPoint()); End(EggPoint());
        Assert.IsTrue(CabinEgg.IsCapturing, "the release frame still belongs to the egg");
        var rotation = _camera.transform.rotation;
        typeof(Allo.CameraRig.CameraRig).GetMethod("Update", Private).Invoke(rig, null);
        Assert.AreEqual(Vector2.zero, velocity.GetValue(rig));
        Assert.AreEqual(rotation, _camera.transform.rotation);
        Assert.IsTrue(tap.enabled); Assert.AreEqual(0, _sent);
    }

    [Test]
    public void CaptureClearsSuspendedCameraGestureStateWithoutChangingLook()
    {
        var rig = _cameraObject.AddComponent<Allo.CameraRig.CameraRig>();
        var type = typeof(Allo.CameraRig.CameraRig);
        var look = new Allo.CameraRig.LookState { yaw = 12, pitch = 7, rail = .3f };
        type.GetField("_state", Private).SetValue(rig, look);
        type.GetField("_velocity", Private).SetValue(rig, new Vector2(70, 40));
        type.GetField("_lastPinch", Private).SetValue(rig, (float?)100);
        type.GetField("_uiTouch", Private).SetValue(rig, true);
        Begin(EggPoint());
        Assert.IsTrue(rig.enabled);
        Assert.IsTrue(EggOwnsPointer(rig));
        Assert.AreEqual(Vector2.zero, type.GetField("_velocity", Private).GetValue(rig));
        Assert.IsNull(type.GetField("_lastPinch", Private).GetValue(rig));
        Assert.IsFalse((bool)type.GetField("_uiTouch", Private).GetValue(rig));
        Assert.AreEqual(look, type.GetField("_state", Private).GetValue(rig));
    }

    [UnityTest]
    public IEnumerator CameraResumedAfterReleaseFrameDoesNotRecoverOldInertia()
    {
        var rig = _cameraObject.AddComponent<Allo.CameraRig.CameraRig>();
        var type = typeof(Allo.CameraRig.CameraRig);
        var look = new Allo.CameraRig.LookState { yaw = 12, pitch = 7, rail = .3f };
        type.GetField("_state", Private).SetValue(rig, look);
        type.GetMethod("Apply", Private).Invoke(rig, null);
        var rotation = _camera.transform.rotation;
        type.GetField("_velocity", Private).SetValue(rig, new Vector2(70, 40));
        var point = EggPoint(); Begin(point); End(point);
        rig.enabled = false;
        yield return null; yield return null;
        Assert.IsFalse(CabinEgg.IsCapturing, "the rig stays suspended until after the pointer release guard has expired");
        rig.enabled = true;
        type.GetMethod("Update", Private).Invoke(rig, null);
        Assert.AreEqual(Vector2.zero, type.GetField("_velocity", Private).GetValue(rig));
        Assert.AreEqual(look, type.GetField("_state", Private).GetValue(rig));
        Assert.AreEqual(rotation, _camera.transform.rotation);
    }

    [Test]
    public void DrawerOpenedDuringDragCancelsWithoutAnIntent()
    {
        var original = _egg.position;
        Begin(EggPoint()); Move(EggPoint() + Vector2.right * 30);
        var ui = _root.AddComponent<AppUi>();
        typeof(AppUi).GetField("_zoneDrawer", Private).SetValue(ui, true);
        Call("Update");
        Assert.That(Vector3.Distance(original, _egg.position), Is.LessThan(.001f));
        Assert.IsFalse(Allo.CameraRig.CameraRig.Locked);
        End(ZonePoint(1)); Assert.AreEqual(0, _sent);
    }

    [Test]
    public void NavigationRestoresPointerOwnershipBeforeWorldSuspensionCachesTheCamera()
    {
        var rig = _cameraObject.AddComponent<Allo.CameraRig.CameraRig>();
        var tap = _cameraObject.AddComponent<Allo.TapInput>();
        var session = _root.AddComponent<AppSession>();
        var world = _root.AddComponent<AppWorld>();
        var instance = typeof(AppSession).GetField("_instance", BindingFlags.Static | BindingFlags.NonPublic);
        Assert.IsNull(instance.GetValue(null), "isolated test must not replace a running application");
        instance.SetValue(null, session);
        typeof(AppSession).GetField("_world", Private).SetValue(session, world);
        typeof(AppSession).GetField("_egg", Private).SetValue(session, _input);
        Begin(EggPoint());
        var home = State(); home.view = "home"; home.revision = 1;
        AppSession.Receive(home);
        Assert.IsFalse(rig.enabled); Assert.IsFalse(tap.enabled, "world suspends camera input while away");
        var back = State(); back.revision = 2;
        AppSession.Receive(back);
        Assert.IsTrue(rig.enabled); Assert.IsTrue(tap.enabled, "returning must restore the enabled state before the egg claimed it");
        End(ZonePoint(1)); Assert.AreEqual(0, _sent);
    }

    [Test]
    public void ChildColliderCanStartTheSameEggGesture()
    {
        var child = new GameObject("Egg child collider", typeof(SphereCollider));
        child.transform.SetParent(_egg, false);
        child.GetComponent<SphereCollider>().radius = .5f;
        _egg.GetComponent<Collider>().enabled = false;
        Physics.SyncTransforms();
        var original = _egg.position;
        Begin(EggPoint()); Move(EggPoint() + Vector2.right * 30);
        Assert.Greater(Vector3.Distance(original, _egg.position), .01f);
    }

    static bool EggOwnsPointer(Allo.CameraRig.CameraRig rig) =>
        (bool)typeof(Allo.CameraRig.CameraRig).GetProperty("EggOwnsPointer", Private).GetValue(rig);
    Vector2 EggPoint() => _camera.WorldToScreenPoint(_egg.position);
    Vector2 ZonePoint(int zone) => _camera.WorldToScreenPoint(_root.transform.Find("Cabin egg visuals/Egg zone " + zone).position);
    float ProjectedEggHeight() => Mathf.Abs(_camera.WorldToScreenPoint(_egg.position + Vector3.up * .12f).y -
        _camera.WorldToScreenPoint(_egg.position - Vector3.up * .12f).y);
    void Begin(Vector2 p) => Call("Begin", p, -1);
    void Move(Vector2 p) => Call("Move", p);
    void End(Vector2 p) => Call("End", p);
    void Call(string method, params object[] args) => typeof(CabinEgg).GetMethod(method, Private).Invoke(_input, args);
    void ObserveIntent(string message, string trace, LogType type) { if (message.Contains("[AndroidHost]")) _sent++; }
    GameObject UiAt(Vector2 position)
    {
        if (_canvas == null)
        {
            _canvas = new GameObject("Egg gesture UI", typeof(Canvas), typeof(GraphicRaycaster));
            _canvas.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
        }
        var ui = new GameObject("Egg gesture blocker", typeof(RectTransform), typeof(Image));
        ui.transform.SetParent(_canvas.transform, false);
        var rect = ui.GetComponent<RectTransform>();
        rect.anchorMin = rect.anchorMax = Vector2.zero;
        rect.pivot = Vector2.zero; rect.anchoredPosition = position - Vector2.one * 15;
        rect.sizeDelta = Vector2.one * 30;
        Canvas.ForceUpdateCanvases();
        return ui;
    }
    static AppState State() => new AppState { ready = true, connected = true, view = "cabin", reducedMotion = true,
        egg = new EggState { id = "current", active = true, zone = 0, preferredZone = 1 } };
}
