using UnityEngine;
using static Allo.World.Kit;

namespace Allo.World
{
    /// 장면별 도로 조각 하나를 만든다. 조각 안 좌표: z 0~L 앞쪽, +x 오른쪽, y 0 = 노면.
    /// 우리 차는 x=0 (오른쪽 차로 가운데), 왼쪽 x≈-3.5 가 마주 오는 차로다.
    public static class ChunkBuilder
    {
        public static readonly Color Asphalt = C("#55585C");
        static readonly Color Grass = C("#7DB04E"), GrassDark = C("#5A8C3C"), Sand = C("#EBD7A8"),
            Sea = C("#3B88B3"), Steel = C("#B9BEC0"), SteelDark = C("#7F888C"), White = C("#EDEDE6"),
            Yellow = C("#F2C14E"), Wood = C("#6A5A4C"), Walk = C("#C9C4B8"), Concrete = C("#A8A49A");

        static readonly string[] Walls = { "#F1E6CF", "#E7B98F", "#B9CDB0", "#DCCB8E", "#AFC2D2", "#D9A9A0", "#C9C9D6" };

        public static void Build(Kit k, Transform root, ChunkInfo c, float L, Material windows)
        {
            var r = new System.Random(c.index * 7919 + c.kind.GetHashCode());
            switch (c.kind)
            {
                case "tunnel": Tunnel(k, root, c, L); return;
                case "highway": Road(k, root, L, true); Highway(k, root, L, r); break;
                case "coast": Road(k, root, L, false); Coast(k, root, c, L, r); break;
                case "mountain": Road(k, root, L, false); Mountain(k, root, L, r); break;
                case "city": Road(k, root, L, false); City(k, root, c, L, r, windows); break;
                default: Road(k, root, L, false); Country(k, root, L, r); break;
            }
            if (c.exit) Portal(k, root, 0.5f, false);
        }

        static void Road(Kit k, Transform p, float L, bool highway)
        {
            var left = highway ? -9.4f : -5.4f;
            var right = highway ? 4.2f : 2.6f;
            k.Box(p, new Vector3((left + right) / 2, -0.1f, L / 2), new Vector3(right - left, 0.1f, L), Asphalt);
            k.Box(p, new Vector3(right - 0.45f, 0.0f, L / 2), new Vector3(0.14f, 0.01f, L), White);
            if (highway)
            {
                k.Box(p, new Vector3(left + 0.5f, 0, L / 2), new Vector3(0.14f, 0.01f, L), Yellow);
                for (var z = 2f; z < L; z += 15) k.Box(p, new Vector3(-1.75f, 0, z + 3), new Vector3(0.13f, 0.01f, 6), White);
                for (var z = 2f; z < L; z += 15) k.Box(p, new Vector3(-5.25f, 0, z + 3), new Vector3(0.13f, 0.01f, 6), White);
            }
            else
            {
                k.Box(p, new Vector3(-1.82f, 0, L / 2), new Vector3(0.1f, 0.01f, L), Yellow);
                k.Box(p, new Vector3(-1.62f, 0, L / 2), new Vector3(0.1f, 0.01f, L), Yellow);
                k.Box(p, new Vector3(left + 0.3f, 0, L / 2), new Vector3(0.12f, 0.01f, L), White);
            }
        }

        static void Ground(Kit k, Transform p, float L, float fromX, float toX, Color c, float y = -0.12f) =>
            k.Box(p, new Vector3((fromX + toX) / 2, y, L / 2), new Vector3(Mathf.Abs(toX - fromX), 0.1f, L), c);

        static void Rail(Kit k, Transform p, float L, float x)
        {
            for (var z = 0f; z < L; z += 4) k.Pole(p, new Vector3(x, 0, z), 0.06f, 0.75f, SteelDark);
            k.Box(p, new Vector3(x, 0.5f, L / 2), new Vector3(0.08f, 0.25f, L), Steel);
        }

