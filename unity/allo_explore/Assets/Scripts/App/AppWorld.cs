using System.Collections.Generic;
using System.Text;
using Allo.Critters;
using Allo.World;
using UnityEngine;
using Rig = Allo.CameraRig.CameraRig;

namespace Allo.App
{
    /// Presentation only: every level, friend and work indicator comes from the saved snapshot.
    public sealed class AppWorld : MonoBehaviour
    {
        static readonly Vector3 CampOrigin = new Vector3(1000, 0, 0);
        static readonly string[] FacilityIds = { "workshop", "kitchen", "training" };
        static readonly Color Cream = new Color(1f, .91f, .74f);
        static readonly Color Cocoa = new Color(.36f, .23f, .18f);
        static readonly Color Mint = new Color(.49f, .73f, .61f);
        static readonly Color Coral = new Color(.88f, .48f, .35f);
        static readonly Color Gold = new Color(1f, .73f, .28f);

        sealed class FacilityVisual
        {
            public Transform root, progress;
            public GameObject built, plot, working;
            public readonly GameObject[] tiers = new GameObject[3];
            public readonly Renderer[] lamps = new Renderer[3];
        }

        readonly Dictionary<string, FacilityVisual> _facilities = new Dictionary<string, FacilityVisual>();
        readonly Dictionary<Color, Material> _materials = new Dictionary<Color, Material>();
        readonly List<Material> _friendMaterials = new List<Material>();
        readonly Dictionary<GameObject, bool> _hidden = new Dictionary<GameObject, bool>();
        readonly Dictionary<Behaviour, bool> _suspended = new Dictionary<Behaviour, bool>();
        Transform _camp, _friends;
        Camera _camera;
        Vector3 _cameraPosition;
        Quaternion _cameraRotation;
        bool _orthographic, _fog, _away;
        float _orthographicSize, _fov, _near, _far;
        Color _background;
        CameraClearFlags _clearFlags;
        string _view = "home", _friendKey;
        AppState _state;

        public void SetView(string view)
        {
            _view = string.IsNullOrEmpty(view) ? "home" : view;
            EnsureCamp();
            if (_view == "cabin") RestoreCabin();
            else EnterCamp();
        }

        public void Apply(AppState state)
        {
            _state = state;
            EnsureCamp();
            foreach (var pair in _facilities)
            {
                FacilityState saved = null;
                if (state?.facilities != null)
                    foreach (var item in state.facilities)
                        if (item != null && item.id == pair.Key) { saved = item; break; }
                var level = Mathf.Clamp(saved?.level ?? 0, 0, 3);
                var visual = pair.Value;
                visual.built.SetActive(level > 0);
                visual.plot.SetActive(level == 0);
                for (var i = 0; i < 3; i++)
                {
                    visual.tiers[i].SetActive(level > i);
                    visual.lamps[i].sharedMaterial = Mat(level > i ? Gold : Cocoa);
                }
                JobState job = null;
                if (state?.jobs != null)
                    foreach (var item in state.jobs)
                        if (item != null && Matches(item, pair.Key)) { job = item; break; }
                visual.working.SetActive(job != null);
                visual.progress.localScale = new Vector3(Mathf.Clamp01(job?.progress ?? 0), 1, 1);
            }
            RefreshFriends();
            SetView(state?.view);
        }

        static bool Matches(JobState job, string facility)
        {
            if (job.targetId == facility) return true;
            return facility == "kitchen" && job.role == "cook" ||
                   facility == "training" && job.role == "trainer";
        }

        void LateUpdate()
        {
            if (_view != "cabin" && !_away) EnterCamp();
        }

        void EnterCamp()
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
            _background = _camera.backgroundColor;
            _clearFlags = _camera.clearFlags;
            _fog = RenderSettings.fog;
            Suspend(_camera.GetComponent<Rig>());
            Suspend(_camera.GetComponent<TapInput>());
            Suspend(_camera.GetComponent<AlloPost>());
            Hide(GameObject.Find("Cabin"));
            foreach (var world in FindObjectsByType<WorldDirector>(FindObjectsInactive.Include, FindObjectsSortMode.None)) Hide(world.gameObject);
            foreach (var critters in FindObjectsByType<CritterDirector>(FindObjectsInactive.Include, FindObjectsSortMode.None)) Hide(critters.gameObject);
            _camp.gameObject.SetActive(true);
            RenderSettings.fog = false;
            _camera.clearFlags = CameraClearFlags.SolidColor;
            _camera.backgroundColor = new Color(.91f, .85f, .72f);
            _camera.orthographic = true;
            _camera.orthographicSize = 5.4f;
            _camera.nearClipPlane = .1f;
            _camera.farClipPlane = 60;
            _camera.transform.position = CampOrigin + new Vector3(9, 11, -15);
            _camera.transform.LookAt(CampOrigin + new Vector3(0, .3f, .5f));
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
            if (_camp != null) _camp.gameObject.SetActive(false);
            if (!_away) return;
            if (_camera != null)
            {
                _camera.transform.SetPositionAndRotation(_cameraPosition, _cameraRotation);
                _camera.orthographic = _orthographic;
                _camera.orthographicSize = _orthographicSize;
                _camera.fieldOfView = _fov;
                _camera.nearClipPlane = _near;
                _camera.farClipPlane = _far;
                _camera.backgroundColor = _background;
                _camera.clearFlags = _clearFlags;
            }
            RenderSettings.fog = _fog;
            foreach (var pair in _hidden) if (pair.Key != null) pair.Key.SetActive(pair.Value);
            foreach (var pair in _suspended) if (pair.Key != null) pair.Key.enabled = pair.Value;
            _hidden.Clear();
            _suspended.Clear();
            _away = false;
        }

