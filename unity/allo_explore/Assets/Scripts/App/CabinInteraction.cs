using System;
using System.Collections;
using System.Collections.Generic;
using Allo.Critters;
using UnityEngine;
using UnityEngine.EventSystems;
using Rig = Allo.CameraRig.CameraRig;

namespace Allo.App
{
    // Owns only held-item and companion gestures; CabinEgg retains its affinity gesture path.
    [DefaultExecutionOrder(-120)]
    public sealed class CabinInteraction : MonoBehaviour
    {
        static CabinInteraction _instance;
        public static string SelectedItem => _instance != null ? _instance._selected : "";
        public static bool MoveArmed => _instance != null && _instance._moveArmed;
        public static bool IsCapturing => _instance != null && (_instance._capturing || _instance._releasedFrame == Time.frameCount);
        string _selected = "", _gestureTarget = "", _gestureSpecies = "", _gestureEgg = "";
        AppState _state;
        Camera _camera;
        CritterDirector _director;
        Transform _held, _flight, _cushion, _blanket;
        Coroutine _throw;
        CritterView _actor;
        CabinDragVisual _dragVisual;
        Rig _rig;
        TapInput _tap;
        bool _capturing, _throwGesture, _dragging, _moveArmed, _pendingCare, _rigEnabled, _tapEnabled, _previousLock;
        CritterView _pendingTapActor;
        Vector2 _pendingTapPosition;
        float _pendingTapTime;
        long _pendingSequence;
        float _pendingDeadline;
        int _finger, _releasedFrame = -1;
        Vector2 _down, _last;
        Vector2 _velocity;
        float _downTime, _lastMotionTime, _travel, _actorDepth;
        Vector3 _originalPosition, _dragOffset;
        int _originalSurface;

        public static bool IsThrowable(string id) => id == "snack" || id == "water" || id == "ball" || id == "plush";
        public static bool CanUse(AppState state) => CanKeepInteraction(state) && !state.busy;
        public static bool CanKeepInteraction(AppState state) => state != null && state.ready && state.connected &&
            !state.sessionEnded && state.view == "cabin" && state.learning != null && state.learning.active && !state.learning.recording &&
            (AppUi.HasSelectedCompanion(state) || (state.egg != null && state.egg.active && !string.IsNullOrEmpty(state.egg.id)));

        public static bool IsThrowGesture(Vector2 from, Vector2 to, float seconds, float height)
        {
            var delta = to - from;
            return height > 0 && seconds > 0 && delta.magnitude >= height * .1f && delta.y >= -Mathf.Abs(delta.x) * .5f;
        }

        public static string BuddyGesture(float travel, float displacement, float seconds, float height)
        {
            if (height <= 0) return "";
            if (travel >= height * .18f && displacement <= height * .12f && travel > displacement * 2f) return "pet";
            return "";
        }

        public static bool IsDoubleTap(Vector2 first, Vector2 second, float elapsed, float height) =>
            elapsed >= 0 && elapsed <= .28f && Vector2.Distance(first, second) <= height * .06f;

        public static AppAction CareIntent(AppState state, string startedCreature, string action)
        {
            if (!CanKeepInteraction(state) || (!IsThrowable(action) && action != "pet" && action != "cushion" && action != "blanket")) return null;
            var target = state.learning.creatureId ?? "";
            if (target != startedCreature || (target != "" && !AppUi.HasSelectedCompanion(state)) ||
                (target == "" && (!IsThrowable(action) || state.egg?.active != true))) return null;
            return new AppAction { action = "commonCare", actionId = action, creatureId = target, eggId = state.egg?.id };
        }

        public static Vector3 ArcPoint(Vector3 from, Vector3 to, float progress, float lift) =>
            Vector3.Lerp(from, to, Mathf.Clamp01(progress)) + Vector3.up * (Mathf.Sin(Mathf.Clamp01(progress) * Mathf.PI) * lift);

        public static Vector2 ThrowAim(Vector2 releasedAt, Vector2 velocity, float width, float height)
        {
            var at = releasedAt + Vector2.ClampMagnitude(velocity * .08f, height * .22f);
            return new Vector2(Mathf.Clamp(at.x, 0, width), Mathf.Clamp(at.y, 0, height));
        }

        void OnEnable()
        {
            _instance = this;
            AppSession.Changed += Apply;
            Apply(AppSession.State);
        }

        public void Apply(AppState state)
        {
            if (_pendingCare && state?.learning != null && state.learning.careSequence > _pendingSequence)
                _pendingCare = false;
            BeforeWorldChange(state);
            _state = state;
            if (!CanKeepInteraction(state)) SetRestVisible(false);
        }

