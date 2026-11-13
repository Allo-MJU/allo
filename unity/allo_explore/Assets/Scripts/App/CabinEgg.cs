using System;
using System.Collections.Generic;
using Allo.Critters;
using UnityEngine;
using UnityEngine.EventSystems;
using Rig = Allo.CameraRig.CameraRig;

namespace Allo.App
{
    // Claim an egg gesture before the legacy cabin and camera input sees it.
    [DefaultExecutionOrder(-100)]
    public sealed class CabinEgg : MonoBehaviour
    {
        public const float EggHeight = 0.24f;
        static readonly string[] Surfaces = { "Walk_Dashboard", "Walk_DoorSill_L", "Walk_DoorSill_R", "Walk_Floor" };
        readonly Transform[] _zones = new Transform[4];
        readonly Renderer[] _zoneRenderers = new Renderer[4];
        readonly bool[] _available = new bool[4];
        readonly List<Material> _materials = new List<Material>();
        AppState _state;
        string _view = "home", _gestureId, _revealSprite;
        Transform _visuals, _egg, _reveal, _shells;
        Renderer _eggRenderer, _revealRenderer;
        Mesh _eggMesh;
        Camera _camera;
        Rig _rig;
        TapInput _tap;
        bool _ownsPointer, _rigEnabled, _tapEnabled, _previousLock, _markerStart;
        int _finger, _targetZone = -1;
        Vector2 _down, _last;
        float _travel, _bounce, _ending;

        public static bool ShowEgg(string view, EggState egg) =>
            view == "cabin" && egg != null && egg.active && !string.IsNullOrEmpty(egg.id);

        public static bool ShowReveal(string view, EggState egg) =>
            view == "cabin" && egg != null && !egg.active && egg.phase == "hatched";

        public static string ZoneSurfaceName(int zone)
        {
            if (zone < 0 || zone >= Surfaces.Length) throw new ArgumentOutOfRangeException(nameof(zone));
            return Surfaces[zone];
        }

        public static Bounds SurfaceBounds(Renderer renderer)
        {
            // Walk renderers are disabled and the cabin may be inactive before its first view.
            var filter = renderer.GetComponent<MeshFilter>();
            var local = filter != null && filter.sharedMesh != null ? filter.sharedMesh.bounds : renderer.localBounds;
            var matrix = renderer.transform.localToWorldMatrix;
            var world = new Bounds(matrix.MultiplyPoint3x4(local.center), Vector3.zero);
            for (var x = 0; x < 2; x++)
            for (var y = 0; y < 2; y++)
            for (var z = 0; z < 2; z++)
                world.Encapsulate(matrix.MultiplyPoint3x4(new Vector3(
                    x == 0 ? local.min.x : local.max.x,
                    y == 0 ? local.min.y : local.max.y,
                    z == 0 ? local.min.z : local.max.z)));
            return world;
        }

        public static Vector3 PositionOnSurface(Bounds surface) =>
            new Vector3(surface.center.x, surface.max.y + EggHeight * 0.5f, surface.center.z);

        public static bool CanInteract(AppState state, string view, string startedEggId) =>
            state != null && state.ready && !state.busy && !state.sessionEnded &&
            !(state.story != null && state.story.active && !state.story.paused) &&
            ShowEgg(view, state.egg) && state.egg.id == startedEggId && !state.egg.photoBusy && !state.egg.speechBusy;

        public static AppAction EggIntent(AppState state, string view, string startedEggId, string action, int zone)
        {
            if (!CanInteract(state, view, startedEggId)) return null;
            if (action == "petEgg" && state.egg.petCooldown <= 0)
                return new AppAction { action = action, eggId = state.egg.id };
            if (action == "placeEgg" && zone >= 0 && zone < 4 && state.egg.moveCooldown <= 0)
                return new AppAction { action = action, eggId = state.egg.id, zone = zone };
            return null;
        }