        void EnsureCamp()
        {
            if (_camp != null) return;
            _camp = new GameObject("AppCampDiorama").transform;
            _camp.SetParent(transform, false);
            _camp.position = CampOrigin;
            Shape(_camp, "Sand plinth", PrimitiveType.Cylinder, new Vector3(0, -.27f, 0), new Vector3(12.2f, .22f, 9.4f), Cream);
            Shape(_camp, "Meadow", PrimitiveType.Cylinder, new Vector3(0, -.08f, 0), new Vector3(11.8f, .08f, 9f), Mint);
            Shape(_camp, "Gathering rug", PrimitiveType.Cylinder, new Vector3(0, .015f, -1.1f), new Vector3(4.8f, .025f, 3.2f), Cream);
            for (var i = 0; i < 7; i++)
                Shape(_camp, "Stepping stone", PrimitiveType.Cylinder, new Vector3((i - 3) * .65f, .025f, -.1f + Mathf.Sin(i) * .15f), new Vector3(.27f, .035f, .2f), Cream);
            MakeFacility("workshop", new Vector3(-3.4f, 0, 1.2f), Gold);
            MakeFacility("kitchen", new Vector3(0, 0, 2), Coral);
            MakeFacility("training", new Vector3(3.4f, 0, 1), Mint);
            for (var i = 0; i < 8; i++)
            {
                var angle = (i * 29 + 12) * Mathf.Deg2Rad;
                var pos = new Vector3(Mathf.Cos(angle) * 5.1f, 0, Mathf.Sin(angle) * 3.8f);
                Tree(pos, .8f + i % 3 * .16f);
            }
            for (var i = 0; i < 9; i++)
            {
                var x = -3.4f + i * .85f;
                Shape(_camp, "Fence post", PrimitiveType.Capsule, new Vector3(x, .28f, 3.45f), new Vector3(.13f, .3f, .13f), Cocoa);
            }
            Shape(_camp, "Fence rail", PrimitiveType.Cube, new Vector3(0, .35f, 3.45f), new Vector3(7, .09f, .09f), Cocoa);
            Shape(_camp, "Welcome board", PrimitiveType.Cube, new Vector3(-3.5f, .55f, -2.5f), new Vector3(1.3f, .55f, .12f), Cocoa);
            Label(_camp, "ALLO CAMP", new Vector3(-3.5f, .55f, -2.58f), .12f, Cream);
            Shape(_camp, "Welcome post", PrimitiveType.Cube, new Vector3(-3.5f, .25f, -2.5f), new Vector3(.1f, .6f, .1f), Cocoa);
            var light = new GameObject("Camp softbox").AddComponent<Light>();
            light.transform.SetParent(_camp, false);
            light.type = LightType.Point;
            light.range = 25;
            light.intensity = 2;
            light.color = new Color(1, .88f, .7f);
            light.transform.localPosition = new Vector3(-3, 7, -4);
            _friends = new GameObject("Collected friends").transform;
            _friends.SetParent(_camp, false);
            _camp.gameObject.SetActive(false);
        }