        static void Country(Kit k, Transform p, float L, System.Random r)
        {
            Ground(k, p, L, -300, -5.4f, Grass);
            Ground(k, p, L, 2.6f, 300, Grass);
            // 밭 고랑: 색이 다른 긴 띠
            for (var x = 12f; x < 80; x += 7) Ground(k, p, L, x, x + 3, GrassDark, -0.07f);
            for (var i = 0; i < 4; i++)
            {
                var side = r.NextDouble() < 0.5 ? -1 : 1;
                var x = side < 0 ? Rand(r, -45, -8) : Rand(r, 5, 45);
                k.Tree(p, new Vector3(x, 0, Rand(r, 0, L)), Rand(r, 4, 8), r);
            }
            for (var i = 0; i < 3; i++) k.Prop("Bush", p, new Vector3(r.NextDouble() < 0.5 ? Rand(r, -30, -7) : Rand(r, 5, 30), 0, Rand(r, 0, L)), Rand(r, 0, 360), Rand(r, 0.7f, 1.3f));
            // 전봇대와 다음 전봇대로 이어지는 전선
            k.Pole(p, new Vector3(4.2f, 0, 0), 0.14f, 8, Wood);
            k.Box(p, new Vector3(4.2f, 7.5f, 0), new Vector3(1.6f, 0.12f, 0.12f), Wood);
            foreach (var dx in new[] { -0.7f, 0.7f })
            {
                var a = new Vector3(4.2f + dx, 7.6f, 0);
                var mid = new Vector3(4.2f + dx, 7.0f, L / 2);
                var b = new Vector3(4.2f + dx, 7.6f, L);
                k.Rod(p, a, mid, 0.015f, C("#333333"));
                k.Rod(p, mid, b, 0.015f, C("#333333"));
            }
            if (r.NextDouble() < 0.45) Farmhouse(k, p, new Vector3(r.NextDouble() < 0.5 ? Rand(r, -70, -25) : Rand(r, 25, 70), 0, Rand(r, 0, L)), r);
            if (r.NextDouble() < 0.4)
                for (var i = 0; i < 3; i++)
                    k.Ball(p, new Vector3(8 + i * 1.6f, 0.6f, Rand(r, 0, L)), new Vector3(1.2f, 1.2f, 1.2f), C("#F4F3EE"));
        }

        static void Farmhouse(Kit k, Transform p, Vector3 at, System.Random r)
        {
            if (k.Prop(r.NextDouble() < 0.6 ? "House_A" : "House_B", p, at, Rand(r, 0, 360), Rand(r, 0.9f, 1.3f)) != null)
            {
                if (r.NextDouble() < 0.7) k.Prop("Bush", p, at + new Vector3(Rand(r, 4, 6), 0, Rand(r, -3, 3)), Rand(r, 0, 360));
                return;
            }
            k.Box(p, at, new Vector3(8, 3, 6), C("#F1E6CF"));
            var roof = r.NextDouble() < 0.5 ? C("#B8634A") : C("#4A7FB0");
            k.Box(p, at + Vector3.up * 3.3f, new Vector3(8.6f, 0.5f, 4.6f), roof, Quaternion.Euler(0, 0, 0));
            k.Box(p, at + new Vector3(0, 3.0f, -1.5f), new Vector3(8.6f, 0.3f, 3.6f), roof, Quaternion.Euler(-28, 0, 0));
            k.Box(p, at + new Vector3(0, 3.0f, 1.5f), new Vector3(8.6f, 0.3f, 3.6f), roof, Quaternion.Euler(28, 0, 0));
        }