        // A back-and-forth rub has travel but little displacement; a move ends in another zone.
        public static string GestureAction(float travel, float displacement, bool changedZone, float height)
        {
            if (changedZone && displacement > height * 0.12f) return "placeEgg";
            if (travel >= height * 0.18f && displacement <= height * 0.12f && travel > displacement * 2f) return "petEgg";
            return "";
        }

        public void SetView(string view)
        {
            _view = view;
            if (view != "cabin") CancelGesture();
            RefreshVisibility();
        }

        public void Apply(AppState state)
        {
            var previous = _state != null ? _state.egg : null;
            _state = state;
            var egg = state != null ? state.egg : null;
            if (_ownsPointer && !CanInteract(state, _view, _gestureId)) CancelGesture();
            if (previous != null && egg != null && previous.id == egg.id)
            {
                if (egg.score > previous.score) _bounce = 0.7f;
                else if (egg.feedback != previous.feedback)
                    _bounce = egg.feedback == "positive" || egg.feedback == "photoRequired" ? 0.7f : 0;
                if (previous.active && !egg.active && (egg.phase == "failed" || egg.phase == "discarded")) _ending = 0.65f;
            }
            EnsureModel();
            if (_egg != null && egg != null)
            {
                var zone = Mathf.Clamp(egg.zone, 0, 3);
                if (_available[zone]) _egg.position = _zones[zone].position + Vector3.up * (EggHeight * 0.5f + 0.005f);
                _eggRenderer.sharedMaterial.color = egg.photoRequired ? new Color(1f, 0.84f, 0.34f) :
                    Color.Lerp(new Color(1f, 0.92f, 0.73f), new Color(0.64f, 0.9f, 0.76f), Mathf.Clamp01(egg.score / 100f));
                _reveal.position = _egg.position;
                _shells.position = _egg.position;

            }
            RefreshVisibility();
        }

        void EnsureModel()
        {
            if (_visuals != null) return;
            Transform cabin = null;
            foreach (var t in FindObjectsByType<Transform>(FindObjectsInactive.Include, FindObjectsSortMode.None))
                if (t.name == "Cabin") { cabin = t; break; }
            if (cabin == null) return;
            _visuals = new GameObject("Cabin egg visuals").transform;
            _visuals.SetParent(transform, false);
            var renderers = cabin.GetComponentsInChildren<Renderer>(true);
            for (var i = 0; i < 4; i++)
            {
                var marker = Primitive("Egg zone " + i, PrimitiveType.Cylinder, _visuals, new Color(0.55f, 0.82f, 0.74f));
                _zones[i] = marker.transform;
                _zoneRenderers[i] = marker.GetComponent<Renderer>();
                marker.transform.localScale = new Vector3(0.23f, 0.004f, 0.23f);
                foreach (var renderer in renderers)
                {
                    if (renderer.name != ZoneSurfaceName(i)) continue;
                    var position = PositionOnSurface(SurfaceBounds(renderer));
                    marker.transform.position = position - Vector3.up * (EggHeight * 0.5f - 0.005f);
                    _available[i] = true;
                    break;
                }
                marker.SetActive(_available[i]);
            }
            var body = Primitive("Cabin egg", PrimitiveType.Sphere, _visuals, new Color(1f, 0.92f, 0.73f));
            _egg = body.transform;
            _egg.localScale = new Vector3(0.18f, EggHeight, 0.18f);
            _eggRenderer = body.GetComponent<Renderer>();
            var bodyFilter = body.GetComponent<MeshFilter>();
            _eggMesh = Instantiate(bodyFilter.sharedMesh);
            bodyFilter.sharedMesh = _eggMesh;
            var vertices = _eggMesh.vertices;
            for (var i = 0; i < vertices.Length; i++)
            {
                var taper = 1f - vertices[i].y * 0.45f;
                vertices[i].x *= taper;
                vertices[i].z *= taper;
            }
            _eggMesh.vertices = vertices;
            _eggMesh.RecalculateNormals();
            _eggMesh.RecalculateBounds();
            var reveal = Primitive("Saved hatch reveal", PrimitiveType.Quad, _visuals, Color.white);
            RemoveCollider(reveal);
            _reveal = reveal.transform;
            _revealRenderer = reveal.GetComponent<Renderer>();
            var spriteMaterial = new Material(Shader.Find("Allo/Sprite"));
            _materials.Add(spriteMaterial);
            _revealRenderer.sharedMaterial = spriteMaterial;
            _revealRenderer.enabled = false;
            _shells = new GameObject("Egg shell farewell").transform;
            _shells.SetParent(_visuals, false);
            for (var i = 0; i < 2; i++)
            {
                var shell = Primitive("Shell", PrimitiveType.Sphere, _shells, new Color(0.9f, 0.84f, 0.67f));
                RemoveCollider(shell);
                shell.transform.localPosition = new Vector3(i == 0 ? -0.07f : 0.07f, -0.08f, 0);
                shell.transform.localScale = new Vector3(0.085f, 0.035f, 0.1f);
                shell.transform.localRotation = Quaternion.Euler(0, 0, i == 0 ? -30 : 30);
            }
        }

