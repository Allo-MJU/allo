using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using Object = UnityEngine.Object;

namespace Allo.App
{
    /// A presentation-only camp, rendered behind the existing bounded UGUI map.
    public sealed class CampPreviewWorld : IDisposable
    {
        const int Layer = 30;
        const int Mask = 1 << Layer;
        readonly GameObject _root;
        readonly Camera _camera;
        readonly Dictionary<string, GameObject> _props = new Dictionary<string, GameObject>();
        readonly Dictionary<Material, Material> _converted = new Dictionary<Material, Material>();
        readonly List<Material> _materials = new List<Material>();
        readonly Dictionary<Light, int> _lightMasks = new Dictionary<Light, int>();
        readonly Dictionary<string, Transform> _facilities = new Dictionary<string, Transform>();
        readonly List<Light> _lights = new List<Light>();
        readonly Material _grass, _soil, _wood, _endGrain, _stone, _canvas, _iron, _straw, _rope, _red;
        readonly Shader _shader;
        bool _visible, _disposed;
        bool _fog;
        AmbientMode _ambientMode;
        Color _ambientLight, _sky, _equator, _ground;
        float _ambientIntensity, _reflectionIntensity, _shadowDistance;
        ShadowQuality _shadows;
        ShadowResolution _shadowResolution;

        public RenderTexture Texture { get; private set; }

        public CampPreviewWorld(IEnumerable<GameObject> props)
        {
            if (props != null) foreach (var p in props) if (p != null) _props[p.name] = p;
            _shader = Shader.Find("Standard") ?? Shader.Find("Allo/Toon");
            _grass = Material("Meadow grass", "778B43"); _soil = Material("Trampled soil", "9A835B");
            _wood = Material("Rough cedar", "785537"); _endGrain = Material("Sawn timber", "B9955C");
            _stone = Material("Raw grey stone", "7D8276"); _canvas = Material("Weathered canvas", "B6AE83");
            _iron = Material("Forged iron", "3B4440"); _straw = Material("Straw stuffing", "C3A257");
            _rope = Material("Hemp rope", "C5B58D"); _red = Material("Target paint", "9A4837");
            _root = new GameObject("Survival camp preview") { layer = Layer };
            _root.transform.position = new Vector3(5000, 0, 0);
            var cameraObject = Child("Camp preview camera", _root.transform);
            _camera = cameraObject.AddComponent<Camera>();
            _camera.enabled = false; _camera.orthographic = true; _camera.orthographicSize = 10.8f;
            _camera.aspect = 16f / 9; _camera.nearClipPlane = .3f; _camera.farClipPlane = 150;
            _camera.cullingMask = Mask; _camera.clearFlags = CameraClearFlags.SolidColor;
            _camera.backgroundColor = new Color(.65f, .76f, .83f); _camera.allowHDR = false; _camera.allowMSAA = false;
            _camera.transform.localPosition = new Vector3(0, 21, -26);
            _camera.transform.LookAt(_root.transform.position);
            Texture = new RenderTexture(1920, 1080, 24, RenderTextureFormat.ARGB32) {
                name = "ALLO survival camp preview", antiAliasing = 1, useMipMap = false,
                autoGenerateMips = false, wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear
            };
            Texture.Create(); _camera.targetTexture = Texture;
            MakeLight("Camp daylight", new Vector3(48, -38, 0), Color.white, 1.12f, true);
            MakeLight("Camp sky fill", new Vector3(62, 142, 0), new Color(.72f, .82f, 1), .28f, false);
            Landscape();
            foreach (var id in new[] { "workshop", "kitchen", "training" })
            {
                var facility = Child("Facility " + id, _root.transform).transform;
                var ray = _camera.ViewportPointToRay(AppWorld.FacilityAnchor(id));
                if (new Plane(Vector3.up, _root.transform.position).Raycast(ray, out var distance)) facility.position = ray.GetPoint(distance);
                facility.localScale = Vector3.one * .88f;
                _facilities[id] = facility;
                Patch(facility, new Vector3(0, .012f, 1.65f), new Vector3(5.5f, .025f, 5.3f));
                if (id == "workshop") Workshop(facility);
                else if (id == "kitchen") Kitchen(facility);
                else Training(facility);
                Upgrades(facility, id);
            }
            Apply(null);
        }

