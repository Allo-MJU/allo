using UnityEngine;

namespace Allo.Critters
{
    /// 차 안 놀이에 쓰는 작은 물건. 기본 도형을 Allo/Toon 으로 칠해 장난감처럼 만든다.
    /// 모든 물건은 원점이 바닥 가운데이고, 크기는 실제 장난감 정도(m)다.
    public static class Toys
    {
        public enum Kind { Apple, Shell, Acorn, FishBun, Ball, Cup, Plush, Cushion, Blanket, Balloon }

        /// 장면에 맞는 간식: 바다는 조개, 산은 도토리, 도시는 붕어빵, 그 밖은 사과
        public static Kind SnackFor(string scene) => scene switch
        {
            "coast" => Kind.Shell,
            "mountain" => Kind.Acorn,
            "city" => Kind.FishBun,
            _ => Kind.Apple,
        };

        /// Flutter 에 보내는 먹이·놀이 종류 이름
        public static string Code(Kind k) => k switch
        {
            Kind.Apple => "apple",
            Kind.Shell => "shell",
            Kind.Acorn => "acorn",
            Kind.FishBun => "fishbun",
            Kind.Ball => "ball",
            Kind.Plush => "plush",
            Kind.Cushion => "cushion",
            Kind.Blanket => "blanket",
            _ => "",
        };

        public static bool IsSnack(Kind k) => k is Kind.Apple or Kind.Shell or Kind.Acorn or Kind.FishBun;