        GameObject Primitive(string name, PrimitiveType type, Transform parent, Color color)
        {
            var go = GameObject.CreatePrimitive(type);
            go.name = name;
            go.transform.SetParent(parent, false);
            var material = new Material(Shader.Find("Allo/Toon") ?? Shader.Find("Standard")) { color = color };
            _materials.Add(material);
            go.GetComponent<Renderer>().sharedMaterial = material;
            return go;
        }

        static void RemoveCollider(GameObject go)
        {
            var collider = go.GetComponent<Collider>();
            if (collider == null) return;
            collider.enabled = false;
            if (Application.isPlaying) Destroy(collider); else DestroyImmediate(collider);
        }

        void RefreshVisibility()
        {
            if (_visuals == null) return;
            var egg = _state != null ? _state.egg : null;
            var active = ShowEgg(_view, egg);
            var reveal = ShowReveal(_view, egg);
            _visuals.gameObject.SetActive(_view == "cabin" && (active || reveal || _ending > 0));
            _egg.gameObject.SetActive(active && _available[Mathf.Clamp(egg.zone, 0, 3)]);
            _reveal.gameObject.SetActive(reveal);
            if (reveal && !string.IsNullOrEmpty(egg.sprite) && _revealSprite != egg.sprite)
            {
                _revealSprite = egg.sprite;
                _revealRenderer.enabled = false;
                var sprite = egg.sprite;
                StartCoroutine(SpriteLoader.Load(sprite, art =>
                {
                    if (_state?.egg?.sprite != sprite || _revealRenderer == null) return;
                    _revealRenderer.sharedMaterial.mainTexture = art[ArtPose.Happy];
                    _reveal.localScale = new Vector3(EggHeight * art.Aspect, EggHeight, 1);
                    _revealRenderer.enabled = true;
                }));
            }
            _shells.gameObject.SetActive(reveal || (_view == "cabin" && _ending > 0));
            for (var i = 0; i < 4; i++) _zones[i].gameObject.SetActive(active && _available[i]);
        }