        public void Apply(AppState state)
        {
            foreach (var pair in _facilities)
            {
                var level = 0;
                if (state?.facilities != null) foreach (var facility in state.facilities)
                    if (facility != null && facility.id == pair.Key) { level = Mathf.Clamp(facility.level, 0, 3); break; }
                pair.Value.Find("Level 2").gameObject.SetActive(level >= 2);
                pair.Value.Find("Level 3").gameObject.SetActive(level >= 3);
            }
        }

        public void SetVisible(bool visible)
        {
            if (_disposed) return;
            if (visible && !Texture.IsCreated()) Texture.Create();
            if (_visible == visible) return;
            _visible = visible; _camera.enabled = visible;
            foreach (var light in _lights) light.enabled = visible;
            if (visible)
            {
                _shadowDistance = QualitySettings.shadowDistance; _shadows = QualitySettings.shadows; _shadowResolution = QualitySettings.shadowResolution;
                QualitySettings.shadowDistance = Mathf.Max(60, _shadowDistance); QualitySettings.shadows = ShadowQuality.All;
                QualitySettings.shadowResolution = (ShadowResolution)Mathf.Max((int)ShadowResolution.Medium, (int)_shadowResolution);
                _fog = RenderSettings.fog; _ambientMode = RenderSettings.ambientMode; _ambientLight = RenderSettings.ambientLight;
                _sky = RenderSettings.ambientSkyColor; _equator = RenderSettings.ambientEquatorColor; _ground = RenderSettings.ambientGroundColor;
                _ambientIntensity = RenderSettings.ambientIntensity; _reflectionIntensity = RenderSettings.reflectionIntensity;
                RenderSettings.fog = false; RenderSettings.ambientMode = AmbientMode.Trilight;
                RenderSettings.ambientSkyColor = new Color(.61f, .70f, .82f);
                RenderSettings.ambientEquatorColor = new Color(.42f, .46f, .35f);
                RenderSettings.ambientGroundColor = new Color(.24f, .23f, .17f);
                RenderSettings.ambientIntensity = 1; RenderSettings.reflectionIntensity = .12f;
                // The cabin sun is global; remove only the preview bit while this scene is visible.
                foreach (var light in Object.FindObjectsByType<Light>(FindObjectsInactive.Include, FindObjectsSortMode.None))
                {
                    if (light.transform.IsChildOf(_root.transform)) continue;
                    _lightMasks[light] = light.cullingMask; light.cullingMask &= ~Mask;
                }
            }
            else
            {
                QualitySettings.shadowDistance = _shadowDistance; QualitySettings.shadows = _shadows; QualitySettings.shadowResolution = _shadowResolution;
                RenderSettings.fog = _fog; RenderSettings.ambientMode = _ambientMode; RenderSettings.ambientLight = _ambientLight;
                RenderSettings.ambientSkyColor = _sky; RenderSettings.ambientEquatorColor = _equator; RenderSettings.ambientGroundColor = _ground;
                RenderSettings.ambientIntensity = _ambientIntensity; RenderSettings.reflectionIntensity = _reflectionIntensity;
                foreach (var pair in _lightMasks) if (pair.Key != null) pair.Key.cullingMask = pair.Value;
                _lightMasks.Clear();
            }
        }

        void MakeLight(string name, Vector3 rotation, Color color, float intensity, bool shadows)
        {
            var go = Child(name, _root.transform); go.transform.localRotation = Quaternion.Euler(rotation);
            var light = go.AddComponent<Light>(); light.type = LightType.Directional; light.color = color; light.intensity = intensity;
            light.cullingMask = Mask; light.shadows = shadows ? LightShadows.Soft : LightShadows.None;
            light.shadowStrength = .62f; light.shadowBias = .035f; light.shadowNormalBias = .25f;
            light.enabled = false; _lights.Add(light);
        }