        public void BeforeWorldChange(AppState state)
        {
            var changed = _state?.learning?.creatureId != state?.learning?.creatureId ||
                _state?.learning?.speciesId != state?.learning?.speciesId || _state?.egg?.id != state?.egg?.id ||
                _state?.egg?.active != state?.egg?.active || _state?.isDemo != state?.isDemo || _state?.view != state?.view;
            if (changed) CancelAll("snapshot identity or view changed");
            else if (!CanKeepInteraction(state)) CancelAll(BlockReason(state));
        }

        public static void SelectItem(string actionId)
        {
            var input = _instance;
            if (input == null || input._pendingCare || !CanUse(input._state) || !IsThrowable(actionId)) return;
            var selected = input._selected == actionId ? "" : actionId;
            input.CancelAll("item selection");
            input._selected = selected;
            input.EnsureHeld();
        }

        bool Blocked => FindFirstObjectByType<AppUi>() is { } ui && ui.CabinGesturesBlocked;

        void Update()
        {
            _camera = Camera.main;
            if (_director == null) _director = FindFirstObjectByType<CritterDirector>();
            if (_pendingCare && Time.unscaledTime >= _pendingDeadline) { _pendingCare = false; _director?.ClearCabinCareLanding(); }
            if (!CanKeepInteraction(_state) || Blocked || _camera == null)
            {
                CancelAll(!CanKeepInteraction(_state) ? BlockReason(_state) : Blocked ? "UI blocked" : "camera absent");
                SetRestVisible(false); return;
            }
            if (_pendingTapActor != null && !_capturing && !_state.busy && Time.unscaledTime - _pendingTapTime > .28f)
            {
                var tapped = _pendingTapActor; _pendingTapActor = null;
                Trace("single tap opens conversation"); _director?.InviteCompanion(tapped);
            }
            EnsureRestProps();
            EnsureHeld();
            if (_held != null && !_capturing) _held.position = HeldPosition(new Vector2(Screen.width * .5f, Screen.height * .17f));
            if (Input.touchCount > 1) { CancelAll("multiple pointers"); return; }
            if (Input.touchCount == 1)
            {
                var touch = Input.GetTouch(0);
                if (touch.phase == TouchPhase.Began) Begin(touch.position, touch.fingerId);
                else if (touch.phase == TouchPhase.Canceled) { if (_capturing) Trace("pointer canceled"); CancelGesture(); }
                else if (touch.phase == TouchPhase.Ended) End(touch.position);
                else Move(touch.position);
            }
#if UNITY_EDITOR
            else
            {
                if (Input.GetMouseButtonDown(0)) Begin(Input.mousePosition, -1);
                else if (Input.GetMouseButton(0)) Move(Input.mousePosition);
                if (Input.GetMouseButtonUp(0)) End(Input.mousePosition);
            }
#endif
        }

        void EnsureHeld()
        {
            if (_held != null || _throw != null || !IsThrowable(_selected) || _camera == null) return;
            _held = Toys.Make(_selected == "snack" ? Toys.Kind.Apple : CabinEgg.CareToyKind(_selected));
            _held.name = "Cabin held " + _selected;
            _held.SetParent(transform, true);
            RemoveColliders(_held);
            _held.position = HeldPosition(new Vector2(Screen.width * .5f, Screen.height * .17f));
        }

        Vector3 HeldPosition(Vector2 screen) => _camera.ScreenToWorldPoint(new Vector3(screen.x, screen.y, .55f));
        public static bool IsOverUi(Vector2 position, bool traceHit = false)
        {
            var events = EventSystem.current;
            if (events == null) return false;
            // This component runs before EventSystem.Update; its cached pointer still describes the previous tap.
            var pointer = new PointerEventData(events) { position = position };
            var hits = new List<RaycastResult>();
            events.RaycastAll(pointer, hits);
            if (traceHit && hits.Count > 0)
            {
                var graphic = hits[0].gameObject.GetComponent<UnityEngine.UI.Graphic>();
                Debug.Log("[CabinGesture] UI hit " + hits[0].gameObject.name + " (" + (graphic != null ? graphic.GetType().Name : "raycaster") + ")");
            }
            return hits.Count > 0;
        }