        static void Coast(Kit k, Transform p, ChunkInfo c, float L, System.Random r)
        {
            Ground(k, p, L, -300, -5.4f, Grass);
            Ground(k, p, L, 2.6f, 14, Sand, -0.15f);
            Ground(k, p, L, 14, 600, Sea, -0.4f);
            Rail(k, p, L, 2.4f);
            // 방파제 테트라포드
            for (var z = 1f; z < L; z += 2.4f) k.Ball(p, new Vector3(Rand(r, 9, 12), 0.2f, z), new Vector3(1.2f, 0.9f, 1.2f), Concrete);
            for (var i = 0; i < 3; i++) k.Tree(p, new Vector3(Rand(r, -30, -8), 0, Rand(r, 0, L)), Rand(r, 4, 7), r);
            if (r.NextDouble() < 0.35 && k.Prop("Sailboat", p, new Vector3(Rand(r, 40, 180), -0.4f, Rand(r, 0, L)), Rand(r, 0, 360), Rand(r, 1.2f, 2f)) != null) { }
            else if (r.NextDouble() < 0.35)
            {
                var at = new Vector3(Rand(r, 40, 180), -0.4f, Rand(r, 0, L));
                k.Box(p, at, new Vector3(1.6f, 0.6f, 4.5f), C("#5A4636"));
                k.Box(p, at + new Vector3(0, 0.6f, 0.3f), new Vector3(0.08f, 4.5f, 2.6f), White);
            }
            if (c.index % 9 == 4) k.Prop("Lighthouse", p, new Vector3(Rand(r, 60, 90), -0.4f, L / 2), 0, 1.4f);
            for (var i = 0; i < 2; i++) k.Prop("Bush", p, new Vector3(Rand(r, -20, -7), 0, Rand(r, 0, L)), Rand(r, 0, 360), Rand(r, 0.8f, 1.4f));
            // 반짝이는 물결
            for (var i = 0; i < 6; i++)
                k.Box(p, new Vector3(Rand(r, 16, 120), -0.33f, Rand(r, 0, L)), new Vector3(Rand(r, 1, 3), 0.01f, 0.15f), C("#BFE3F0"));
        }

        static void Mountain(Kit k, Transform p, float L, System.Random r)
        {
            Ground(k, p, L, -300, -5.4f, GrassDark);
            Ground(k, p, L, 2.6f, 300, GrassDark);
            Rail(k, p, L, 2.4f);
            for (var i = 0; i < 18; i++)
            {
                var side = i % 2 == 0 ? -1 : 1;
                var x = side < 0 ? Rand(r, -60, -7.5f) : Rand(r, 4.5f, 60);
                k.Pine(p, new Vector3(x, 0, Rand(r, 0, L)), Rand(r, 6, 13), r);
            }
            for (var i = 0; i < 3; i++)
            {
                var s = Rand(r, 0.8f, 2.4f);
                var at = new Vector3(r.NextDouble() < 0.5 ? Rand(r, -12, -6) : Rand(r, 4, 10), 0, Rand(r, 0, L));
                if (k.Prop("Rock", p, at, Rand(r, 0, 360), s) == null)
                    k.Ball(p, at + Vector3.up * 0.2f, new Vector3(s * 1.4f, s, s), C("#8C8A80"));
            }
        }

