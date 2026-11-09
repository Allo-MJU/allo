using System.Collections.Generic;
using UnityEngine;

namespace Allo.World
{
    /// 창밖 물체를 기본 도형으로 빠르게 만든다. 같은 색은 재질 하나를 같이 써서 묶어 그린다(배칭).
    public sealed class Kit
    {
        readonly Material _solid, _glow;
        readonly Dictionary<Color, Material> _solids = new();
        readonly Dictionary<Color, Material> _glows = new();

        readonly Dictionary<string, GameObject> _props = new();
        Material _ground;
        readonly Dictionary<Color, Material> _grounds = new();

        /// 땅 재질: 풀·모래 무늬를 월드 좌표로 깐다 (넓은 판에 늘어나지 않게)
        public void SetGround(Material ground) => _ground = ground;

        public GameObject GroundBox(Transform p, Vector3 bottomCenter, Vector3 size, Color c)
        {
            var go = Box(p, bottomCenter, size, c);
            if (_ground == null) return go;
            if (!_grounds.TryGetValue(c, out var m))
            {
                m = new Material(_ground) { color = c };
                _grounds[c] = m;
            }
            go.GetComponent<Renderer>().sharedMaterial = m;
            return go;
        }

        public Kit(Material solid, Material glow, IEnumerable<GameObject> props = null)
        {
            _solid = solid;
            _glow = glow;
            if (props != null)
                foreach (var p in props)
                    if (p != null) _props[p.name] = p;
        }

        public bool Has(string prop) => _props.ContainsKey(prop);

        /// Blender 로 만든 물체(Props.fbx)를 놓는다. 없으면 null (기본 도형으로 대신 그린다)
        public GameObject Prop(string name, Transform p, Vector3 at, float yaw = 0, float scale = 1)
        {
            if (!_props.TryGetValue(name, out var src)) return null;
            var go = Object.Instantiate(src, p, false);
            go.transform.localPosition = at;
            go.transform.localRotation = Quaternion.Euler(0, yaw, 0);
            go.transform.localScale = Vector3.one * scale;
            foreach (var r in go.GetComponentsInChildren<Renderer>())
            {
                r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                r.receiveShadows = false;
            }
            return go;
        }

        public static Color C(string hex) => ColorUtility.TryParseHtmlString(hex, out var c) ? c : Color.magenta;

        public Material Solid(Color c)
        {
            if (_solids.TryGetValue(c, out var m)) return m;
            m = new Material(_solid) { color = c, enableInstancing = true };
            _solids[c] = m;
            return m;
        }

        /// 스스로 빛나는 재질 (창문 불빛·가로등·터널 등). 밤에 세기를 올린다
        public Material Glow(Color c)
        {
            if (_glows.TryGetValue(c, out var m)) return m;
            m = new Material(_glow) { color = c * 0.6f };
            m.EnableKeyword("_EMISSION");
            m.SetColor("_EmissionColor", c);
            _glows[c] = m;
            return m;
        }

        public IEnumerable<Material> Glows => _glows.Values;

        public static void Kill(Object o)
        {
            if (o == null) return;
            if (Application.isPlaying) Object.Destroy(o);
            else Object.DestroyImmediate(o);
        }

        GameObject Prim(PrimitiveType t, Transform parent, Vector3 pos, Vector3 scale, Material m, Quaternion? rot = null)
        {
            var go = GameObject.CreatePrimitive(t);
            Kill(go.GetComponent<Collider>());
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = rot ?? Quaternion.identity;
            go.transform.localScale = scale;
            var r = go.GetComponent<Renderer>();
            r.sharedMaterial = m;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            return go;
        }

        /// 바닥이 y 에 닿는 상자. center 는 (x, 바닥 y, z)
        public GameObject Box(Transform p, Vector3 bottomCenter, Vector3 size, Color c, Quaternion? rot = null) =>
            Prim(PrimitiveType.Cube, p, bottomCenter + Vector3.up * size.y / 2, size, Solid(c), rot);

        public GameObject GlowBox(Transform p, Vector3 bottomCenter, Vector3 size, Color c) =>
            Prim(PrimitiveType.Cube, p, bottomCenter + Vector3.up * size.y / 2, size, Glow(c));

        public GameObject Ball(Transform p, Vector3 center, Vector3 size, Color c) =>
            Prim(PrimitiveType.Sphere, p, center, size, Solid(c));

        public GameObject GlowBall(Transform p, Vector3 center, float d, Color c) =>
            Prim(PrimitiveType.Sphere, p, center, Vector3.one * d, Glow(c));

        /// 바닥에 선 원기둥 (Unity 원기둥은 높이 2 가 기본이라 반으로 줄인다)
        public GameObject Pole(Transform p, Vector3 bottom, float radius, float height, Color c) =>
            Prim(PrimitiveType.Cylinder, p, bottom + Vector3.up * height / 2, new Vector3(radius * 2, height / 2, radius * 2), Solid(c));