        void Update()
        {
            _camera = Camera.main;
            if (_view != "cabin" || _visuals == null || _state?.egg == null) return;
            _bounce = Mathf.Max(0, _bounce - Time.unscaledDeltaTime);
            if (_ending > 0)
            {
                _ending = Mathf.Max(0, _ending - Time.unscaledDeltaTime);
                _shells.localScale = Vector3.one * Mathf.Clamp01(_ending / 0.65f);
                RefreshVisibility();
            }
            else _shells.localScale = Vector3.one;
            var egg = _state.egg;
            if (_egg.gameObject.activeSelf)
            {
                var hop = _state.reducedMotion ? 0 : Mathf.Sin((0.7f - _bounce) * Mathf.PI / 0.7f) * _bounce * 0.06f;
                var zone = Mathf.Clamp(egg.zone, 0, 3);
                _egg.position = _zones[zone].position + Vector3.up * (EggHeight * 0.5f + 0.005f + Mathf.Max(0, hop));
                for (var i = 0; i < 4; i++)
                    _zoneRenderers[i].sharedMaterial.color = i == _targetZone && _ownsPointer ? Color.white :
                        i == egg.preferredZone ? new Color(1f, 0.81f, 0.25f) : new Color(0.55f, 0.82f, 0.74f);
            }
            if (_reveal.gameObject.activeSelf && _camera != null)
                _reveal.rotation = Quaternion.LookRotation(_reveal.position - _camera.transform.position);
            if (AppSession.StoryActive || StoryOverlay.CapturingInput) { CancelGesture(); return; }
            if (Input.touchCount > 1) { CancelGesture(); return; }
            if (Input.touchCount == 1)
            {
                var touch = Input.GetTouch(0);
                if (touch.phase == TouchPhase.Began) Begin(touch.position, touch.fingerId);
                else if (touch.phase == TouchPhase.Canceled) CancelGesture();
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

        bool OverUi(int finger) => EventSystem.current != null && EventSystem.current.IsPointerOverGameObject(finger);

        void Begin(Vector2 position, int finger)
        {
            if (_camera == null || OverUi(finger) || !CanInteract(_state, _view, _state?.egg?.id)) return;
            if (!Physics.Raycast(_camera.ScreenPointToRay(position), out var hit, 80f)) return;
            var hitEgg = hit.transform == _egg;
            var zone = Array.IndexOf(_zones, hit.transform);
            if (!hitEgg && zone < 0) return;
            _finger = finger;
            _down = _last = position;
            _travel = 0;
            _targetZone = zone;
            _markerStart = !hitEgg;
            _gestureId = _state.egg.id;
            _ownsPointer = true;
            _previousLock = Rig.Locked;
            Rig.Locked = true;
            _rig = _camera.GetComponent<Rig>();
            _tap = _camera.GetComponent<TapInput>();
            _rigEnabled = _rig != null && _rig.enabled;
            _tapEnabled = _tap != null && _tap.enabled;
            if (_rig != null) _rig.enabled = false;
            if (_tap != null) _tap.enabled = false;
        }

        void Move(Vector2 position)
        {
            if (!_ownsPointer) return;
            _travel += Vector2.Distance(_last, position);
            _last = position;
            _targetZone = -1;
            var nearest = Screen.height * 0.14f;
            for (var i = 0; i < 4; i++)
            {
                if (!_available[i]) continue;
                var point = _camera.WorldToScreenPoint(_zones[i].position);
                if (point.z <= 0) continue;
                var distance = Vector2.Distance(position, point);
                if (distance >= nearest) continue;
                nearest = distance;
                _targetZone = i;
            }
        }

        void End(Vector2 position)
        {
            if (!_ownsPointer) return;
            Move(position);
            var displacement = Vector2.Distance(_down, position);
            var changed = _targetZone >= 0 && _targetZone != _state.egg.zone;
            var action = _markerStart && changed && displacement < Screen.height * 0.05f ? "placeEgg" :
                GestureAction(_travel, displacement, changed, Screen.height);
            var intent = OverUi(_finger) ? null : EggIntent(_state, _view, _gestureId, action, _targetZone);
            CancelGesture();
            if (intent != null) AppSession.Request(intent.action, intent);
        }

        void CancelGesture()
        {
            if (!_ownsPointer) return;
            _ownsPointer = false;
            _targetZone = -1;
            if (_rig != null) _rig.enabled = _rigEnabled;
            if (_tap != null) _tap.enabled = _tapEnabled;
            Rig.Locked = _previousLock;
        }

        void OnDisable() => CancelGesture();
        void OnDestroy()
        {
            CancelGesture();
            foreach (var material in _materials)
                if (Application.isPlaying) Destroy(material); else DestroyImmediate(material);
            if (_eggMesh != null)
                if (Application.isPlaying) Destroy(_eggMesh); else DestroyImmediate(_eggMesh);
        }
    }
}