        static void City(Kit k, Transform p, ChunkInfo c, float L, System.Random r, Material windows)
        {
            Ground(k, p, L, -9.5f, -5.4f, Walk, -0.02f);
            Ground(k, p, L, 2.6f, 6.5f, Walk, -0.02f);
            Ground(k, p, L, -300, -9.5f, C("#9A9890"));
            Ground(k, p, L, 6.5f, 300, C("#9A9890"));
            var crossing = c.index % 4 == 0;
            // 건물: 길가 줄은 낮고 촘촘하게, 뒷줄은 높게 (스카이라인)
            foreach (var side in new[] { -1, 1 })
            {
                foreach (var (row, x0, depth, lo, hi) in new[] { (0, 10f, 9f, 6f, 20f), (1, 22f, 12f, 15f, 45f), (2, 38f, 16f, 25f, 75f) })
                {
                    var z = 0f;
                    while (z < L)
                    {
                        var w = Rand(r, 7, 13) + row * 2;
                        if (row == 0 && crossing && z < 12) { z = 12; continue; }
                        var h = Rand(r, lo, hi);
                        var x = side * (x0 + depth / 2);
                        var wall = C(Walls[r.Next(Walls.Length)]);
                        var go = k.Box(p, new Vector3(x, 0, z + w / 2), new Vector3(depth, h, w - 0.8f), wall);
                        // 창문: 건물 앞면에 붙인 얇은 판 (창문 무늬 재질)
                        var face = GameObject.CreatePrimitive(PrimitiveType.Quad);
                        Kill(face.GetComponent<Collider>());
                        face.transform.SetParent(p, false);
                        face.transform.localPosition = new Vector3(x - side * (depth / 2 + 0.02f), h / 2 + 1.5f, z + w / 2);
                        face.transform.localRotation = Quaternion.Euler(0, side < 0 ? 90 : -90, 0);
                        face.transform.localScale = new Vector3(w - 1.6f, h - 3.2f, 1);
                        var fr = face.GetComponent<Renderer>();
                        fr.sharedMaterial = windows;
                        fr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                        if (row == 0)
                        {
                            // 1층 가게 간판과 차양
                            var sign = C(new[] { "#E2614B", "#4A90D0", "#58D8A0", "#F2C14E", "#B487D8" }[r.Next(5)]);
                            k.Box(p, new Vector3(side * (x0 - 0.1f), 3.0f, z + w / 2), new Vector3(0.2f, 0.9f, w - 2), sign);
                            k.Box(p, new Vector3(side * (x0 - 0.6f), 2.5f, z + w / 2), new Vector3(1.2f, 0.12f, w - 2), sign);
                        }
                        z += w;
                    }
                }
                // 인도: 가로수·가로등·사람
                var walkX = side < 0 ? -7.4f : 4.6f;
                for (var z = 3f; z < L; z += 14)
                    if (!(crossing && z < 12)) k.Tree(p, new Vector3(walkX, 0, z), 5, r);
                if (k.Prop("StreetLamp", p, new Vector3(walkX - side * 0.6f, 0, L * 0.6f), side < 0 ? 90 : -90) == null)
                {
                    k.Pole(p, new Vector3(walkX + side * -0.8f, 0, L * 0.6f), 0.08f, 7, C("#7B8287"));
                    k.GlowBall(p, new Vector3(walkX - side * 0.2f, 7, L * 0.6f), 0.5f, C("#FFD98A"));
                }
                if (r.NextDouble() < 0.4) k.Prop("Bench", p, new Vector3(walkX + side * 1.2f, 0, Rand(r, 2, L - 2)), side < 0 ? 90 : -90);
                for (var i = 0; i < 4; i++)
                    if (r.NextDouble() < 0.6) k.Person(p, new Vector3(walkX + Rand(r, -1.2f, 1.2f), 0, Rand(r, 0, L)), r);
            }
            // 오른쪽 길가 주차 차
            for (var z = 4f; z < L - 4; z += 9)
                if (r.NextDouble() < 0.45 && !(crossing && z < 12))
                    k.Car(p, new Vector3(2.0f, 0, z), C(new[] { "#E9E4DA", "#7FA6C9", "#C8654F", "#59615E", "#F2C14E" }[r.Next(5)]), false, r.Next(9));
            if (crossing)
            {
                for (var x = -5f; x < 2.6f; x += 0.9f) k.Box(p, new Vector3(x + 0.25f, 0.005f, 6), new Vector3(0.5f, 0.01f, 3), White);
                foreach (var x in new[] { -6.2f, 3.4f })
                {
                    k.Pole(p, new Vector3(x, 0, 4), 0.08f, 4.2f, C("#5A5F63"));
                    k.Box(p, new Vector3(x, 4.2f, 4), new Vector3(0.4f, 1.2f, 0.4f), C("#2E2E2E"));
                    k.GlowBall(p, new Vector3(x, 4.9f, 3.78f), 0.22f, c.index % 8 == 0 ? C("#58D8A0") : C("#E2614B"));
                }
            }
        }