        /// 두 점을 잇는 가는 막대 (전선·레일)
        public GameObject Rod(Transform p, Vector3 a, Vector3 b, float radius, Color c)
        {
            var d = b - a;
            return Prim(PrimitiveType.Cylinder, p, (a + b) / 2, new Vector3(radius * 2, d.magnitude / 2, radius * 2), Solid(c),
                Quaternion.FromToRotation(Vector3.up, d.normalized));
        }

        /// 건물 앞면 창문 판. 창 칸 크기가 건물 크기와 상관없이 일정하도록 UV 를 칸 수로 늘린다
        /// (재질 텍스처 한 장 = 가로 4 × 세로 4 칸). center 는 판 가운데, rot 은 판이 바라보는 방향.
        /// 메시 이름 "Facade" 는 조각을 합칠 때(WorldDirector.Combine) 같이 지운다
        public GameObject Facade(Transform p, Vector3 center, Quaternion rot, float w, float h, Material m, float cellW = 2.2f, float cellH = 2.9f)
        {
            var go = new GameObject("Facade");
            go.transform.SetParent(p, false);
            go.transform.localPosition = center;
            go.transform.localRotation = rot;
            var mesh = new Mesh { name = "Facade" };
            float hw = w / 2, hh = h / 2;
            mesh.vertices = new[] { new Vector3(-hw, -hh, 0), new Vector3(hw, -hh, 0), new Vector3(-hw, hh, 0), new Vector3(hw, hh, 0) };
            var u = Mathf.Max(0.25f, Mathf.Round(w / cellW) / 4f);
            var v = Mathf.Max(0.25f, Mathf.Round(h / cellH) / 4f);
            mesh.uv = new[] { new Vector2(0, 0), new Vector2(u, 0), new Vector2(0, v), new Vector2(u, v) };
            mesh.normals = new[] { -Vector3.forward, -Vector3.forward, -Vector3.forward, -Vector3.forward };
            mesh.triangles = new[] { 0, 2, 1, 2, 3, 1 };
            mesh.RecalculateBounds();
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterial = m;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            return go;
        }

        /// 잎이 뭉친 활엽수
        public void Tree(Transform p, Vector3 at, float h, System.Random r)
        {
            if (Prop("Tree_Round", p, at, Rand(r, 0, 360), h / 5f * Rand(r, 0.85f, 1.15f)) != null) return;
            Pole(p, at, h * 0.05f, h * 0.45f, C("#5B4434"));
            var dark = C("#355F3A");
            var lit = C("#6E9E4C");
            for (var k = 0; k < 4; k++)
            {
                var o = new Vector3(Rand(r, -0.2f, 0.2f) * h, h * (0.6f + Rand(r, 0, 0.2f)), Rand(r, -0.2f, 0.2f) * h);
                var s = h * Rand(r, 0.38f, 0.52f);
                Ball(p, at + o, new Vector3(s, s * 0.9f, s), k == 3 ? lit : dark);
            }
        }

        /// 산에 많은 바늘잎 나무
        public void Pine(Transform p, Vector3 at, float h, System.Random r)
        {
            if (Prop("Tree_Pine", p, at, Rand(r, 0, 360), h / 5.5f) != null) return;
            Pole(p, at, h * 0.04f, h * 0.3f, C("#4A3628"));
            var c = Color.Lerp(C("#2F5233"), C("#3E6B3A"), (float)r.NextDouble());
            for (var k = 0; k < 3; k++)
            {
                var w = h * (0.5f - k * 0.13f);
                Prim(PrimitiveType.Capsule, p, at + Vector3.up * (h * (0.4f + k * 0.2f)), new Vector3(w, h * 0.22f, w), Solid(c));
            }
        }

        /// 차 앞이 +z(우리와 같은 방향)를 보게 놓는다. 마주 오는 차는 부모를 180도 돌린다
        public void Car(Transform p, Vector3 at, Color body, bool lights, int seed = 0)
        {
            if (Prop(seed % 3 == 0 ? "Car_SUV" : "Car_Sedan", p, at, CarYaw) != null) return;
            Box(p, at + Vector3.up * 0.25f, new Vector3(1.8f, 0.7f, 4.2f), body);
            Box(p, at + new Vector3(0, 0.95f, -0.2f), new Vector3(1.6f, 0.55f, 2.2f), C("#3B4650"));
            foreach (var x in new[] { -0.75f, 0.75f })
            foreach (var z in new[] { -1.35f, 1.35f })
                Prim(PrimitiveType.Cylinder, p, at + new Vector3(x, 0.33f, z), new Vector3(0.66f, 0.12f, 0.66f), Solid(C("#1C1C1C")),
                    Quaternion.Euler(0, 0, 90));
            if (!lights) return;
            foreach (var x in new[] { -0.6f, 0.6f })
            {
                GlowBox(p, at + new Vector3(x, 0.65f, -2.12f), new Vector3(0.35f, 0.15f, 0.05f), C("#FFF4D6"));
                GlowBox(p, at + new Vector3(x, 0.65f, 2.12f), new Vector3(0.35f, 0.15f, 0.05f), C("#E2463A"));
            }
        }