        void Begin(Vector2 position, int finger)
        {
            if (_capturing || _throw != null || _pendingCare || IsOverUi(position) || _camera == null || !CanKeepInteraction(_state) || Blocked)
            {
                if (_selected != "") Trace(IsOverUi(position) ? "held begin rejected by current UI" : !CanKeepInteraction(_state) ? BlockReason(_state) : "held begin temporarily blocked");
                if (_selected != "") IsOverUi(position, true);
                return;
            }
            _throwGesture = _held != null && Vector2.Distance(position, _camera.WorldToScreenPoint(_held.position)) <= Screen.height * .15f;
            _actor = null;
            if (!_throwGesture)
            {
                if (_director == null) return;
                var candidate = _moveArmed ? _director.Companion :
                    Physics.Raycast(_camera.ScreenPointToRay(position), out var hit, 80) ? hit.collider.GetComponentInParent<CritterView>() : null;
                if (candidate == null || candidate != _director.Companion || !AppUi.HasSelectedCompanion(_state)) return;
                if (_pendingTapActor == candidate && IsDoubleTap(_pendingTapPosition, position, Time.unscaledTime - _pendingTapTime, Screen.height))
                {
                    _moveArmed = true; _pendingTapActor = null;
                    Trace("double tap armed moving");
                }
                _director.CancelCommonCare();
                _actor = candidate;
                _originalPosition = candidate.Brain.Position; _originalSurface = candidate.Brain.Surface;
                candidate.Brain.Hold = true; candidate.Brain.StayAsleep = false;
                _actorDepth = _camera.WorldToScreenPoint(candidate.transform.position).z;
                _dragOffset = candidate.transform.position - _camera.ScreenToWorldPoint(new Vector3(position.x, position.y, _actorDepth));
            }
            _gestureTarget = _state.learning.creatureId ?? "";
            _gestureSpecies = _state.learning.speciesId;
            _gestureEgg = _state.egg?.id;
            _finger = finger; _down = _last = position; _travel = 0; _downTime = Time.unscaledTime;
            _lastMotionTime = _downTime; _velocity = Vector2.zero;
            _capturing = true; _dragging = false;
            _previousLock = Rig.Locked; Rig.Locked = true;
            _rig = _camera.GetComponent<Rig>(); _rigEnabled = _rig != null && _rig.enabled;
            _tap = _camera.GetComponent<TapInput>(); _tapEnabled = _tap != null && _tap.enabled;
            if (_rig != null) _rig.enabled = false;
            if (_tap != null) _tap.enabled = false;
            Trace(_throwGesture ? "held pointer captured" : "buddy pointer captured");
        }

        void Move(Vector2 position)
        {
            if (!_capturing) return;
            var delta = position - _last;
            _travel += delta.magnitude;
            if (delta.sqrMagnitude > 1)
            {
                _velocity = delta / Mathf.Max(.016f, Time.unscaledTime - _lastMotionTime);
                _lastMotionTime = Time.unscaledTime;
            }
            _last = position;
            if (_throwGesture) { if (_held != null) _held.position = HeldPosition(position); return; }
            if (_actor == null) { CancelGesture(); return; }
            var displacement = Vector2.Distance(_down, position);
            if (!_dragging && _moveArmed && displacement >= Screen.height * .025f)
            {
                _dragging = true;
                _dragVisual = gameObject.AddComponent<CabinDragVisual>();
                _dragVisual.Actor = _actor;
            }
            if (_dragging && _dragVisual != null)
                _dragVisual.Position = _camera.ScreenToWorldPoint(new Vector3(position.x, position.y, _actorDepth)) + _dragOffset;
        }