        static void Highway(Kit k, Transform p, float L, System.Random r)
        {
            Ground(k, p, L, -300, -9.4f, GrassDark);
            Ground(k, p, L, 4.2f, 300, Grass);
            k.Box(p, new Vector3(-9.6f, 0, L / 2), new Vector3(0.6f, 1.0f, L), Concrete);
            // 방음벽: 기둥 + 반투명 판 (판은 WorldDirector 가 유리 재질로 덮는다)
            for (var z = 0f; z < L; z += 5) k.Pole(p, new Vector3(4.6f, 0, z), 0.1f, 3.8f, SteelDark);
            var wall = k.Box(p, new Vector3(4.65f, 0, L / 2), new Vector3(0.05f, 3.6f, L), C("#B7D3D6"));
            wall.name = "SoundWall";
            for (var z = 5f; z < L; z += 40)
            {
                k.Pole(p, new Vector3(-9.4f, 0, z), 0.12f, 9, C("#7B8287"));
                k.Rod(p, new Vector3(-9.4f, 9, z), new Vector3(-7.4f, 9.2f, z), 0.07f, C("#7B8287"));
                k.GlowBall(p, new Vector3(-7.4f, 9.1f, z), 0.45f, C("#FFD98A"));
            }
            for (var i = 0; i < 3; i++) k.Tree(p, new Vector3(Rand(r, 10, 50), 0, Rand(r, 0, L)), Rand(r, 4, 8), r);
        }

        static void Tunnel(Kit k, Transform p, ChunkInfo c, float L)
        {
            var wall = C("#6B5E50");
            k.Box(p, new Vector3(-1.5f, -0.1f, L / 2), new Vector3(10, 0.1f, L), C("#3A3530"));
            k.Box(p, new Vector3(-6.6f, -0.1f, L / 2), new Vector3(0.4f, 6, L), wall);
            k.Box(p, new Vector3(3.6f, -0.1f, L / 2), new Vector3(0.4f, 6, L), wall);
            k.Box(p, new Vector3(-1.5f, 5.9f, L / 2), new Vector3(10.6f, 0.4f, L), C("#4A4036"));
            k.Box(p, new Vector3(-1.72f, 0, L / 2), new Vector3(0.12f, 0.01f, L), C("#D9C9A8"));
            // 벽 타일 이음매와 주황 나트륨등
            for (var z = 0f; z < L; z += 4)
            {
                k.Box(p, new Vector3(-6.38f, 0.5f, z), new Vector3(0.05f, 4.5f, 0.12f), C("#5A4E42"));
                k.Box(p, new Vector3(3.38f, 0.5f, z), new Vector3(0.05f, 4.5f, 0.12f), C("#5A4E42"));
            }
            for (var z = 2f; z < L; z += 8)
                foreach (var x in new[] { -4.2f, 1.2f })
                    k.GlowBox(p, new Vector3(x, 5.55f, z), new Vector3(0.4f, 0.12f, 2.4f), C("#FFB04A"));
            if (c.entrance) Portal(k, p, 0, true);
        }

        /// 터널 입구(산을 뚫은 콘크리트 벽)와 출구
        static void Portal(Kit k, Transform p, float z, bool entrance)
        {
            var concrete = C("#B0AA9E");
            k.Box(p, new Vector3(-12, -0.1f, z), new Vector3(11, 8, 1.2f), concrete);
            k.Box(p, new Vector3(9, -0.1f, z), new Vector3(11, 8, 1.2f), concrete);
            k.Box(p, new Vector3(-1.5f, 6.2f, z), new Vector3(14, 2, 1.2f), concrete);
            // 문 위를 덮은 산
            k.Ball(p, new Vector3(-1.5f, 8, z + (entrance ? 18 : -18)), new Vector3(80, 30, 40), C("#4E7F3A"));
        }
    }
}
