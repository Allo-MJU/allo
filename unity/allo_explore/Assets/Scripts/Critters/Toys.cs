using UnityEngine;

namespace Allo.Critters
{
    /// 차 안 놀이에 쓰는 작은 물건. 기본 도형을 Allo/Toon 으로 칠해 장난감처럼 만든다.
    /// 모든 물건은 원점이 바닥 가운데이고, 크기는 실제 장난감 정도(m)다.
    public static class Toys
    {
        public enum Kind { Apple, Shell, Acorn, FishBun, Ball, Cup, Plush, Cushion, Blanket, Balloon, Egg, EggTop, EggBottom, Nest, Tissue, EggWrap, EggBit, Kite, Birds, Plane, Star, Whale }

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
            Kind.Tissue => "tissue",
            _ => "",
        };

        public static bool IsSnack(Kind k) => k is Kind.Apple or Kind.Shell or Kind.Acorn or Kind.FishBun;

        /// 3D 모델 프리팹 ID (Resources/Props/P_{ID}, scripts/import_props.sh). 프리팹이 있으면 도형 대신 쓴다
        static readonly System.Collections.Generic.Dictionary<Kind, string> PropIds = new()
        {
            [Kind.Apple] = "apple", [Kind.Shell] = "shell", [Kind.Acorn] = "acorn", [Kind.FishBun] = "fishbun",
            [Kind.Ball] = "ball", [Kind.Plush] = "plush", [Kind.Cushion] = "cushion", [Kind.Blanket] = "blanket",
            [Kind.Egg] = "egg", [Kind.EggTop] = "egg_top", [Kind.EggBottom] = "egg_bottom", [Kind.Nest] = "nest",
        };

        /// 프리팹 크기와 다르게 쓰는 것: 동행에게 건네는 작은 인형·쿠션 (프리팹은 차 안 옆자리 크기)
        static readonly System.Collections.Generic.Dictionary<Kind, float> PropHeight = new()
        {
            [Kind.Plush] = 0.13f, [Kind.Cushion] = 0.16f,
        };

        public static GameObject PropModel(string id) => string.IsNullOrEmpty(id) ? null : Resources.Load<GameObject>("Props/P_" + id);

        public static GameObject PropModel(Kind k) => PropIds.TryGetValue(k, out var id) ? PropModel(id) : null;