        void MakeFacility(string id, Vector3 position, Color accent)
        {
            var v = new FacilityVisual();
            v.root = new GameObject(id).transform;
            v.root.SetParent(_camp, false);
            v.root.localPosition = position;
            Shape(v.root, "Deck", PrimitiveType.Cylinder, new Vector3(0, .04f, 0), new Vector3(2.84f, .07f, 2.2f), Cream);
            v.built = new GameObject("Built facility");
            v.built.transform.SetParent(v.root, false);
            Shape(v.built.transform, "Counter", PrimitiveType.Cube, new Vector3(0, .45f, 0), new Vector3(1.65f, .7f, .85f), Cream);
            Shape(v.built.transform, "Counter top", PrimitiveType.Cube, new Vector3(0, .85f, 0), new Vector3(1.85f, .14f, 1), Cocoa);
            for (var side = -1; side <= 1; side += 2)
                Shape(v.built.transform, "Canopy post", PrimitiveType.Cylinder, new Vector3(side * .86f, 1.05f, .28f), new Vector3(.09f, 1.05f, .09f), Cocoa);
            Shape(v.built.transform, "Round canopy", PrimitiveType.Sphere, new Vector3(0, 2.05f, .05f), new Vector3(2.2f, .35f, 1.3f), accent);
            if (id == "workshop")
            {
                for (var i = 0; i < 3; i++) Shape(v.built.transform, "Timber", PrimitiveType.Cylinder, new Vector3(-.4f + i * .25f, 1.02f, 0), new Vector3(.16f, .38f, .16f), Gold).transform.localRotation = Quaternion.Euler(90, 0, 0);
                Shape(v.built.transform, "Hammer handle", PrimitiveType.Cube, new Vector3(.5f, 1.13f, -.1f), new Vector3(.09f, .45f, .09f), Cocoa);
                Shape(v.built.transform, "Hammer head", PrimitiveType.Cube, new Vector3(.5f, 1.35f, -.1f), new Vector3(.4f, .18f, .18f), Mint);
            }
            else if (id == "kitchen")
            {
                Shape(v.built.transform, "Cooking pot", PrimitiveType.Cylinder, new Vector3(0, 1.08f, 0), new Vector3(.55f, .23f, .55f), Coral);
                Shape(v.built.transform, "Pot lid", PrimitiveType.Sphere, new Vector3(0, 1.33f, 0), new Vector3(.62f, .12f, .62f), Cream);
                Shape(v.built.transform, "Lid knob", PrimitiveType.Sphere, new Vector3(0, 1.44f, 0), Vector3.one * .13f, Cocoa);
            }
            else
            {
                Shape(v.built.transform, "Balance beam", PrimitiveType.Cube, new Vector3(0, 1.12f, 0), new Vector3(1.2f, .1f, .12f), Mint);
                for (var side = -1; side <= 1; side += 2)
                    Shape(v.built.transform, "Training weight", PrimitiveType.Sphere, new Vector3(side * .53f, 1.12f, 0), Vector3.one * .35f, Gold);
            }
            v.plot = new GameObject("Unbuilt plot");
            v.plot.transform.SetParent(v.root, false);
            for (var i = 0; i < 4; i++)
                Shape(v.plot.transform, "Plot peg", PrimitiveType.Cylinder, new Vector3(i % 2 == 0 ? -.65f : .65f, .2f, i < 2 ? -.4f : .4f), new Vector3(.1f, .2f, .1f), Cocoa);
            Label(v.plot.transform, "건설 전", new Vector3(0, .25f, -.1f), .1f, Cocoa);
            Shape(v.root, "Facility sign", PrimitiveType.Cube, new Vector3(0, .33f, -.85f), new Vector3(1.7f, .42f, .08f), Cocoa);
            Label(v.root, id == "workshop" ? "공방" : id == "kitchen" ? "주방" : "훈련장", new Vector3(0, .36f, -.9f), .115f, Cream);
            for (var i = 0; i < 3; i++)
            {
                v.lamps[i] = Shape(v.root, "Level " + (i + 1), PrimitiveType.Sphere, new Vector3((i - 1) * .19f, .15f, -.91f), Vector3.one * .1f, Cocoa).GetComponent<Renderer>();
                v.tiers[i] = Shape(v.built.transform, "Upgrade flower " + (i + 1), PrimitiveType.Sphere, new Vector3((i - 1) * .25f, 2.32f, .05f), Vector3.one * .16f, Gold);
            }
            v.working = new GameObject("Authoritative job progress");
            v.working.transform.SetParent(v.root, false);
            Shape(v.working.transform, "Progress track", PrimitiveType.Cube, new Vector3(0, 2.6f, 0), new Vector3(1.45f, .12f, .1f), Cocoa);
            v.progress = new GameObject("Progress fill").transform;
            v.progress.SetParent(v.working.transform, false);
            v.progress.localPosition = new Vector3(-.7f, 2.6f, -.065f);
            Shape(v.progress, "Completed fraction", PrimitiveType.Cube, new Vector3(.7f, 0, 0), new Vector3(1.4f, .08f, .04f), Gold);
            v.working.SetActive(false);
            v.built.SetActive(false);
            _facilities[id] = v;
        }

        void Tree(Vector3 position, float size)
        {
            Shape(_camp, "Tree trunk", PrimitiveType.Cylinder, position + Vector3.up * .45f, new Vector3(.17f, .5f, .17f), Cocoa);
            Shape(_camp, "Tree crown", PrimitiveType.Sphere, position + Vector3.up * (size + .2f), new Vector3(size, size * 1.25f, size), Mint * .85f);
            Shape(_camp, "Tree crown highlight", PrimitiveType.Sphere, position + new Vector3(-.2f, size + .35f, -.1f), Vector3.one * size * .65f, Mint);
        }