        void Landscape()
        {
            Box("Continuous grass ground", _root.transform, new Vector3(0, -.16f, 0), new Vector3(120, .3f, 120), _grass);
            // Broad irregular clearings and a worn route connect useful work areas without a city grid.
            for (var i = 0; i < 14; i++)
            {
                var x = -23 + i * 3.5f;
                Patch(_root.transform, new Vector3(x, .006f, -3.7f + Mathf.Sin(i * .7f) * .7f), new Vector3(5, .015f, 2.4f));
            }
            var rng = new System.Random(812);
            for (var i = 0; i < 37; i++)
            {
                var x = -37 + (float)rng.NextDouble() * 74;
                var z = i < 22 ? 10 + (float)rng.NextDouble() * 23 : -19 + (float)rng.NextDouble() * 29;
                if (i >= 22 && Mathf.Abs(x) < 21) x = Mathf.Sign(x) * (23 + (float)rng.NextDouble() * 9);
                var h = 4.5f + (float)rng.NextDouble() * 3.8f;
                Tree(_root.transform, new Vector3(x, 0, z), h, i);
            }
            for (var i = 0; i < 27; i++)
            {
                var x = -28 + (float)rng.NextDouble() * 56; var z = 7 + (float)rng.NextDouble() * 20;
                var h = .4f + (float)rng.NextDouble() * 1.1f;
                if (!Prop("K_rock_large" + (i % 2 == 0 ? "A" : "B"), _root.transform, new Vector3(x, 0, z), h, i * 37))
                    Shape("Weathered rock", PrimitiveType.Sphere, _root.transform, new Vector3(x, h * .4f, z), new Vector3(h * 1.7f, h, h * 1.2f), _stone);
            }
            // Small tufts are sparse geometry, not a particle system or an animated grass field.
            for (var i = 0; i < 44; i++)
            {
                var x = -25 + (float)rng.NextDouble() * 50; var z = -10 + (float)rng.NextDouble() * 25;
                if (z > -1 && z < 6 && (Mathf.Abs(x + 12) < 4 || Mathf.Abs(x) < 4 || Mathf.Abs(x - 12) < 4)) continue;
                Prop("K_grass", _root.transform, new Vector3(x, 0, z), .2f + (float)rng.NextDouble() * .16f, i * 23);
            }
        }

        void Tree(Transform parent, Vector3 position, float height, int index)
        {
            if (Prop(index % 3 == 0 ? "K_tree_detailed" : "K_tree_pineRoundC", parent, position, height, index * 53)) return;
            var root = Child("Pine", parent).transform; root.localPosition = position;
            Shape("Trunk", PrimitiveType.Cylinder, root, new Vector3(0, height * .28f, 0), new Vector3(.4f, height * .28f, .4f), _wood);
            for (var i = 0; i < 3; i++) Shape("Pine canopy", PrimitiveType.Sphere, root, new Vector3(0, height * (.48f + i * .18f), 0), new Vector3(height * (.55f - i * .12f), height * .38f, height * (.55f - i * .12f)), _grass);
        }