        public static Transform Make(Kind k)
        {
            var root = new GameObject("Toy_" + k).transform;
            // 알 담요(포대기)는 잘 때 담요 모델을 알 크기로 맞춰 덮는다: 알 아래 3/4 을 덮고 꼭대기는 담요 위로 나온다
            if (k == Kind.EggWrap && PropModel("blanket") is { } quilt)
            {
                var m = Object.Instantiate(quilt, root, false).transform;
                m.name = "Model";
                var b = BoundsOf(m);
                m.localScale = new Vector3(EggW * EggWrapWide / b.size.x, EggH * EggWrapHigh / b.size.y, EggW * EggWrapWide / b.size.z);
                return root;
            }
            var prefab = PropModel(k);
            if (prefab != null)
            {
                var m = Object.Instantiate(prefab, root, false).transform;
                m.name = "Model";
                if (PropHeight.TryGetValue(k, out var h))
                {
                    var b = BoundsOf(m);
                    m.localScale = Vector3.one * (h / Mathf.Max(0.001f, b.size.y));
                }
                // 담요: 도형 돔처럼 뒤(-z)로 조금 물려 얼굴 쪽을 남긴다
                if (k == Kind.Blanket) m.localPosition = new Vector3(0, 0, -CritterView.Height * 0.12f);
                return root;
            }
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
                    // 덮어 준 담요: 캐릭터 아랫몸을 감싼 낮은 돔 + 둘레 주름 단 + 크림색 점. 원점이 캐릭터 발 자리, +z 가 카메라 쪽.
                    // 돔은 뒤(-z)로 조금 물려 그림의 얼굴 쪽은 남기고, 높이는 몸의 2/5 까지만 — 머리와 등 잎이 담요 위로 나온다
                    var H = CritterView.Height;
                    var blue = new Color(0.55f, 0.75f, 0.95f);
                    var cream = new Color(0.98f, 0.95f, 0.85f);
                    var center = new Vector3(0, H * 0.06f, -H * 0.12f);
                    var dome = Part(root, PrimitiveType.Sphere, center, new Vector3(H * 1.2f, H * 0.5f, H * 0.95f), blue);
                    dome.name = "BlanketDome";
                    for (var i = 0; i < 10; i++)
                    {
                        var a = i * Mathf.PI * 2 / 10;
                        var hem = Part(root, PrimitiveType.Capsule, center + new Vector3(Mathf.Cos(a) * H * 0.56f, -H * 0.035f, Mathf.Sin(a) * H * 0.44f),
                            new Vector3(H * 0.15f, H * 0.08f, H * 0.15f), blue);
                        hem.localRotation = Quaternion.Euler(90, -a * Mathf.Rad2Deg, 0);
                    }
                    for (var i = 0; i < 6; i++)
                    {
                        var a = i * 2.4f + 0.7f; var u = 0.4f + (i % 3) * 0.2f; // 돔 윗면에 흩어진 점
                        var dir = new Vector3(Mathf.Cos(a) * (1 - u), u * 1.1f, Mathf.Sin(a) * (1 - u)).normalized;
                        var pos = center + Vector3.Scale(dir, new Vector3(H * 0.6f, H * 0.25f, H * 0.47f));
                        var dot = Part(root, PrimitiveType.Sphere, pos, new Vector3(H * 0.11f, H * 0.11f, H * 0.03f), cream);
                        dot.localRotation = Quaternion.LookRotation(dir);
                    }
                    break;
                }
                case Kind.Kite:
                {
                    // 마름모 연 + 꼬리 리본. 원점이 연 가운데
                    var red = new Color(1f, 0.45f, 0.4f); var yellow = new Color(1f, 0.85f, 0.3f);
                    var body = Part(root, PrimitiveType.Cube, Vector3.zero, new Vector3(1.2f, 1.2f, 0.05f), red);
                    body.localRotation = Quaternion.Euler(0, 0, 45);
                    Part(root, PrimitiveType.Cube, new Vector3(0, 0, -0.03f), new Vector3(0.85f, 0.06f, 0.02f), yellow).localRotation = Quaternion.Euler(0, 0, 45);
                    Part(root, PrimitiveType.Cube, new Vector3(0, 0, -0.03f), new Vector3(0.85f, 0.06f, 0.02f), yellow).localRotation = Quaternion.Euler(0, 0, -45);
                    for (var i = 0; i < 5; i++)
                    {
                        var bow = Part(root, PrimitiveType.Cube, new Vector3(0.15f * (i % 2 == 0 ? 1 : -1), -1.0f - i * 0.45f, 0), new Vector3(0.3f, 0.12f, 0.04f), i % 2 == 0 ? yellow : red);
                        bow.localRotation = Quaternion.Euler(0, 0, 20);
                    }
                    Part(root, PrimitiveType.Cylinder, new Vector3(0, -1.9f, 0), new Vector3(0.025f, 1.2f, 0.025f), Color.white);
                    break;
                }
                case Kind.Birds:
                {
                    // 새 떼: 브이(V) 자 세 마리. 날개는 "Wing" 이름으로 두고 밖에서 퍼덕인다
                    var ink = new Color(0.2f, 0.2f, 0.28f);
                    var offs = new[] { new Vector3(0, 0, 0), new Vector3(-1.1f, -0.25f, 0.4f), new Vector3(1.0f, -0.35f, -0.3f) };
                    foreach (var o in offs)
                    {
                        var l = Part(root, PrimitiveType.Cube, o + new Vector3(-0.3f, 0, 0), new Vector3(0.6f, 0.05f, 0.14f), ink);
                        l.name = "WingL"; l.localRotation = Quaternion.Euler(0, 0, 25);
                        var r = Part(root, PrimitiveType.Cube, o + new Vector3(0.3f, 0, 0), new Vector3(0.6f, 0.05f, 0.14f), ink);
                        r.name = "WingR"; r.localRotation = Quaternion.Euler(0, 0, -25);
                    }
                    break;
                }
                case Kind.Plane:
                {
                    // 작은 여객기: 동체 + 날개 + 꼬리. 원점이 동체 가운데, +x 가 앞
                    var white = new Color(0.96f, 0.97f, 1f); var blue = new Color(0.4f, 0.6f, 0.95f);
                    Part(root, PrimitiveType.Capsule, Vector3.zero, new Vector3(0.5f, 1.4f, 0.5f), white).localRotation = Quaternion.Euler(0, 0, 90);
                    Part(root, PrimitiveType.Cube, new Vector3(0.1f, 0, 0), new Vector3(0.6f, 0.05f, 2.4f), blue);
                    Part(root, PrimitiveType.Cube, new Vector3(-1.1f, 0.3f, 0), new Vector3(0.35f, 0.6f, 0.05f), blue);
                    Part(root, PrimitiveType.Cube, new Vector3(-1.1f, 0.05f, 0), new Vector3(0.35f, 0.04f, 1f), blue);
                    var light = Part(root, PrimitiveType.Sphere, new Vector3(0.1f, -0.1f, 1.2f), new Vector3(0.14f, 0.14f, 0.14f), new Color(1f, 0.3f, 0.3f));
                    light.name = "Blink";
                    break;
                }
                case Kind.Star:
                {
                    // 별똥별: 밝은 머리 + 꼬리 구슬 세 개 (-x 쪽으로). 원점이 머리
                    var glow = new Color(1f, 0.97f, 0.75f);
                    Part(root, PrimitiveType.Sphere, Vector3.zero, new Vector3(0.5f, 0.5f, 0.5f), Color.white);
                    for (var i = 1; i <= 4; i++)
                        Part(root, PrimitiveType.Sphere, new Vector3(-0.55f * i, 0.12f * i, 0), Vector3.one * (0.4f - i * 0.07f), glow);
                    break;
                }
                case Kind.Whale:
                {
                    // 고래: 짙은 파랑 몸통 + 흰 배 + 꼬리. 원점이 수면 (몸의 아래 1/3 이 물 아래)
                    var navy = new Color(0.25f, 0.4f, 0.7f); var belly = new Color(0.9f, 0.95f, 1f);
                    Part(root, PrimitiveType.Sphere, new Vector3(0, 0.2f, 0), new Vector3(3.2f, 1.4f, 1.6f), navy);
                    Part(root, PrimitiveType.Sphere, new Vector3(0.2f, -0.05f, 0), new Vector3(2.4f, 0.8f, 1.5f), belly);
                    var tail = Part(root, PrimitiveType.Cube, new Vector3(-1.9f, 0.5f, 0), new Vector3(0.7f, 0.12f, 1.3f), navy);
                    tail.name = "Tail";
                    Part(root, PrimitiveType.Sphere, new Vector3(1.0f, 0.75f, 0.45f), new Vector3(0.18f, 0.18f, 0.18f), Color.black);
                    var spout = Part(root, PrimitiveType.Sphere, new Vector3(0.6f, 1.0f, 0), new Vector3(0.1f, 0.1f, 0.1f), belly);
                    spout.name = "Spout";
                    break;
                }
                case Kind.Balloon:
                {
                    Part(root, PrimitiveType.Sphere, new Vector3(0, 1.6f, 0), new Vector3(1f, 1.2f, 1f), new Color(1f, 0.4f, 0.5f));
                    Part(root, PrimitiveType.Cylinder, new Vector3(0, 0.5f, 0), new Vector3(0.02f, 0.5f, 0.02f), Color.white);
                    Part(root, PrimitiveType.Sphere, new Vector3(0.9f, 2.1f, 0.2f), new Vector3(0.7f, 0.85f, 0.7f), new Color(1f, 0.85f, 0.3f));
                    break;
                }
                case Kind.Egg:
                {
                    // 알: 노란 껍데기(palette EGG) + 크림색 점. 원점이 바닥 가운데
                    var body = Part(root, PrimitiveType.Sphere, new Vector3(0, EggH / 2, 0), new Vector3(EggW, EggH, EggW), EggYellow);
                    body.name = "EggBody";
                    var spots = new[] { new Vector3(0.35f, 0.15f, 0.36f), new Vector3(-0.4f, 0.28f, 0.25f), new Vector3(0.05f, -0.1f, 0.48f),
                        new Vector3(-0.2f, 0.05f, -0.44f), new Vector3(0.42f, -0.05f, -0.2f), new Vector3(0.1f, 0.38f, -0.25f) };
                    foreach (var d in spots)
                    {
                        var spot = Part(body, PrimitiveType.Sphere, d.normalized * 0.48f, new Vector3(0.22f, 0.18f, 0.22f), EggSpot);
                        spot.localRotation = Quaternion.LookRotation(d.normalized);
                        spot.localScale = new Vector3(0.24f, 0.2f, 0.08f);
                    }
                    break;
                }
                case Kind.EggBottom:
                {
                    // 깨진 아래 껍데기: 납작한 반쪽 + 들쭉날쭉한 테두리
                    Part(root, PrimitiveType.Sphere, new Vector3(0, EggH * 0.2f, 0), new Vector3(EggW, EggH * 0.42f, EggW), EggYellow);
                    for (var i = 0; i < 9; i++)
                    {
                        var a = i * Mathf.PI * 2 / 9;
                        var tooth = Part(root, PrimitiveType.Cube, new Vector3(Mathf.Cos(a) * EggW * 0.43f, EggH * 0.4f, Mathf.Sin(a) * EggW * 0.43f),
                            new Vector3(EggW * 0.22f, EggW * 0.22f, EggW * 0.05f), EggYellow);
                        tooth.localRotation = Quaternion.Euler(0, -a * Mathf.Rad2Deg + 90, 45);
                    }
                    break;
                }
                case Kind.EggBit:
                {
                    // 깨질 때 튀는 껍데기 조각: 바깥은 노랑, 안쪽은 크림색
                    Part(root, PrimitiveType.Cube, Vector3.zero, new Vector3(EggW * 0.26f, EggW * 0.22f, EggW * 0.05f), EggYellow);
                    Part(root, PrimitiveType.Cube, new Vector3(0, 0, -EggW * 0.012f), new Vector3(EggW * 0.2f, EggW * 0.16f, EggW * 0.04f), EggSpot);
                    break;
                }
                case Kind.EggTop:
                {
                    // 깨진 윗 껍데기 (모자처럼 날아간다)
                    Part(root, PrimitiveType.Sphere, new Vector3(0, EggH * 0.08f, 0), new Vector3(EggW * 0.82f, EggH * 0.32f, EggW * 0.82f), EggYellow);
                    for (var i = 0; i < 7; i++)
                    {
                        var a = i * Mathf.PI * 2 / 7;
                        var tooth = Part(root, PrimitiveType.Cube, new Vector3(Mathf.Cos(a) * EggW * 0.36f, -EggH * 0.02f, Mathf.Sin(a) * EggW * 0.36f),
                            new Vector3(EggW * 0.2f, EggW * 0.2f, EggW * 0.05f), EggYellow);
                        tooth.localRotation = Quaternion.Euler(0, -a * Mathf.Rad2Deg + 90, 45);
                    }
                    break;
                }
                case Kind.Nest:
                {
                    // 둥지: 밑판 + 짚 고리 + 삐죽 나온 짚
                    var straw = new Color(0.86f, 0.68f, 0.38f);
                    var dark = new Color(0.66f, 0.47f, 0.24f);
                    Part(root, PrimitiveType.Cylinder, new Vector3(0, 0.008f, 0), new Vector3(0.15f, 0.008f, 0.15f), dark);
                    for (var i = 0; i < 14; i++)
                    {
                        var a = i * Mathf.PI * 2 / 14;
                        var twig = Part(root, PrimitiveType.Capsule, new Vector3(Mathf.Cos(a) * 0.072f, 0.022f, Mathf.Sin(a) * 0.072f),
                            new Vector3(0.026f, 0.034f, 0.026f), i % 2 == 0 ? straw : dark);
                        twig.localRotation = Quaternion.Euler(0, 90 - a * Mathf.Rad2Deg, 90); // 둥지 고리를 따라 눕힌다
                    }
                    for (var i = 0; i < 5; i++)
                    {
                        var a = i * 1.37f;
                        var stick = Part(root, PrimitiveType.Cylinder, new Vector3(Mathf.Cos(a) * 0.085f, 0.035f, Mathf.Sin(a) * 0.085f),
                            new Vector3(0.004f, 0.025f, 0.004f), straw);
                        stick.localRotation = Quaternion.Euler(Mathf.Sin(a) * 50, 0, Mathf.Cos(a) * 50);
                    }
                    break;
                }
                case Kind.EggWrap:
                {
                    // 알을 감싸는 포대기: 아래 2/3 을 덮고 꼭대기는 보인다. 알(원점 바닥 가운데)에 붙여 같이 흔들린다
                    var blue = new Color(0.55f, 0.75f, 0.95f);
                    var cream = new Color(0.98f, 0.95f, 0.85f);
                    Part(root, PrimitiveType.Sphere, new Vector3(0, EggH * 0.33f, 0), new Vector3(EggW * 1.12f, EggH * 0.78f, EggW * 1.12f), blue);
                    // 천 무늬: 겉면에 작은 크림색 점 (테두리처럼 튀어나오지 않게 겉면에 붙인다)
                    for (var i = 0; i < 10; i++)
                    {
                        var a = i * 2.4f;
                        var y = 0.12f + 0.42f * ((i * 0.37f) % 1f);
                        var r = Mathf.Sqrt(Mathf.Max(0, 1 - Mathf.Pow((y - 0.33f) / 0.39f, 2))) * EggW * 0.56f;
                        var dir = new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a));
                        var dot = Part(root, PrimitiveType.Sphere, dir * r + Vector3.up * (EggH * y), new Vector3(EggW * 0.13f, EggW * 0.13f, EggW * 0.04f), cream);
                        dot.localRotation = Quaternion.LookRotation(dir);
                    }
                    // 위쪽 접힌 단: 알 둘레를 따라 도톰하게
                    for (var i = 0; i < 12; i++)
                    {
                        var a = i * Mathf.PI * 2 / 12;
                        var hem = Part(root, PrimitiveType.Capsule, new Vector3(Mathf.Cos(a) * EggW * 0.5f, EggH * 0.68f, Mathf.Sin(a) * EggW * 0.5f),
                            new Vector3(EggW * 0.16f, EggW * 0.17f, EggW * 0.16f), blue);
                        hem.localRotation = Quaternion.Euler(0, 90 - a * Mathf.Rad2Deg, 90);
                    }
                    break;
                }
                case Kind.Tissue:
                {
                    var t = Part(root, PrimitiveType.Cube, Vector3.zero, new Vector3(0.12f, 0.003f, 0.1f), new Color(0.98f, 0.98f, 1f));
                    t.localRotation = Quaternion.Euler(0, 0, 8);
                    break;
                }
            }
            return root;
        }

        /// 알 담요 모델 크기: 알 폭의 배수, 알 키의 비율
        public const float EggWrapWide = 1.3f, EggWrapHigh = 0.75f;

        /// 알 크기 (m). 큰 알은 Unity 에서 1.25배로 키운다
        public const float EggW = 0.1f, EggH = 0.125f;
        static readonly Color EggYellow = new(0.99f, 0.8f, 0.27f);
        static readonly Color EggSpot = new(1f, 0.95f, 0.78f);

        /// 알에 금을 하나 더 긋는다 (step 0, 1, 2 …). 아이 쪽(+z)으로 지그재그
        public static void AddCrack(Transform egg, int step)
        {
            var dark = new Color(0.45f, 0.3f, 0.12f);
            var y0 = EggH * (0.55f + 0.08f * step);
            var side = step % 2 == 0 ? 1 : -1;
            for (var i = 0; i < 4; i++)
            {
                var ang = (step * 40 - 25 + i * 14) * Mathf.Deg2Rad;
                var p = new Vector3(Mathf.Sin(ang) * EggW * 0.5f, y0 + (i % 2 == 0 ? 0.008f : -0.008f) * side, Mathf.Cos(ang) * EggW * 0.5f);
                var seg = Part(egg, PrimitiveType.Cube, p, new Vector3(0.022f, 0.003f, 0.004f), dark);
                seg.name = "Crack";
                seg.localRotation = Quaternion.LookRotation(new Vector3(p.x, 0, p.z)) * Quaternion.Euler(0, 0, (i % 2 == 0 ? 35 : -35) * side);
            }
        }

        static Material _toon;
        static readonly System.Collections.Generic.Dictionary<Color, Material> _byColor = new();

        /// 색마다 재질 하나를 같이 쓴다 (장난감·껍데기·비눗방울을 만들 때마다 새로 만들면 쌓인다)
        static Material ToonFor(Color color)
        {
            if (_byColor.TryGetValue(color, out var m) && m != null) return m;
            if (_toon == null) _toon = new Material(Shader.Find("Allo/Toon"));
            m = new Material(_toon) { color = color };
            m.SetFloat("_OutlineWidth", 0.003f);
            m.SetFloat("_HiSize", 0.25f);
            _byColor[color] = m;
            return m;
        }

        static Transform Part(Transform parent, PrimitiveType t, Vector3 pos, Vector3 scale, Color color)
        {
            var go = GameObject.CreatePrimitive(t);
            Kill(go.GetComponent<Collider>());
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localScale = scale;
            var r = go.GetComponent<Renderer>();
            r.sharedMaterial = ToonFor(color);
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            return go.transform;
        }

        /// t 아래 렌더러를 모두 감싸는 상자 (월드)
        public static Bounds BoundsOf(Transform t)
        {
            var rs = t.GetComponentsInChildren<Renderer>();
            if (rs.Length == 0) return new Bounds(t.position, Vector3.zero);
            var b = rs[0].bounds;
            foreach (var r in rs) b.Encapsulate(r.bounds);
            return b;
        }

        static void Kill(Object o)
        {
            if (Application.isPlaying) Object.Destroy(o);
            else Object.DestroyImmediate(o);
        }
    }
}