        void End(Vector2 position)
        {
            if (!_capturing) return;
            Move(position);
            var valid = CanKeepInteraction(_state) && !Blocked && !IsOverUi(position) && (_state.learning.creatureId ?? "") == _gestureTarget &&
                _state.learning.speciesId == _gestureSpecies && _state.egg?.id == _gestureEgg;
            var elapsed = Time.unscaledTime - _downTime;
            var action = _throwGesture ? (IsThrowGesture(_down, position, elapsed, Screen.height) ? _selected : "") :
                _dragging ? RestAt(position) : BuddyGesture(_travel, Vector2.Distance(_down, position), elapsed, Screen.height);
            var actor = _actor;
            var moved = _dragging;
            var quick = !_throwGesture && !_dragging && _travel < Screen.height * .03f && elapsed <= .35f;
            var target = _gestureTarget;
            CancelGesture();
            if (!valid)
            {
                Trace(!CanKeepInteraction(_state) ? BlockReason(_state) : IsOverUi(position) ? "release canceled by current UI" : "release canceled by target or modal");
                IsOverUi(position, true);
                return;
            }
            if (quick)
            {
                if (!_moveArmed)
                {
                    _pendingTapActor = actor; _pendingTapPosition = position; _pendingTapTime = Time.unscaledTime;
                    Trace("single tap deferred");
                }
                return;
            }
            if (moved && action == "")
            {
                if (_director.TryCabinLanding(_camera.ScreenPointToRay(position), out var freeAt, out var freeSurface) &&
                    _director.PlaceCabinCompanion(_gestureSpecies, freeAt, freeSurface))
                { _moveArmed = false; Trace("companion placed without reward"); }
                return;
            }
            var intent = CareIntent(_state, target, action);
            if (intent == null)
            {
                Trace("release without care");
                return;
            }
            if (IsThrowable(action))
            {
                var aim = ThrowAim(position, _velocity, Screen.width, Screen.height);
                if (_held != null && _director != null && _director.TryCabinLanding(_camera.ScreenPointToRay(aim), out var at, out var surface))
                {
                    Trace("throw released");
                    _throw = StartCoroutine(ThrowItem(intent, at, surface));
                }
                return;
            }
            if ((action == "cushion" || action == "blanket") && _director.TryCabinRestSpot(action, out var rest, out var restSurface))
                _director.QueueCabinCareLanding(_state.learning.speciesId, action, rest, restSurface);
            _moveArmed = false;
            SendCare(intent);
        }

        IEnumerator ThrowItem(AppAction intent, Vector3 at, int surface)
        {
            _flight = _held; _held = null; _selected = "";
            var item = _flight; var from = item.position;
            var species = _state.learning.speciesId; var egg = _state.egg?.id;
            var duration = _state.reducedMotion ? .16f : .62f;
            var originalScale = item.localScale;
            if (!_state.reducedMotion)
            {
                var trail = item.gameObject.AddComponent<TrailRenderer>();
                trail.sharedMaterial = _director.critterMaterial;
                trail.time = .16f; trail.startWidth = .018f; trail.endWidth = 0;
                trail.startColor = new Color(1, .94f, .73f, .5f); trail.endColor = new Color(1, .94f, .73f, 0);
                trail.minVertexDistance = .012f; trail.Clear();
            }
            for (var t = 0f; t < duration && item != null; t += Time.unscaledDeltaTime)
            {
                var k = t / duration;
                item.position = ArcPoint(from, at, k, _state.reducedMotion ? 0 : .32f);
                item.localScale = originalScale * Mathf.Lerp(1.25f, 1f, k);
                if (!_state.reducedMotion) item.Rotate(Vector3.right, 420 * Time.unscaledDeltaTime, Space.World);
                yield return null;
            }
            if (item != null) item.position = at;
            Trace("throw landed");
            var accepted = CareIntent(_state, intent.creatureId, intent.actionId);
            if (accepted != null && !Blocked && _state.learning.speciesId == species && _state.egg?.id == egg)
            {
                if (!string.IsNullOrEmpty(intent.creatureId)) _director.QueueCabinCareLanding(species, intent.actionId, at, surface);
                SendCare(accepted);
            }
            DestroyVisual(_flight); _flight = null; _throw = null;
        }

        void SendCare(AppAction intent)
        {
            _pendingCare = true; _pendingSequence = _state.learning.careSequence; _pendingDeadline = Time.unscaledTime + 5;
            StartCoroutine(SubmitWhenReady(intent));
        }

        IEnumerator SubmitWhenReady(AppAction intent)
        {
            var deadline = Time.unscaledTime + 2;
            var species = _state.learning.speciesId;
            var egg = _state.egg?.id;
            while (CanKeepInteraction(_state) && _state.busy && Time.unscaledTime < deadline) yield return null;
            var current = CareIntent(_state, intent.creatureId, intent.actionId);
            if (current != null && CanUse(_state) && !Blocked && _state.learning.speciesId == species && _state.egg?.id == egg)
            { Trace("care intent sent"); AppSession.Request("commonCare", current); }
            else { Trace("care submission canceled"); _pendingCare = false; _director?.ClearCabinCareLanding(); }
        }

        string RestAt(Vector2 position)
        {
            var nearest = Screen.height * .14f; var action = "";
            foreach (var id in new[] { "cushion", "blanket" })
            {
                if (!_director.TryCabinRestSpot(id, out var at, out _)) continue;
                var screen = _camera.WorldToScreenPoint(at);
                var distance = Vector2.Distance(position, screen);
                if (screen.z > 0 && distance < nearest) { nearest = distance; action = id; }
            }
            return action;
        }

