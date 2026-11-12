using System.Collections.Generic;
using Allo.Critters;
using Allo.World;
using UnityEngine;
using Rig = Allo.CameraRig.CameraRig;

namespace Allo.App
{
    /// The UGUI village owns non-cabin views; preserve the original cabin until it is requested.
    public sealed class AppWorld : MonoBehaviour
    {
        readonly Dictionary<GameObject, bool> _hidden = new Dictionary<GameObject, bool>();
        readonly Dictionary<Behaviour, bool> _suspended = new Dictionary<Behaviour, bool>();
        Camera _camera;
        Vector3 _cameraPosition;
        Quaternion _cameraRotation;
        bool _orthographic, _fog, _away;
        float _orthographicSize, _fov, _near, _far;
        int _cullingMask;
        Color _background;
        CameraClearFlags _clearFlags;
        string _view = "home";

        public void SetView(string view)
        {
            _view = string.IsNullOrEmpty(view) ? "home" : view;
            if (_view == "cabin") RestoreCabin();
            else ShowVillageBackdrop();
        }

        public void Apply(AppState state) => SetView(state?.view);

        void LateUpdate()
        {
            if (_view != "cabin" && !_away) ShowVillageBackdrop();
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

        void OnDisable() => RestoreCabin();
        void OnDestroy() => RestoreCabin();
    }
}