        void Workshop(Transform p)
        {
            // Open timber scaffold and a single practical canvas roof, never a cottage.
            foreach (var x in new[] { -1.75f, 1.75f })
                foreach (var z in new[] { .45f, 3.1f }) Box("Scaffold post", p, new Vector3(x, 1.5f, z), new Vector3(.16f, 3, .16f), _wood);
            Beam("Ridge support", p, new Vector3(-1.9f, 2.95f, 1.8f), new Vector3(1.9f, 2.95f, 1.8f), .14f, _wood);
            Box("Canvas canopy", p, new Vector3(0, 3.03f, 1.8f), new Vector3(4.15f, .06f, 3.05f), _canvas, new Vector3(7, 0, 0));
            Box("Workbench top", p, new Vector3(0, 1.05f, 1.3f), new Vector3(2.75f, .22f, .95f), _endGrain);
            foreach (var x in new[] { -1.05f, 1.05f }) foreach (var z in new[] { .98f, 1.62f }) Box("Bench leg", p, new Vector3(x, .48f, z), new Vector3(.18f, .96f, .18f), _wood);
            Box("Cut board", p, new Vector3(.15f, 1.2f, 1.3f), new Vector3(1.4f, .1f, .34f), _wood, new Vector3(0, -12, 0));
            Box("Woodworking clamp", p, new Vector3(-.8f, 1.27f, .93f), new Vector3(.2f, .34f, .27f), _iron);
            if (!Prop("K_log_stack", p, new Vector3(-1.1f, 0, 2.55f), .84f, 90)) Logs(p, new Vector3(-1.1f, .18f, 2.55f), 4);
            Crate(p, new Vector3(1.28f, .36f, 2.6f), .72f);
        }

        void Kitchen(Transform p)
        {
            if (!Prop("K_campfire_stones", p, new Vector3(-.35f, 0, 1.5f), .38f, 0))
            {
                for (var i = 0; i < 9; i++) { var a = i * Mathf.PI * 2 / 9; Shape("Hearth stone", PrimitiveType.Sphere, p, new Vector3(-.35f + Mathf.Cos(a) * .68f, .14f, 1.5f + Mathf.Sin(a) * .68f), new Vector3(.42f, .3f, .34f), _stone); }
                Logs(p, new Vector3(-.35f, .12f, 1.5f), 2);
            }
            var fire = Material("Hearth embers", "C96B2C");
            Shape("Embers", PrimitiveType.Sphere, p, new Vector3(-.35f, .2f, 1.5f), new Vector3(.65f, .22f, .6f), fire);
            Shape("Cooking cauldron", PrimitiveType.Sphere, p, new Vector3(-.35f, .85f, 1.5f), new Vector3(1.05f, .8f, 1.05f), _iron);
            Shape("Cauldron rim", PrimitiveType.Cylinder, p, new Vector3(-.35f, 1.11f, 1.5f), new Vector3(1.03f, .055f, 1.03f), _iron);
            Shape("Soup surface", PrimitiveType.Cylinder, p, new Vector3(-.35f, 1.17f, 1.5f), new Vector3(.84f, .012f, .84f), Material("Soup", "A98035"));
            foreach (var x in new[] { -1.12f, .42f }) Beam("Cooking tripod", p, new Vector3(x, 0, 1.25f), new Vector3(-.35f, 2.25f, 1.5f), .1f, _wood);
            Beam("Rear tripod leg", p, new Vector3(-.35f, 0, 2.6f), new Vector3(-.35f, 2.25f, 1.5f), .1f, _wood);
            Beam("Cauldron chain", p, new Vector3(-.35f, 1.15f, 1.5f), new Vector3(-.35f, 2.2f, 1.5f), .035f, _iron);
            Box("Preparation table", p, new Vector3(1.48f, .96f, 2.35f), new Vector3(1.3f, .16f, .8f), _endGrain);
            foreach (var x in new[] { 1f, 1.95f }) Box("Table supports", p, new Vector3(x, .45f, 2.35f), new Vector3(.15f, .9f, .64f), _wood);
            Shape("Supply sack", PrimitiveType.Sphere, p, new Vector3(1.6f, .36f, .62f), new Vector3(.7f, .75f, .7f), _canvas);
            Crate(p, new Vector3(-1.6f, .35f, 2.65f), .7f);
        }

