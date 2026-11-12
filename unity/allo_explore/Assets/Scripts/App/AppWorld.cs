using System.Collections.Generic;
using Allo.Critters;
using Allo.World;
using UnityEngine;
using Rig = Allo.CameraRig.CameraRig;

namespace Allo.App
{
    /// Preserve the original cabin while the isolated 3D camp renders behind the UGUI map.
    public sealed class AppWorld : MonoBehaviour
    {
        readonly Dictionary<GameObject, bool> _hidden = new Dictionary<GameObject, bool>();
        readonly Dictionary<Behaviour, bool> _suspended = new Dictionary<Behaviour, bool>();
        static AppWorld _instance;
        CampPreviewWorld _preview;
        bool _paused;
        Camera _camera;
        Vector3 _cameraPosition;
        Quaternion _cameraRotation;
        bool _orthographic, _fog, _away;
        float _orthographicSize, _fov, _near, _far;
        int _cullingMask;
        Color _background;
        CameraClearFlags _clearFlags;
        string _view = "home";

        public static RenderTexture CampPreview => _instance != null ? _instance._preview?.Texture : null;

        public static Vector2 FacilityAnchor(string id)
        {
            switch (id)
            {
                case "workshop": return new Vector2(.20f, .46f);
                case "kitchen": return new Vector2(.505f, .43f);
                case "training": return new Vector2(.81f, .47f);
                default: throw new System.ArgumentException("Unknown camp facility", nameof(id));
            }
        }

        public void SetView(string view)
        {
            _view = string.IsNullOrEmpty(view) ? "home" : view;
            _instance = this;
            if (_view == "cabin") { _preview?.SetVisible(false); RestoreCabin(); }
            else
            {
                ShowVillageBackdrop();
                if (_preview == null)
                {
                    var props = new List<GameObject>();
                    foreach (var director in FindObjectsByType<WorldDirector>(FindObjectsInactive.Include, FindObjectsSortMode.None))
                        if (director.props != null) props.AddRange(director.props);
                    _preview = new CampPreviewWorld(props);
                }
                _preview.SetVisible(!_paused && (_view == "home" || _view == "camp"));
            }
        }

        public void Apply(AppState state)
        {
            SetView(state?.view);
            _preview?.Apply(state);
        }

        void LateUpdate()
        {
            if (_paused) return;
            if (_view != "cabin" && !_away) SetView(_view);
            if (_view == "home" || _view == "camp") _preview?.SetVisible(true);
        }

        void ShowVillageBackdrop()
        {
            if (_away) return;
            _camera = Camera.main;
            if (_camera == null) return;
            _cameraPosition = _camera.transform.position;
            _cameraRotation = _camera.transform.rotation;
            _orthographic = _camera.orthographic;
            _orthographicSize = _camera.orthographicSize;
            _fov = _camera.fieldOfView;
            _near = _camera.nearClipPlane;
            _far = _camera.farClipPlane;
            _cullingMask = _camera.cullingMask;
            _background = _camera.backgroundColor;
            _clearFlags = _camera.clearFlags;
            _fog = RenderSettings.fog;
            Suspend(_camera.GetComponent<Rig>());
            Suspend(_camera.GetComponent<TapInput>());
            Suspend(_camera.GetComponent<AlloPost>());
            Hide(GameObject.Find("Cabin"));
            foreach (var world in FindObjectsByType<WorldDirector>(FindObjectsInactive.Include, FindObjectsSortMode.None))
                Hide(world.gameObject);
            foreach (var critters in FindObjectsByType<CritterDirector>(FindObjectsInactive.Include, FindObjectsSortMode.None))
                Hide(critters.gameObject);
            RenderSettings.fog = false;
            _camera.clearFlags = CameraClearFlags.SolidColor;
            _camera.backgroundColor = new Color(.96f, .92f, .83f);
            _camera.cullingMask = 0;
            _away = true;
        }

        void Suspend(Behaviour component)
        {
            if (component == null) return;
            _suspended[component] = component.enabled;
            component.enabled = false;
        }

        void Hide(GameObject go)
        {
            if (go == null || _hidden.ContainsKey(go)) return;
            _hidden[go] = go.activeSelf;
            go.SetActive(false);
        }

        void RestoreCabin()
        {
            if (!_away) return;
            if (_camera != null)
            {
                _camera.transform.SetPositionAndRotation(_cameraPosition, _cameraRotation);
                _camera.orthographic = _orthographic;
                _camera.orthographicSize = _orthographicSize;
                _camera.fieldOfView = _fov;
                _camera.nearClipPlane = _near;
                _camera.farClipPlane = _far;
                _camera.cullingMask = _cullingMask;
                _camera.backgroundColor = _background;
                _camera.clearFlags = _clearFlags;
            }
            RenderSettings.fog = _fog;
            foreach (var pair in _hidden)
                if (pair.Key != null) pair.Key.SetActive(pair.Value);
            foreach (var pair in _suspended)
                if (pair.Key != null) pair.Key.enabled = pair.Value;
            _hidden.Clear();
            _suspended.Clear();
            _away = false;
        }

        void OnApplicationPause(bool paused)
        {
            _paused = paused;
            _preview?.SetVisible(!paused && isActiveAndEnabled && (_view == "home" || _view == "camp"));
        }
        void OnDisable() { _preview?.SetVisible(false); RestoreCabin(); }
        void OnDestroy()
        {
            _preview?.Dispose(); _preview = null;
            RestoreCabin();
            if (_instance == this) _instance = null;
        }
    }
}