        public static Transform Make(Kind k)
        {
            var root = new GameObject("Toy_" + k).transform;
            switch (k)
            {
                case Kind.Apple:
                {
                    var body = Part(root, PrimitiveType.Sphere, new Vector3(0, 0.03f, 0), new Vector3(0.065f, 0.06f, 0.065f), new Color(0.9f, 0.25f, 0.2f));
                    Part(body, PrimitiveType.Cylinder, new Vector3(0, 0.55f, 0), new Vector3(0.08f, 0.16f, 0.08f), new Color(0.35f, 0.22f, 0.12f));
                    Part(body, PrimitiveType.Sphere, new Vector3(0.18f, 0.55f, 0), new Vector3(0.28f, 0.1f, 0.16f), new Color(0.35f, 0.7f, 0.3f));
                    break;
                }
                case Kind.Shell:
                {
                    // 부채꼴 조개: 납작한 반구 + 골
                    var c = new Color(1f, 0.72f, 0.66f);
                    Part(root, PrimitiveType.Sphere, new Vector3(0, 0.012f, 0), new Vector3(0.075f, 0.03f, 0.065f), c);
                    for (var i = -2; i <= 2; i++)
                    {
                        var rib = Part(root, PrimitiveType.Cube, new Vector3(i * 0.013f, 0.024f, 0.004f), new Vector3(0.004f, 0.006f, 0.05f), Color.Lerp(c, Color.white, 0.4f));
                        rib.localRotation = Quaternion.Euler(0, i * 14, 0);
                    }
                    Part(root, PrimitiveType.Cube, new Vector3(0, 0.01f, -0.032f), new Vector3(0.026f, 0.016f, 0.012f), Color.Lerp(c, Color.black, 0.15f));
                    break;
                }
                case Kind.Acorn:
                {
                    Part(root, PrimitiveType.Sphere, new Vector3(0, 0.03f, 0), new Vector3(0.045f, 0.058f, 0.045f), new Color(0.72f, 0.48f, 0.25f));
                    Part(root, PrimitiveType.Sphere, new Vector3(0, 0.055f, 0), new Vector3(0.052f, 0.03f, 0.052f), new Color(0.45f, 0.3f, 0.16f));
                    Part(root, PrimitiveType.Cylinder, new Vector3(0, 0.074f, 0), new Vector3(0.008f, 0.01f, 0.008f), new Color(0.35f, 0.22f, 0.12f));
                    break;
                }
                case Kind.FishBun:
                {
                    var gold = new Color(0.86f, 0.6f, 0.28f);
                    Part(root, PrimitiveType.Sphere, new Vector3(0, 0.022f, 0), new Vector3(0.1f, 0.04f, 0.05f), gold);
                    var tail = Part(root, PrimitiveType.Cube, new Vector3(-0.058f, 0.022f, 0), new Vector3(0.03f, 0.03f, 0.008f), gold);
                    tail.localRotation = Quaternion.Euler(0, 0, 45);
                    Part(root, PrimitiveType.Sphere, new Vector3(0.03f, 0.03f, 0.022f), Vector3.one * 0.008f, new Color(0.25f, 0.15f, 0.08f));
                    break;
                }
                case Kind.Ball:
                {
                    var b = Part(root, PrimitiveType.Sphere, new Vector3(0, 0.04f, 0), Vector3.one * 0.08f, new Color(0.25f, 0.55f, 0.95f));
                    Part(b, PrimitiveType.Cylinder, Vector3.zero, new Vector3(1.02f, 0.12f, 1.02f), new Color(1f, 0.85f, 0.25f));
                    break;
                }
                case Kind.Cup:
                {
                    Part(root, PrimitiveType.Cylinder, new Vector3(0, 0.025f, 0), new Vector3(0.05f, 0.025f, 0.05f), new Color(0.95f, 0.95f, 0.98f));
                    Part(root, PrimitiveType.Cylinder, new Vector3(0, 0.049f, 0), new Vector3(0.042f, 0.002f, 0.042f), new Color(0.45f, 0.75f, 0.95f));
                    break;
                }
                case Kind.Plush:
                {
                    var tan = new Color(0.85f, 0.62f, 0.42f);
                    var body = Part(root, PrimitiveType.Sphere, new Vector3(0, 0.04f, 0), new Vector3(0.07f, 0.08f, 0.065f), tan);
                    var head = Part(root, PrimitiveType.Sphere, new Vector3(0, 0.1f, 0), Vector3.one * 0.06f, tan);
                    Part(head, PrimitiveType.Sphere, new Vector3(-0.38f, 0.42f, 0), Vector3.one * 0.35f, new Color(0.6f, 0.4f, 0.26f));
                    Part(head, PrimitiveType.Sphere, new Vector3(0.38f, 0.42f, 0), Vector3.one * 0.35f, new Color(0.6f, 0.4f, 0.26f));
                    Part(head, PrimitiveType.Sphere, new Vector3(0, -0.05f, 0.42f), new Vector3(0.4f, 0.3f, 0.25f), new Color(0.95f, 0.85f, 0.72f));
                    break;
                }
                case Kind.Cushion:
                {
                    Part(root, PrimitiveType.Cube, new Vector3(0, 0.025f, 0), new Vector3(0.2f, 0.05f, 0.18f), new Color(0.95f, 0.55f, 0.6f));
                    Part(root, PrimitiveType.Sphere, new Vector3(0, 0.05f, 0), new Vector3(0.19f, 0.03f, 0.17f), new Color(0.98f, 0.62f, 0.66f));
                    break;
                }
                case Kind.Blanket:
                {
                    // 체크무늬 대신 두 색 띠
                    var a = new Color(0.55f, 0.75f, 0.95f);
                    var b = new Color(0.98f, 0.95f, 0.85f);
                    for (var i = 0; i < 4; i++)
                        Part(root, PrimitiveType.Cube, new Vector3(0, 0, -0.105f + i * 0.07f), new Vector3(0.3f, 0.012f, 0.07f), i % 2 == 0 ? a : b);
                    break;
                }
                case Kind.Balloon:
                {
                    Part(root, PrimitiveType.Sphere, new Vector3(0, 1.6f, 0), new Vector3(1f, 1.2f, 1f), new Color(1f, 0.4f, 0.5f));
                    Part(root, PrimitiveType.Cylinder, new Vector3(0, 0.5f, 0), new Vector3(0.02f, 0.5f, 0.02f), Color.white);
                    Part(root, PrimitiveType.Sphere, new Vector3(0.9f, 2.1f, 0.2f), new Vector3(0.7f, 0.85f, 0.7f), new Color(1f, 0.85f, 0.3f));
                    break;
                }
            }
            return root;
        }

        static Material _toon;

        static Transform Part(Transform parent, PrimitiveType t, Vector3 pos, Vector3 scale, Color color)
        {
            var go = GameObject.CreatePrimitive(t);
            Kill(go.GetComponent<Collider>());
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localScale = scale;
            var r = go.GetComponent<Renderer>();
            _toon ??= new Material(Shader.Find("Allo/Toon"));
            var m = new Material(_toon) { color = color };
            m.SetFloat("_OutlineWidth", 0.003f);
            m.SetFloat("_HiSize", 0.25f);
            r.sharedMaterial = m;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            return go.transform;
        }

        static void Kill(Object o)
        {
            if (Application.isPlaying) Object.Destroy(o);
            else Object.DestroyImmediate(o);
        }
    }
}