        void Training(Transform p)
        {
            Box("Training mat", p, new Vector3(-.65f, .04f, 1), new Vector3(1.9f, .055f, 2.1f), _canvas);
            Box("Dummy upright", p, new Vector3(-.65f, .93f, 1.3f), new Vector3(.16f, 1.86f, .16f), _wood);
            Shape("Straw dummy torso", PrimitiveType.Capsule, p, new Vector3(-.65f, 1.3f, 1.3f), new Vector3(.65f, .47f, .5f), _straw);
            Shape("Straw dummy head", PrimitiveType.Sphere, p, new Vector3(-.65f, 2.02f, 1.3f), new Vector3(.45f, .47f, .43f), _straw);
            Box("Dummy crossbar", p, new Vector3(-.65f, 1.62f, 1.3f), new Vector3(1.65f, .13f, .13f), _wood);
            Box("Dummy binding", p, new Vector3(-.65f, 1.35f, 1.03f), new Vector3(.7f, .09f, .035f), _rope);
            foreach (var x in new[] { .95f, 1.75f }) Beam("Target stand", p, new Vector3(x, 0, 2.5f), new Vector3(1.35f, 1.65f, 2.5f), .1f, _wood);
            Shape("Target", PrimitiveType.Cylinder, p, new Vector3(1.35f, 1.7f, 2.5f), new Vector3(1.35f, .07f, 1.35f), _straw, new Vector3(90, 0, 0));
            Shape("Target ring", PrimitiveType.Cylinder, p, new Vector3(1.35f, 1.7f, 2.42f), new Vector3(.86f, .012f, .86f), _red, new Vector3(90, 0, 0));
            Shape("Target center", PrimitiveType.Cylinder, p, new Vector3(1.35f, 1.7f, 2.4f), new Vector3(.36f, .015f, .36f), _straw, new Vector3(90, 0, 0));
            for (var i = 0; i < 4; i++) Box("Fence post", p, new Vector3(-1.9f + i * 1.3f, .65f, 3.35f), new Vector3(.14f, 1.3f, .15f), _wood);
            for (var i = 0; i < 2; i++) Box("Fence rail", p, new Vector3(0, .43f + i * .5f, 3.35f), new Vector3(4.2f, .12f, .12f), _endGrain);
        }

        void Upgrades(Transform parent, string id)
        {
            var second = Child("Level 2", parent).transform;
            if (id == "workshop") Logs(second, new Vector3(2.1f, .2f, 2.1f), 4);
            else Crate(second, new Vector3(2.1f, .35f, .8f), .7f);
            var third = Child("Level 3", parent).transform;
            Box("Additional supply shelf", third, new Vector3(-1.8f, .65f, 3.25f), new Vector3(1.2f, .13f, .65f), _endGrain);
            foreach (var x in new[] { -2.25f, -1.35f }) Box("Shelf legs", third, new Vector3(x, .3f, 3.25f), new Vector3(.12f, .6f, .5f), _wood);
            Crate(third, new Vector3(-1.8f, .99f, 3.25f), .55f);
        }