        void EnsureRestProps()
        {
            if (_director == null || !AppUi.HasSelectedCompanion(_state)) { SetRestVisible(false); return; }
            MakeRest(ref _cushion, "cushion", Toys.Kind.Cushion);
            MakeRest(ref _blanket, "blanket", Toys.Kind.Blanket);
            SetRestVisible(true);
        }

        void MakeRest(ref Transform prop, string action, Toys.Kind kind)
        {
            if (!_director.TryCabinRestSpot(action, out var at, out _)) return;
            if (prop == null)
            {
                prop = Toys.Make(kind); prop.name = "Cabin fixed " + action; prop.SetParent(transform, true); RemoveColliders(prop);
                // A wide, flat resting patch stays visible on the door sill instead of hiding behind a seat.
                var bounds = Toys.BoundsOf(prop);
                if (kind == Toys.Kind.Cushion && bounds.size.y > bounds.size.z * 2)
                    prop.rotation = Quaternion.Euler(90, 0, 0);
                bounds = Toys.BoundsOf(prop);
                if (bounds.size.x > .001f) prop.localScale *= .26f / bounds.size.x;
                if (kind == Toys.Kind.Blanket) prop.localScale = Vector3.Scale(prop.localScale, new Vector3(1, .35f, 1));
            }
            prop.position = at;
            var placed = Toys.BoundsOf(prop);
            prop.position += new Vector3(at.x - placed.center.x, at.y + .006f - placed.min.y, at.z - placed.center.z);
        }

        void SetRestVisible(bool visible)
        {
            if (_cushion != null) _cushion.gameObject.SetActive(visible);
            if (_blanket != null) _blanket.gameObject.SetActive(visible);
        }

        void CancelGesture()
        {
            if (!_capturing) return;
            _capturing = false; _releasedFrame = Time.frameCount;
            if (_dragVisual != null) { _dragVisual.Actor = null; DestroyVisual(_dragVisual); _dragVisual = null; }
            if (_actor != null)
            {
                _actor.Brain.Place(_originalPosition, _originalSurface);
                _actor.Brain.Hold = false; _actor.transform.position = _originalPosition;
            }
            _actor = null; _dragging = false;
            if (_rig != null) _rig.enabled = _rigEnabled;
            if (_tap != null) _tap.enabled = _tapEnabled;
            Rig.Locked = _previousLock;
        }

        void CancelAll(string reason = "reset")
        {
            if (_selected != "" || _capturing || _throw != null || _pendingCare || _moveArmed || _pendingTapActor != null) Trace("cancel: " + reason);
            CancelGesture();
            StopAllCoroutines();
            _throw = null; _selected = ""; _pendingCare = false;
            _moveArmed = false; _pendingTapActor = null;
            DestroyVisual(_held); DestroyVisual(_flight); _held = _flight = null;
            if (_director != null) _director.ClearCabinCareLanding();
        }

        static void RemoveColliders(Transform root)
        {
            foreach (var collider in root.GetComponentsInChildren<Collider>()) collider.enabled = false;
        }

        static void DestroyVisual(UnityEngine.Object obj)
        {
            if (obj == null) return;
            var target = obj is Transform t ? t.gameObject : obj;
            if (Application.isPlaying) Destroy(target); else DestroyImmediate(target);
        }

        static void Trace(string message) => Debug.Log("[CabinGesture] " + message);
        static string BlockReason(AppState state) => state == null ? "state absent" : !state.ready ? "state not ready" :
            !state.connected ? "disconnected" : state.sessionEnded ? "session ended" : state.view != "cabin" ? "outside cabin" :
            state.learning == null ? "learning absent" : !state.learning.active ? "learning inactive" : state.learning.recording ? "recording" :
            state.busy ? "state temporarily busy" : "no valid target";

        void OnApplicationPause(bool paused) { if (paused) CancelAll("application paused"); }
        void OnApplicationFocus(bool focused) { if (!focused) CancelAll("application unfocused"); }
        void OnDisable()
        {
            AppSession.Changed -= Apply; CancelAll(); SetRestVisible(false);
            if (_instance == this) _instance = null;
        }
    }

    // Run after CritterView's pose so the held preview follows the finger without changing its brain surface.
    [DefaultExecutionOrder(1000)]
    public sealed class CabinDragVisual : MonoBehaviour
    {
        public CritterView Actor;
        public Vector3 Position;
        void LateUpdate() { if (Actor != null) Actor.transform.position = Position; }
    }
}