        void RefreshFriends()
        {
            var key = new StringBuilder();
            if (_state?.creatures != null)
                foreach (var c in _state.creatures)
                    if (c != null) key.Append(c.id).Append('|').Append(c.speciesId).Append('|').Append(c.sprite).Append(';');
            if (_friendKey == key.ToString()) return;
            _friendKey = key.ToString();
            for (var i = _friends.childCount - 1; i >= 0; i--)
            {
                _friends.GetChild(i).gameObject.SetActive(false);
                Destroy(_friends.GetChild(i).gameObject);
            }
            foreach (var material in _friendMaterials) Destroy(material);
            _friendMaterials.Clear();
            if (_state?.creatures == null) return;
            var index = 0;
            foreach (var creature in _state.creatures)
            {
                if (creature == null) continue;
                var friend = new GameObject("Owned_" + creature.id).transform;
                friend.SetParent(_friends, false);
                var ring = index / 8;
                var angle = index % 8 * Mathf.PI * 2 / 8;
                friend.localPosition = new Vector3(Mathf.Cos(angle) * (1.7f + ring * .55f), .06f, -1.15f + Mathf.Sin(angle) * (.8f + ring * .3f));
                friend.localRotation = Quaternion.Euler(0, 155, 0);
                var prefab = CharacterModel.Find(creature.speciesId);
                if (prefab != null && prefab.GetComponent<CharacterModel>() != null)
                    CharacterModel.Spawn(prefab, friend, .65f);
                else
                {
                    // Missing species art stays a neutral marker; never substitute another species.
                    var marker = Shape(friend, "Art unavailable", PrimitiveType.Capsule, new Vector3(0, .25f, 0), new Vector3(.32f, .25f, .32f), Cream);
                    if (!string.IsNullOrEmpty(creature.sprite))
                    {
                        var spriteParent = friend;
                        StartCoroutine(SpriteLoader.Load(creature.sprite, art =>
                        {
                            if (spriteParent == null) return;
                            marker.SetActive(false);
                            var quad = Shape(spriteParent, "Canonical species art", PrimitiveType.Quad, new Vector3(0, .38f, 0), new Vector3(.75f * art.Aspect, .75f, 1), Color.white);
                            quad.transform.rotation = Quaternion.LookRotation(_camera != null ? quad.transform.position - _camera.transform.position : Vector3.forward);
                            var shader = Shader.Find("Allo/Sprite");
                            if (shader == null) return;
                            var material = new Material(shader) { mainTexture = art[ArtPose.Idle] };
                            material.SetFloat("_Lit", 0);
                            _friendMaterials.Add(material);
                            quad.GetComponent<Renderer>().sharedMaterial = material;
                        }));
                    }
                    Label(friend, "친구", new Vector3(0, .66f, -.05f), .07f, Cocoa);
                }
                index++;
            }
        }

        Material Mat(Color color)
        {
            if (_materials.TryGetValue(color, out var material)) return material;
            var shader = Shader.Find("Allo/Toon") ?? Shader.Find("Standard");
            material = new Material(shader) { color = color };
            if (material.HasProperty("_RimStrength")) material.SetFloat("_RimStrength", .12f);
            _materials[color] = material;
            return material;
        }

        GameObject Shape(Transform parent, string name, PrimitiveType type, Vector3 position, Vector3 scale, Color color)
        {
            var go = GameObject.CreatePrimitive(type);
            go.name = name;
            go.transform.SetParent(parent, false);
            go.transform.localPosition = position;
            go.transform.localScale = scale;
            var collider = go.GetComponent<Collider>();
            if (collider != null) Destroy(collider);
            go.GetComponent<Renderer>().sharedMaterial = Mat(color);
            return go;
        }

        void Label(Transform parent, string text, Vector3 position, float size, Color color)
        {
            var go = new GameObject(text);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = position;
            go.transform.localRotation = Quaternion.identity;
            var label = go.AddComponent<TextMesh>();
            var font = Resources.Load<Font>("Fonts/DoHyeon-Regular") ?? Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            label.font = font;
            go.GetComponent<MeshRenderer>().sharedMaterial = font.material;
            label.text = text;
            label.fontSize = 40;
            label.characterSize = size;
            label.anchor = TextAnchor.MiddleCenter;
            label.color = color;
        }

        void OnDisable() => RestoreCabin();

        void OnDestroy()
        {
            RestoreCabin();
            if (_camp != null) Destroy(_camp.gameObject);
            foreach (var material in _materials.Values) Destroy(material);
            foreach (var material in _friendMaterials) Destroy(material);
        }
    }
}