        void Logs(Transform parent, Vector3 at, int count)
        {
            for (var i = 0; i < count; i++)
            {
                var p = at + new Vector3((i % 3 - 1) * .32f, i / 3 * .28f, 0);
                Shape("Stored log", PrimitiveType.Cylinder, parent, p, new Vector3(.29f, .65f, .29f), _wood, new Vector3(90, 0, 0));
                Shape("Sawn log end", PrimitiveType.Cylinder, parent, p + new Vector3(0, 0, -.66f), new Vector3(.25f, .012f, .25f), _endGrain, new Vector3(90, 0, 0));
            }
        }
        void Crate(Transform p, Vector3 at, float size)
        {
            Box("Supply crate", p, at, Vector3.one * size, _wood);
            foreach (var y in new[] { -.32f, .32f }) Box("Crate brace", p, at + new Vector3(0, size * y, -size * .51f), new Vector3(size * 1.06f, .08f, .05f), _endGrain);
            Box("Crate diagonal", p, at + new Vector3(0, 0, -size * .52f), new Vector3(size * 1.18f, .075f, .05f), _endGrain, new Vector3(0, 0, 42));
        }
        void Patch(Transform p, Vector3 at, Vector3 size) => Shape("Worn earth", PrimitiveType.Cylinder, p, at, size, _soil);
        void Box(string name, Transform p, Vector3 at, Vector3 size, Material material, Vector3 rotation = default) => Shape(name, PrimitiveType.Cube, p, at, size, material, rotation);
        void Beam(string name, Transform p, Vector3 from, Vector3 to, float width, Material material)
        {
            var go = Shape(name, PrimitiveType.Cube, p, (from + to) * .5f, new Vector3(width, Vector3.Distance(from, to), width), material);
            go.transform.localRotation = Quaternion.FromToRotation(Vector3.up, to - from);
        }
        GameObject Shape(string name, PrimitiveType kind, Transform parent, Vector3 at, Vector3 size, Material material, Vector3 rotation = default)
        {
            var go = GameObject.CreatePrimitive(kind); go.name = name; go.layer = Layer;
            go.transform.SetParent(parent, false); go.transform.localPosition = at; go.transform.localScale = size; go.transform.localRotation = Quaternion.Euler(rotation);
            var collider = go.GetComponent<Collider>(); if (collider != null) { collider.enabled = false; Kill(collider); }
            var renderer = go.GetComponent<Renderer>(); renderer.sharedMaterial = material;
            renderer.shadowCastingMode = ShadowCastingMode.On; renderer.receiveShadows = true;
            return go;
        }
        bool Prop(string name, Transform parent, Vector3 at, float height, float yaw)
        {
            if (!_props.TryGetValue(name, out var prefab)) return false;
            var go = Object.Instantiate(prefab, parent, false); go.name = name;
            go.transform.localPosition = at; go.transform.localRotation = Quaternion.Euler(0, yaw, 0); go.transform.localScale = Vector3.one * height;
            foreach (var transform in go.GetComponentsInChildren<Transform>(true)) transform.gameObject.layer = Layer;
            foreach (var collider in go.GetComponentsInChildren<Collider>(true)) { collider.enabled = false; Kill(collider); }
            foreach (var renderer in go.GetComponentsInChildren<Renderer>(true))
            {
                var materials = renderer.sharedMaterials;
                for (var i = 0; i < materials.Length; i++)
                {
                    var source = materials[i]; if (source == null) continue;
                    if (!_converted.TryGetValue(source, out var material))
                    {
                        material = Material(source.name + " camp instance", "FFFFFF");
                        if (source.HasProperty("_Color")) material.color = source.color;
                        if (source.HasProperty("_MainTex")) { material.mainTexture = source.mainTexture; material.mainTextureScale = source.mainTextureScale; material.mainTextureOffset = source.mainTextureOffset; }
                        _converted[source] = material;
                    }
                    materials[i] = material;
                }
                renderer.sharedMaterials = materials; renderer.shadowCastingMode = ShadowCastingMode.On; renderer.receiveShadows = true;
            }
            return true;
        }
        Material Material(string name, string hex)
        {
            ColorUtility.TryParseHtmlString("#" + hex, out var color);
            var material = new Material(_shader) { name = name, color = color, enableInstancing = true };
            if (material.HasProperty("_Glossiness")) material.SetFloat("_Glossiness", .05f);
            if (material.HasProperty("_Metallic")) material.SetFloat("_Metallic", 0);
            if (material.HasProperty("_OutlineWidth")) material.SetFloat("_OutlineWidth", 0);
            _materials.Add(material); return material;
        }
        static GameObject Child(string name, Transform parent)
        {
            var go = new GameObject(name) { layer = Layer }; go.transform.SetParent(parent, false); return go;
        }
        public void Dispose()
        {
            if (_disposed) return;
            SetVisible(false); _disposed = true;
            _camera.targetTexture = null; Texture.Release(); Kill(Texture); Texture = null;
            _root.SetActive(false); Kill(_root);
            foreach (var material in _materials) Kill(material);
            _materials.Clear(); _converted.Clear(); _props.Clear();
        }
        static void Kill(Object target) { if (Application.isPlaying) Object.Destroy(target); else Object.DestroyImmediate(target); }
    }
}