        /// 길 가는 사람: 다리·신발·몸통·팔·머리·머리카락, 가끔 묶은 머리·모자·치마·가방. 아이는 작다.
        /// 기본 도형 12개 안팎이라 조각 메시에 합쳐도 가볍다
        public void Person(Transform p, Vector3 at, System.Random r)
        {
            var shirt = C(new[] { "#E2614B", "#4A90D0", "#F2C14E", "#58D8A0", "#F1E6CF", "#B487D8", "#FF8FB8", "#3F7D5A" }[r.Next(8)]);
            var pants = C(new[] { "#3B4A5C", "#2E3440", "#6B5B4A", "#8A6A4C", "#5A6B8C" }[r.Next(5)]);
            var skin = C(new[] { "#F1C7A5", "#E0A97E", "#C68A5E", "#8D5A3B" }[r.Next(4)]);
            var hair = C(new[] { "#2B2320", "#4A2E1E", "#7A4A2A", "#D9A066", "#8C8C8C", "#C8654F" }[r.Next(6)]);
            var kid = r.NextDouble() < 0.22;
            var h = kid ? Rand(r, 1.0f, 1.2f) : Rand(r, 1.6f, 1.85f);
            var s = h / 1.75f;
            var g = new GameObject("Person").transform;
            g.SetParent(p, false);
            g.localPosition = at;
            g.localRotation = Quaternion.Euler(0, Rand(r, 0, 360), 0);
            var skirt = !kid && r.NextDouble() < 0.3;
            foreach (var x in new[] { -0.09f, 0.09f })
            {
                Pole(g, new Vector3(x * s, 0, 0), 0.065f * s, h * 0.46f, skirt ? skin : pants);
                Box(g, new Vector3(x * s, 0, 0.03f * s), new Vector3(0.11f, 0.06f, 0.24f) * s, C("#2E2A28"));
            }
            if (skirt) Prim(PrimitiveType.Cylinder, g, new Vector3(0, h * 0.42f, 0), new Vector3(0.46f * s, h * 0.07f, 0.4f * s), Solid(pants));
            // 몸통·팔 (캡슐은 기본 높이 2)
            Prim(PrimitiveType.Capsule, g, new Vector3(0, h * 0.63f, 0), new Vector3(0.4f * s, h * 0.17f, 0.26f * s), Solid(shirt));
            foreach (var x in new[] { -0.25f, 0.25f })
            {
                Prim(PrimitiveType.Capsule, g, new Vector3(x * s, h * 0.6f, 0), new Vector3(0.1f * s, h * 0.14f, 0.1f * s), Solid(shirt), Quaternion.Euler(0, 0, x < 0 ? 8 : -8));
                Ball(g, new Vector3(x * 1.05f * s, h * 0.46f, 0), Vector3.one * 0.09f * s, skin);
            }
            var headY = h * 0.9f;
            Ball(g, new Vector3(0, headY, 0), Vector3.one * 0.25f * s, skin);
            Ball(g, new Vector3(0, headY + 0.035f * s, -0.02f * s), new Vector3(0.27f, 0.2f, 0.27f) * s, hair);
            var style = r.NextDouble();
            if (style < 0.25) Ball(g, new Vector3(0, headY - 0.02f * s, -0.14f * s), new Vector3(0.1f, 0.18f, 0.1f) * s, hair);
            else if (style < 0.45)
            {
                Prim(PrimitiveType.Cylinder, g, new Vector3(0, headY + 0.1f * s, 0), new Vector3(0.36f * s, 0.01f * s, 0.36f * s), Solid(shirt));
                Prim(PrimitiveType.Cylinder, g, new Vector3(0, headY + 0.14f * s, 0), new Vector3(0.24f * s, 0.05f * s, 0.24f * s), Solid(shirt));
            }
            if (!kid && r.NextDouble() < 0.35)
                Box(g, new Vector3(0.27f * s, h * 0.42f, 0), new Vector3(0.08f, 0.22f, 0.18f) * s, C(new[] { "#6B4A35", "#2E3440", "#C8654F" }[r.Next(3)]));
        }

        /// Blender 차는 -Y 가 앞이다. FBX 를 Unity 로 옮긴 뒤 앞이 +z 가 되도록 돌리는 각도 (캡처로 확인)
        public static float CarYaw = 180;

        public static float Rand(System.Random r, float a, float b) => a + (float)r.NextDouble() * (b - a);
    }
}
