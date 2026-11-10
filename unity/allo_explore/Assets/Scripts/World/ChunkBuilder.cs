using System.Collections.Generic;
using UnityEngine;
using static Allo.World.Kit;

namespace Allo.World
{
    /// 장면별 도로 조각 하나를 만든다. 조각 안 좌표: z 0~L 앞쪽, +x 오른쪽, y 0 = 노면.
    /// 우리 차는 x=0 (오른쪽 차로 가운데), 왼쪽 x≈-3.5 가 마주 오는 차로다.
    public static class ChunkBuilder
    {
        public static readonly Color Asphalt = C("#55585C");
        static readonly Color Grass = C("#6CB847"), GrassDark = C("#549E3A"), Sand = C("#F4E2B0"),
            Sea = C("#2F9BD6"), Steel = C("#B9BEC0"), SteelDark = C("#7F888C"), White = C("#EDEDE6"),
            Yellow = C("#F2C14E"), Wood = C("#6A5A4C"), Walk = C("#C9C4B8"), Concrete = C("#A8A49A");

        static readonly string[] Walls = { "#F1E6CF", "#E7B98F", "#B9CDB0", "#DCCB8E", "#AFC2D2", "#D9A9A0", "#C9C9D6" };

        /// 조각 하나를 짓는다. 유턴 뒤 되짚는 조각은 지나온 조각(seed)과 똑같이 지어진다.
        /// trimLeft·trimRight 면 그쪽 길가 풍경을 짓지 않는다 (회전 안쪽 모서리에서 지나온 조각과 겹치지 않게)
        public static void Build(Kit k, Transform root, ChunkInfo c, float L, Material windows, bool trimLeft = false, bool trimRight = false)
        {
            if (c.turn != null) { Junction(k, root, c, windows); return; }
            Scene(k, root, View(c, c.seed), L, windows);
            Trim(root, trimLeft, trimRight);
            if (c.clearEnd) ClearPast(root, L);
            if (Mathf.Abs(c.bend) > 0.01f) Bend(root, c.bend, L);
        }

        /// 곧게 지은 조각을 호 모양으로 휜다. 긴 상자(아스팔트·땅 띠·차선·난간·방음벽)는 3m 토막으로 나눈 뒤,
        /// 물체마다 길 방향 위치 z 의 호 위 자리로 옮기고 그 자리 방향만큼 돌린다 (건물은 모양 그대로 옮겨진다)
        static void Bend(Transform p, float bend, float L)
        {
            var r = Mathf.Abs(L / (bend * Mathf.Deg2Rad));
            var inner = bend > 0 ? 1 : -1; // 휘는 쪽(안쪽)
            var limit = r * 0.8f;          // 안쪽 땅 띠가 곡률 중심을 넘어 접히지 않게
            foreach (var t in new List<Transform>(Children(p)))
            {
                var mf = t.GetComponent<MeshFilter>();
                if (mf == null || mf.sharedMesh == null || mf.sharedMesh.name != "Cube" || Quaternion.Angle(t.localRotation, Quaternion.identity) > 1) continue;
                var sc = t.localScale;
                var pos = t.localPosition;
                // 안쪽으로 너무 넓은 상자는 곡률 중심 앞에서 자른다
                var x0 = pos.x - sc.x / 2;
                var x1 = pos.x + sc.x / 2;
                if (inner > 0 && x1 > limit) x1 = Mathf.Max(x0 + 0.1f, limit);
                if (inner < 0 && x0 < -limit) x0 = Mathf.Min(x1 - 0.1f, -limit);
                sc.x = x1 - x0;
                pos.x = (x0 + x1) / 2;
                if (sc.z <= 3.5f) { t.localScale = sc; t.localPosition = pos; continue; }
                var n = Mathf.CeilToInt(sc.z / 3f);
                var piece = sc.z / n;
                var z0 = pos.z - sc.z / 2;
                for (var i = 0; i < n; i++)
                {
                    var g = Object.Instantiate(t.gameObject, p, false);
                    g.name = t.name;
                    g.transform.localScale = new Vector3(sc.x, sc.y, piece + 0.02f);
                    g.transform.localPosition = new Vector3(pos.x, pos.y, z0 + piece * (i + 0.5f));
                }
                Remove(t.gameObject);
            }
            foreach (var t in Children(p))
            {
                if (!t.gameObject.activeSelf) continue;
                var lp = t.localPosition;
                var pose = ChunkTrack.LocalPose(null, lp.z, L, bend);
                t.localPosition = pose.pos + pose.Rot * new Vector3(lp.x, 0, 0) + Vector3.up * lp.y;
                t.localRotation = pose.Rot * t.localRotation;
            }
        }

        static IEnumerable<Transform> Children(Transform p)
        {
            for (var i = 0; i < p.childCount; i++) yield return p.GetChild(i);
        }

        /// 길가 물체 중 zMax 를 넘어 뻗는 것을 지운다 (교차로 가로 도로 위에 건물이 걸치지 않게)
        static void ClearPast(Transform p, float zMax)
        {
            for (var i = p.childCount - 1; i >= 0; i--)
            {
                var t = p.GetChild(i);
                var x = t.localPosition.x;
                if (x <= 3.0f && x >= -5.8f) continue; // 도로 위 표시·땅 띠 가운데 등은 둔다
                if (t.name.StartsWith("Cube") && t.localScale.x > 50) continue; // 땅 띠
                foreach (var r in t.GetComponentsInChildren<Renderer>())
                {
                    var b = r.bounds;
                    var far = float.NegativeInfinity;
                    for (var k = 0; k < 8; k++)
                    {
                        var corner = new Vector3((k & 1) == 0 ? b.min.x : b.max.x, (k & 2) == 0 ? b.min.y : b.max.y, (k & 4) == 0 ? b.min.z : b.max.z);
                        far = Mathf.Max(far, p.InverseTransformPoint(corner).z);
                    }
                    if (far > zMax + 0.3f) { Remove(t.gameObject); break; }
                }
            }
        }

        static ChunkInfo View(ChunkInfo c, int index) => new() { index = index, kind = c.kind, entrance = c.entrance, exit = c.exit };

        static void Scene(Kit k, Transform root, ChunkInfo c, float L, Material windows)
        {
            var r = new System.Random(c.index * 7919 + c.kind.GetHashCode());
            switch (c.kind)
            {
                case "tunnel": Tunnel(k, root, c, L); return;
                case "highway": Road(k, root, L, true, r); Highway(k, root, L, r); break;
                case "coast": Road(k, root, L, false, r); Coast(k, root, c, L, r); break;
                case "mountain": Road(k, root, L, false, r); Mountain(k, root, c, L, r); break;
                case "city": Road(k, root, L, false, r); City(k, root, c, L, r, windows); break;
                default: Road(k, root, L, false, r); Country(k, root, c, L, r); break;
            }
            if (c.exit) Portal(k, root, 0.5f, false);
            Wildlife(k, root, c, L);
        }

        /// 장면별로 가끔 보이는 동물. 기존 배치 난수와 따로 굴려서 다른 물체 자리가 바뀌지 않게 한다
        static void Wildlife(Kit k, Transform p, ChunkInfo c, float L)
        {
            var r = new System.Random(c.index * 3571 + 11);
            var side = r.NextDouble() < 0.5 ? -1 : 1;
            switch (c.kind)
            {
                case "mountain":
                    if (r.NextDouble() < 0.45) Herd(k, p, L, r, "A_Deer", r.Next(2, 4), side > 0 ? 6 : -14, side > 0 ? 14 : -7);
                    break;
                case "city":
                    if (r.NextDouble() < 0.45) Herd(k, p, L, r, r.NextDouble() < 0.5 ? "A_Dog" : "A_Kitty", r.Next(1, 3), 3.6f, 5.8f);
                    break;
                case "coast":
                    if (r.NextDouble() < 0.3) Herd(k, p, L, r, "A_Dog", r.Next(1, 3), 4, 9);
                    break;
            }
        }

        /// 도로 밖 한쪽 풍경(땅 띠 포함)을 지운다. 바로 아래 자식의 위치로 판단한다
        static void Trim(Transform p, bool left, bool right)
        {
            if (!left && !right) return;
            for (var i = p.childCount - 1; i >= 0; i--)
            {
                var t = p.GetChild(i);
                var x = t.localPosition.x;
                if (right && x > 3.0f || left && x < -5.8f) Remove(t.gameObject);
            }
        }

        static Transform Sub(Transform p, string name, Vector3 at)
        {
            var t = new GameObject(name).transform;
            t.SetParent(p, false);
            t.localPosition = at;
            return t;
        }

        // ───────── 도로 영역 ─────────

        /// 조각이 차지하는 도로 영역들 (조각 로컬 직사각형: xMin, xMax, zMin, zMax). 길가 물체가 이 안에 들어오면 안 된다.
        /// 교차로는 다가가는 길·가로 도로·직진 길까지 포함한다
        public static List<(Pose2 at, Vector4 rect)> RoadRects(ChunkInfo c, float L)
        {
            const float m = 0.6f; // 도로 가장자리 여유
            var id = new Pose2(Vector3.zero, 0);
            var list = new List<(Pose2, Vector4)>();
            var (left, right) = c.kind == "highway" ? (-9.4f, 4.2f) : (-5.4f, 2.6f);
            if (c.turn == null)
            {
                // 휜 조각은 세 토막으로 나눠 어림한다
                var n = Mathf.Abs(c.bend) > 0.01f ? 3 : 1;
                for (var i = 0; i < n; i++)
                    list.Add((ChunkTrack.LocalPose(null, L * i / n, L, c.bend), new Vector4(left - m, right + m, 0, L / n)));
                return list;
            }
            if (c.turn == "uturn") { list.Add((id, new Vector4(left - m, right + m, 0, TurnShape.UturnLen + 60))); return list; }
            var rt = c.turn == "right";
            var (near, far) = TurnShape.CrossEdges(c.turn);
            var exitX = TurnShape.ExitX(c.turn);
            var x0 = Mathf.Min(rt ? -60f : -5.4f, exitX);
            var x1 = Mathf.Max(rt ? 2.6f : 60f, exitX);
            list.Add((id, new Vector4(left - m, right + m, 0, near)));
            list.Add((id, new Vector4(x0, x1, near - m, far + m)));
            list.Add((id, new Vector4(left - m, right + m, far, far + 60)));
            if (TurnShape.Apron(c.turn) is Vector4 ap) list.Add((id, new Vector4(ap.x - m, ap.y + m, ap.z, ap.w)));
            return list;
        }

        // ───────── 교차로 · 유턴 ─────────

        /// 좌·우회전 교차로와 유턴 조각. 조각 로컬: 들어올 때 +z, 우리 차로 x=0, 도로 x -5.4~2.6.
        /// 회전 전에 앞이 끊겨 보이지 않게 직진 길 60m 를 더 짓는다 (회전 쪽 풍경은 회전한 뒤 길과 겹치므로 뺀다)
        static void Junction(Kit k, Transform p, ChunkInfo c, Material windows)
        {
            var r = new System.Random(c.seed * 7919 + 17);
            var city = c.kind == "city";
            if (c.turn == "uturn")
            {
                var u = Sub(p, "Approach", Vector3.zero);
                Scene(k, u, View(c, c.seed), TurnShape.UturnLen, windows);
                var g = Sub(p, "Ahead", new Vector3(0, 0, TurnShape.UturnLen));
                Scene(k, g, View(c, c.seed + 1), 30, windows);
                var g2 = Sub(p, "Ahead2", new Vector3(0, 0, TurnShape.UturnLen + 30));
                Scene(k, g2, View(c, c.seed + 2), 30, windows);
                // 유턴 표시: 노면 화살표 대신 노란 중앙선이 끊기고 표지판이 선다
                k.Box(p, new Vector3(-1.72f, 0.004f, 5), new Vector3(0.5f, 0.012f, 9.6f), Asphalt);
                for (var z = 1f; z < 9.5f; z += 2) k.Box(p, new Vector3(-1.72f, 0.006f, z), new Vector3(0.12f, 0.012f, 1f), White);
                k.Pole(p, new Vector3(-5.9f, 0, 4), 0.05f, 2.6f, SteelDark);
                k.Box(p, new Vector3(-5.9f, 2.2f, 4), new Vector3(0.06f, 0.6f, 0.6f), C("#2F6FC4"));
                k.Box(p, new Vector3(-5.86f, 2.35f, 4), new Vector3(0.02f, 0.3f, 0.12f), White);
                return;
            }
            var right = c.turn == "right";
            var side = right ? 1 : -1;
            var zc = TurnShape.LaneZ(c.turn);                   // 회전한 뒤 차로가 지나는 z
            var (near, far) = TurnShape.CrossEdges(c.turn);     // 가로 도로의 가까운·먼 가장자리
            var exitX = TurnShape.ExitX(c.turn);
            // 다가가는 길 (회전 쪽 풍경은 짓지 않는다)
            var a = Sub(p, "Approach", Vector3.zero);
            Scene(k, a, View(c, c.seed), near, windows);
            Trim(a, !right, right);
            ClearPast(a, near);
            // 교차로와 가로 도로 (회전 반대쪽으로 60m 이어진다)
            var stubFrom = right ? -60f : -5.4f;
            var stubTo = right ? 2.6f : 60f;
            var x0 = Mathf.Min(stubFrom, exitX);
            var x1 = Mathf.Max(stubTo, exitX);
            k.GroundBox(p, new Vector3((x0 + x1) / 2, -0.1f, (near + far) / 2), new Vector3(x1 - x0, 0.1f, far - near), Asphalt);
            // 회전 안쪽 모서리 포장: 천천히 도는 동안 차가 지나는 자리
            var apron = TurnShape.Apron(c.turn);
            if (apron != null)
            {
                // 차가 지나는 곡선을 따라 폭 7m 띠로 포장한다 (둥근 모서리처럼 보인다)
                var len = TurnShape.Length(c.turn);
                for (var s = 0f; s < len; s += 1.2f)
                {
                    var pose = TurnShape.Pose(c.turn, s);
                    var off = right ? pose.pos.x > 2.0f : pose.pos.x < -5.0f;
                    if (!off || pose.pos.z > near + 0.5f) continue;
                    var g = k.GroundBox(p, pose.pos + pose.Right * -0.3f + Vector3.down * 0.1f, new Vector3(7f, 0.1f, 1.6f), Asphalt);
                    g.transform.localRotation = pose.Rot;
                }
            }
            if (city)
            {
                // 모서리 인도 (회전 쪽은 포장 앞에서 끊는다)
                var turnWalk = apron is Vector4 ap2 ? Mathf.Max(0.5f, ap2.z) : near;
                k.GroundBox(p, new Vector3(right ? 4.6f : -7.5f, -0.02f, turnWalk / 2), new Vector3(3.9f, 0.1f, turnWalk), Walk);
                k.GroundBox(p, new Vector3(right ? -7.5f : 4.6f, -0.02f, near / 2), new Vector3(3.9f, 0.1f, near), Walk);
            }
            // 가로 도로 중앙선
            // 가로 도로의 중앙선(차로 기준 x'=-1.72)은 교차로 밖 반대쪽 구간에만 긋는다
            var midZ = right ? zc + 1.72f : zc - 1.72f;
            var (m0, m1) = right ? (-60f, -5.4f) : (2.6f, 60f);
            k.Box(p, new Vector3((m0 + m1) / 2, 0, midZ - 0.05f), new Vector3(m1 - m0, 0.01f, 0.1f), Yellow);
            // 정지선·횡단보도 (우리 길, 그리고 회전해 들어갈 길)
            k.Box(p, new Vector3(-1.4f + 2.0f, 0.004f, near - 3.0f), new Vector3(4.0f, 0.012f, 0.35f), White);
            for (var x = -5.0f; x < 2.4f; x += 1.0f) k.Box(p, new Vector3(x + 0.25f, 0.004f, near - 1.6f), new Vector3(0.5f, 0.012f, 2.2f), White);
            for (var z = near + 0.4f; z < far - 0.2f; z += 1.0f) k.Box(p, new Vector3(right ? 4.6f : -7.4f, 0.004f, z + 0.25f), new Vector3(2.2f, 0.012f, 0.5f), White);
            // 신호등: 건너편 모서리에서 우리 쪽을 본다
            var lx = right ? -6.2f : 3.4f;
            k.Pole(p, new Vector3(lx, 0, far + 0.6f), 0.08f, 4.6f, SteelDark);
            k.Rod(p, new Vector3(lx, 4.5f, far + 0.6f), new Vector3(-1.4f, 4.6f, far + 0.6f), 0.06f, SteelDark);
            k.Box(p, new Vector3(-1.4f, 4.1f, far + 0.6f), new Vector3(1.2f, 0.42f, 0.3f), C("#2E3236"));
            k.GlowBall(p, new Vector3(-1.4f + 0.38f, 4.32f, far + 0.43f), 0.24f, C("#58D8A0"));
            // 교차로 너머 직진 길 (회전 쪽 풍경은 회전한 뒤 길과 겹치므로 뺀다)
            for (var i = 0; i < 2; i++)
            {
                var g = Sub(p, $"Ahead{i}", new Vector3(0, 0, far + i * 30));
                Scene(k, g, View(c, c.seed + 1 + i), 30, windows);
                Trim(g, !right, right);
            }
            // 회전 반대쪽 모서리 풍경: 덤불·나무 몇 그루
            for (var i = 0; i < 6; i++)
            {
                var x = right ? -Rand(r, 7, 30) : Rand(r, 4, 30);
                var z = Rand(r, 0, near - 0.5f);
                if (city) Bush(k, p, new Vector3(right ? -Rand(r, 10, 12) : Rand(r, 7, 9), 0, z), r);
                else k.Tree(p, new Vector3(x, 0, z), Rand(r, 4, 7), r);
            }
        }

        /// 길가 풀 덤불과 들꽃: 길 양옆 띠에 빽빽하게, 멀어질수록 드물게
        static void Verge(Kit k, Transform p, float L, System.Random r, float left, float right, float density = 1)
        {
            if (!k.Has("GrassTuft")) return;
            var n = (int)(26 * density);
            for (var i = 0; i < n; i++)
            {
                var side = i % 2 == 0 ? -1 : 1;
                var d = Mathf.Pow((float)r.NextDouble(), 2) * 14;
                var x = side < 0 ? left - 0.6f - d : right + 0.6f + d;
                var at = new Vector3(x, 0, Rand(r, 0, L));
                var pick = r.NextDouble();
                if (pick < 0.12 && k.Any(r, Flowers, p, at, Rand(r, 0.25f, 0.45f)) != null) continue;
                if (pick < 0.24) k.Prop("Flowers", p, at, Rand(r, 0, 360), Rand(r, 0.9f, 1.4f));
                else k.Prop("GrassTuft", p, at, Rand(r, 0, 360), Rand(r, 0.8f, 1.6f));
            }
        }

        static void Road(Kit k, Transform p, float L, bool highway, System.Random r)
        {
            var left = highway ? -9.4f : -5.4f;
            var right = highway ? 4.2f : 2.6f;
            k.GroundBox(p, new Vector3((left + right) / 2, -0.1f, L / 2), new Vector3(right - left, 0.1f, L), Asphalt);
            // 노면 디테일: 보수 자국·맨홀·이음매. 차와 함께 흘러가 달리는 느낌을 준다
            for (var i = 0; i < 2; i++)
                if (r.NextDouble() < 0.7)
                    k.Box(p, new Vector3(Rand(r, left + 1, right - 1), 0.002f, Rand(r, 1, L - 1)), new Vector3(Rand(r, 0.8f, 2.2f), 0.01f, Rand(r, 1.5f, 4f)), C("#4A4D51"));
            if (r.NextDouble() < 0.5)
                k.Pole(p, new Vector3(Rand(r, -1.2f, 1.6f), 0.0f, Rand(r, 2, L - 2)), 0.32f, 0.012f, C("#3E4044"));
            k.Box(p, new Vector3((left + right) / 2, 0.002f, Rand(r, 3, L - 3)), new Vector3(right - left, 0.01f, 0.08f), C("#45484C"));
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
            k.GroundBox(p, new Vector3((fromX + toX) / 2, y, L / 2), new Vector3(Mathf.Abs(toX - fromX), 0.1f, L), c);

        static void Rail(Kit k, Transform p, float L, float x)
        {
            for (var z = 0f; z < L; z += 4) k.Pole(p, new Vector3(x, 0, z), 0.06f, 0.75f, SteelDark);
            k.Box(p, new Vector3(x, 0.5f, L / 2), new Vector3(0.08f, 0.25f, L), Steel);
        }

        // ───────── 공통 ─────────

        /// 조각 여러 개(blockLen 조각)에 걸쳐 같은 배치를 이어 가기 위한 난수. 밭·숲·마을이 조각 경계에서 끊기지 않게 한다
        static System.Random Block(ChunkInfo c, int chunksPerBlock, int salt) =>
            new System.Random((c.index / chunksPerBlock) * 104729 + salt * 31 + c.kind.GetHashCode());

        /// 숲 덩어리: 가운데 큰 나무, 둘레에 작은 나무·덤불. 가장자리에 그루터기·버섯
        static void Grove(Kit k, Transform p, Vector3 at, float radius, int trees, string[] kinds, float hLo, float hHi, System.Random r)
        {
            for (var i = 0; i < trees; i++)
            {
                var a = Rand(r, 0, Mathf.PI * 2);
                var d = Mathf.Sqrt((float)r.NextDouble()) * radius;
                var pos = at + new Vector3(Mathf.Cos(a) * d, 0, Mathf.Sin(a) * d);
                var h = Mathf.Lerp(hHi, hLo, d / radius) * Rand(r, 0.85f, 1.15f);
                if (k.Any(r, r.NextDouble() < 0.12 ? FallTrees : kinds, p, pos, h) == null) k.Tree(p, pos, h, r);
            }
            for (var i = 0; i < trees / 2 + 1; i++)
            {
                var a = Rand(r, 0, Mathf.PI * 2);
                var pos = at + new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)) * (radius + Rand(r, 0, 2.5f));
                if (r.NextDouble() < 0.6) Bush(k, p, pos, r);
                else k.Any(r, Shrubs, p, pos, Rand(r, 0.6f, 1.2f));
            }
            if (r.NextDouble() < 0.5) k.Any(r, WoodBits, p, at + new Vector3(Rand(r, -1, 1), 0, Rand(r, -1, 1)) * (radius + 1.5f), Rand(r, 0.5f, 1.0f));
            if (r.NextDouble() < 0.4) k.Any(r, Flowers, p, at + new Vector3(radius + 1, 0, Rand(r, -2, 2)), Rand(r, 0.3f, 0.5f));
        }

        /// 길가 가까운 띠(창 높이로 보이는 곳): 덤불·키 큰 풀·꽃·작은 바위
        static void NearVerge(Kit k, Transform p, float L, System.Random r, float x0, float x1, int n)
        {
            for (var i = 0; i < n; i++)
            {
                var at = new Vector3(Rand(r, x0, x1), 0, Rand(r, 0, L));
                var pick = r.NextDouble();
                if (pick < 0.35) Bush(k, p, at, r);
                else if (pick < 0.7) k.Any(r, Shrubs, p, at, Rand(r, 0.6f, 1.3f));
                else if (pick < 0.88) k.Any(r, Flowers, p, at, Rand(r, 0.3f, 0.5f));
                else k.Any(r, SmallRocks, p, at, Rand(r, 0.3f, 0.7f));
            }
        }

        /// 밭: 흙 판 위에 작물 줄. 길과 나란한 줄이라 달리면 줄이 흘러간다
        static void Field(Kit k, Transform p, float L, float x0, float x1, int kind, System.Random r)
        {
            var dirt = kind == 3 ? C("#7FAE4E") : C("#A07A52");
            Ground(k, p, L, x0, x1, dirt, -0.07f);
            if (kind == 3) // 꽃밭
            {
                for (var i = 0; i < 40; i++) k.Any(r, Flowers, p, new Vector3(Rand(r, x0, x1), 0, Rand(r, 0, L)), Rand(r, 0.35f, 0.6f));
                return;
            }
            var crops = kind == 0 ? Corn : kind == 1 ? Wheat : Greens;
            var h = kind == 0 ? 2.0f : kind == 1 ? 1.0f : 0.5f;
            var rowGap = kind == 0 ? 2.2f : 1.8f;
            for (var x = x0 + 0.8f; x < x1 - 0.5f; x += rowGap)
            for (var z = Rand(r, 0, 1.5f); z < L; z += Rand(r, 1.6f, 2.4f))
            {
                if (kind == 2 && r.NextDouble() < 0.12) k.Any(r, Gourds, p, new Vector3(x, 0, z), 0.6f);
                else k.Any(r, crops, p, new Vector3(x + Rand(r, -0.2f, 0.2f), 0, z), h * Rand(r, 0.85f, 1.15f));
            }
        }

        /// 길과 나란한 나무 울타리 (Kenney fence_simple 조각을 이어 붙인다)
        static void FenceLine(Kit k, Transform p, float L, float x, System.Random r, float height = 0.9f)
        {
            if (!k.Has("K_fence_simple")) return;
            for (var z = 0f; z < L; z += 2f)
                k.Prop("K_fence_simple", p, new Vector3(x, 0, z + 1), FenceYaw, height);
        }

        /// Kenney fence_simple 이 길(z)과 나란하게 되는 각도 (캡처로 확인)
        public static float FenceYaw = 90;

        // ───────── 시골길 ─────────

        static void Country(Kit k, Transform p, ChunkInfo c, float L, System.Random r)
        {
            Ground(k, p, L, -300, -5.4f, Grass);
            Ground(k, p, L, 2.6f, 300, Grass);
            Verge(k, p, L, r, -5.4f, 2.6f, 1.2f);
            NearVerge(k, p, L, r, 3.4f, 7f, 7);
            NearVerge(k, p, L, r, -10f, -6.2f, 5);
            // 오른쪽: 밭 (90m 단위로 종류가 바뀐다) + 밭 앞 울타리
            var b = Block(c, 3, 1);
            var fieldKind = b.Next(4);
            var hasField = b.NextDouble() < 0.45; // 나머지는 목장 (동물이 창 가까이 보이게)
            if (hasField)
            {
                FenceLine(k, p, L, 8.2f, r);
                Field(k, p, L, 9.5f, 9.5f + Rand(b, 14, 22), fieldKind, r);
            }
            else
            {
                // 목장: 길가 낮은 울타리 바로 너머에서 풀을 뜯는 소·양·말 (90m 동안 같은 종). 창 높이에서 잘 보이게 6~12m
                FenceLine(k, p, L, 5.2f, r, 0.6f); // 낮은 울타리: 뒷좌석 눈높이에서 동물이 가리지 않게
                var kind = k.Pick(b, Pasture);
                Herd(k, p, L, r, kind, r.Next(4, 8), 6.2f, 12f);
                // 조금 뒤쪽에 다른 종 몇 마리
                Herd(k, p, L, r, k.Pick(r, Pasture), r.Next(1, 3), 12f, 18f);
                Grove(k, p, new Vector3(Rand(r, 24, 34), 0, Rand(r, 5, L - 5)), Rand(r, 4, 6), r.Next(5, 9), RoundTrees, 4, 8, r);
            }
            // 밭이어도 가끔 왼쪽 길가 풀밭에 동물 몇 마리
            if (hasField && r.NextDouble() < 0.35) Herd(k, p, L, r, k.Pick(r, Pasture), r.Next(2, 4), -12f, -7f);
            // 왼쪽: 숲 덩어리·외딴 나무·마을
            var lb = Block(c, 2, 2);
            var village = k.Has(Houses[0]) && lb.NextDouble() < 0.35;
            if (village)
            {
                for (var z = Rand(r, 0, 5); z < L - 3; z += Rand(r, 12, 16))
                    House(k, p, new Vector3(-Rand(r, 15, 18), 0, z), 90, r);
                // 마당의 닭과 강아지
                if (r.NextDouble() < 0.6) Herd(k, p, L, r, "A_Chicken", r.Next(2, 4), -12, -9);
                if (r.NextDouble() < 0.3) Herd(k, p, L, r, r.NextDouble() < 0.5 ? "A_Dog" : "A_Pug", 1, -10, -8);
            }
            else if (r.NextDouble() < 0.7)
                Grove(k, p, new Vector3(-Rand(r, 16, 30), 0, Rand(r, 4, L - 4)), Rand(r, 4, 7), r.Next(6, 11), RoundTrees, 4, 9, r);
            for (var i = 0; i < 2; i++) k.Tree(p, new Vector3(-Rand(r, 20, 28), 0, Rand(r, 0, L)), Rand(r, 4, 7), r);
            // 먼 숲 띠: 언덕 앞을 채워 지평선이 비지 않게
            for (var i = 0; i < 6; i++)
            {
                var side = i % 2 == 0 ? -1 : 1;
                k.Tree(p, new Vector3(side * Rand(r, 45, 90), 0, Rand(r, 0, L)), Rand(r, 7, 12), r);
            }
            if (r.NextDouble() < 0.35) Farmhouse(k, p, new Vector3(r.NextDouble() < 0.5 ? Rand(r, -70, -40) : Rand(r, 40, 70), 0, Rand(r, 0, L)), r);
            // 전봇대와 전선
            k.Pole(p, new Vector3(4.2f, 0, 0), 0.14f, 8, Wood);
            k.Box(p, new Vector3(4.2f, 7.5f, 0), new Vector3(1.6f, 0.12f, 0.12f), Wood);
            foreach (var dx in new[] { -0.7f, 0.7f })
            {
                var a = new Vector3(4.2f + dx, 7.6f, 0);
                var mid = new Vector3(4.2f + dx, 7.0f, L / 2);
                var e = new Vector3(4.2f + dx, 7.6f, L);
                k.Rod(p, a, mid, 0.015f, C("#333333"));
                k.Rod(p, mid, e, 0.015f, C("#333333"));
            }
        }

        /// 목장에 풀어 두는 동물 (A_ 프리팹: 실제 높이, 서 있기·풀 뜯기 애니메이션)
        static readonly string[] Pasture = { "A_Cow", "A_Sheep", "A_Horse", "A_Pig", "A_Llama", "A_Cow", "A_Sheep" };

        /// 동물 n 마리를 x 범위(길 가운데 기준, 음수는 왼쪽)에 흩어 놓는다. 서로 다른 동작 시점에서 시작한다
        static void Herd(Kit k, Transform p, float L, System.Random r, string animal, int n, float xLo, float xHi)
        {
            if (animal == null || !k.Has(animal)) return;
            for (var i = 0; i < n; i++)
            {
                var go = k.Prop(animal, p, new Vector3(Rand(r, xLo, xHi), 0, Rand(r, 2, L - 2)), Rand(r, 0, 360), Rand(r, 0.9f, 1.1f));
                if (go == null) continue;
                go.name = "Animal_" + animal;
                var a = go.GetComponentInChildren<Animator>();
                if (a != null && Application.isPlaying)
                {
                    a.speed = Rand(r, 0.8f, 1.2f);
                    a.Play(0, 0, (float)r.NextDouble());
                }
            }
        }

        static void Farmhouse(Kit k, Transform p, Vector3 at, System.Random r)
        {
            if (House(k, p, at, Rand(r, 0, 360), r)) return;
            k.Prop(r.NextDouble() < 0.6 ? "House_A" : "House_B", p, at, Rand(r, 0, 360), Rand(r, 0.9f, 1.3f));
        }

        /// Kenney 교외 집 한 채와 마당(울타리·덤불·나무·장작). yaw 는 집 앞이 보는 방향. 집 에셋이 없으면 false
        static bool House(Kit k, Transform p, Vector3 at, float yaw, System.Random r)
        {
            if (k.Any(r, Houses, p, at, Rand(r, 6.5f, 8.5f), yaw + Rand(r, -4, 4)) == null) return false;
            var front = Quaternion.Euler(0, yaw, 0);
            // 마당 앞 낮은 나무 울타리 (0.8m). 교외 팩의 주황 울타리는 창 앞에서 너무 커 보여 쓰지 않는다
            if (r.NextDouble() < 0.7 && k.Has("K_fence_simple"))
                for (var i = -2; i <= 2; i++)
                    k.Prop("K_fence_simple", p, at + front * new Vector3(i * 1.6f, 0, 5.5f), yaw + FenceYaw - 90, 0.8f);
            for (var i = 0; i < 3; i++)
                if (r.NextDouble() < 0.7) Bush(k, p, at + front * new Vector3(Rand(r, -5, 5), 0, Rand(r, 4, 7)), r);
            if (r.NextDouble() < 0.7) k.Any(r, RoundTrees, p, at + front * new Vector3(Rand(r, 6, 8) * (r.NextDouble() < 0.5 ? -1 : 1), 0, Rand(r, -2, 3)), Rand(r, 5, 8));
            if (r.NextDouble() < 0.4) k.Any(r, WoodBits, p, at + front * new Vector3(Rand(r, -6, 6), 0, Rand(r, -4, 0)), Rand(r, 0.8f, 1.2f));
            return true;
        }

        static void Bush(Kit k, Transform p, Vector3 at, System.Random r)
        {
            if (k.Any(r, Bushes, p, at, Rand(r, 0.8f, 1.6f)) == null) k.Prop("Bush", p, at, Rand(r, 0, 360), Rand(r, 0.7f, 1.3f));
        }

        // ───────── 해안 ─────────

        static void Coast(Kit k, Transform p, ChunkInfo c, float L, System.Random r)
        {
            Ground(k, p, L, -300, -5.4f, Grass);
            Ground(k, p, L, 2.6f, 16, Sand, -0.15f);
            Ground(k, p, L, 16, 600, Sea, -0.4f);
            Verge(k, p, L, r, -5.4f, 900, 0.6f);
            Rail(k, p, L, 2.4f);
            // 모래밭 가장자리: 해안 풀과 작은 바위
            for (var i = 0; i < 6; i++) k.Any(r, Shrubs, p, new Vector3(Rand(r, 3.2f, 5.5f), -0.15f, Rand(r, 0, L)), Rand(r, 0.5f, 1.0f));
            // 야자수 무리 (60m 마다 자리가 이어진다)
            var b = Block(c, 2, 3);
            var palmZ = Rand(b, 0, L);
            // 모래밭은 낮은 것만 (창 높이 너머로 잘리지 않게): 해안 풀 덤불·작은 바위
            for (var i = 0; i < 4; i++) k.Any(r, Shrubs, p, new Vector3(Rand(r, 6, 12), -0.15f, palmZ + Rand(r, -8, 8)), Rand(r, 0.5f, 0.9f));
            for (var i = 0; i < 2; i++) k.Any(r, SmallRocks, p, new Vector3(Rand(r, 6, 13), -0.15f, Rand(r, 0, L)), Rand(r, 0.3f, 0.6f));
            // 파라솔과 카누 (해수욕장)
            if (b.NextDouble() < 0.6)
                for (var z = Rand(r, 2, 6); z < L; z += Rand(r, 6, 10))
                {
                    k.Any(r, Parasols, p, new Vector3(Rand(r, 9, 13), -0.15f, z), 2.4f);
                    if (r.NextDouble() < 0.3) k.Prop("K_canoe", p, new Vector3(Rand(r, 12, 14.5f), -0.15f, z + 2), Rand(r, 60, 120), 0.5f);
                }
            // 물가 바위
            for (var i = 0; i < 4; i++) k.Any(r, r.NextDouble() < 0.6 ? LowRocks : SmallRocks, p, new Vector3(Rand(r, 13.5f, 17), -0.3f, Rand(r, 0, L)), Rand(r, 0.6f, 1.4f));
            // 왼쪽(뭍): 야자수·나무 덩어리·바닷가 집
            var lb = Block(c, 3, 4);
            if (k.Has(Houses[0]) && lb.NextDouble() < 0.3)
                for (var z = Rand(r, 0, 6); z < L - 3; z += Rand(r, 13, 17)) House(k, p, new Vector3(-Rand(r, 15, 18), 0, z), 90, r);
            else
                Grove(k, p, new Vector3(-Rand(r, 14, 26), 0, Rand(r, 4, L - 4)), Rand(r, 4, 6), r.Next(5, 9), r.NextDouble() < 0.5 ? Palms : RoundTrees, 5, 8, r);
            NearVerge(k, p, L, r, -10f, -6.2f, 5);
            if (r.NextDouble() < 0.35) k.Prop("Sailboat", p, new Vector3(Rand(r, 40, 180), -0.4f, Rand(r, 0, L)), Rand(r, 0, 360), Rand(r, 1.2f, 2f));
            if (c.index % 9 == 4) k.Prop("Lighthouse", p, new Vector3(Rand(r, 60, 90), -0.4f, L / 2), 0, 1.4f);
            for (var i = 0; i < 6; i++)
                k.Box(p, new Vector3(Rand(r, 18, 120), -0.33f, Rand(r, 0, L)), new Vector3(Rand(r, 1, 3), 0.01f, 0.15f), C("#BFE3F0"));
        }

        // ───────── 산길 ─────────

        static void Mountain(Kit k, Transform p, ChunkInfo c, float L, System.Random r)
        {
            Ground(k, p, L, -300, -5.4f, GrassDark);
            Ground(k, p, L, 2.6f, 300, GrassDark);
            Rail(k, p, L, 2.4f);
            Verge(k, p, L, r, -5.4f, 4.5f, 1.0f);
            // 왼쪽: 깎아지른 바위 절벽 (90m 단위로 절벽/숲이 바뀐다)
            var b = Block(c, 3, 5);
            if (b.NextDouble() < 0.6 && k.Has(Cliffs[0]))
            {
                for (var z = 0f; z < L; z += Rand(r, 4.5f, 6.5f))
                    k.Any(r, Cliffs, p, new Vector3(-Rand(r, 9.5f, 11), -0.2f, z), Rand(r, 6, 11), r.Next(4) * 90);
                for (var i = 0; i < 6; i++) k.Any(r, SmallPines, p, new Vector3(-Rand(r, 7, 9), 0, Rand(r, 0, L)), Rand(r, 2, 3.5f));
                for (var i = 0; i < 3; i++) k.Any(r, SmallRocks, p, new Vector3(-Rand(r, 6.5f, 8.5f), 0, Rand(r, 0, L)), Rand(r, 0.4f, 0.9f));
                for (var i = 0; i < 6; i++) k.Pine(p, new Vector3(-Rand(r, 16, 40), Rand(r, 4, 9), Rand(r, 0, L)), Rand(r, 7, 12), r);
            }
            else
            {
                for (var i = 0; i < 10; i++) k.Pine(p, new Vector3(-Rand(r, 7.5f, 50), 0, Rand(r, 0, L)), Rand(r, 6, 13), r);
                NearVerge(k, p, L, r, -10f, -6.2f, 5);
            }
            // 오른쪽: 겹겹이 선 숲. 가까운 곳은 어린 나무·덤불, 멀수록 큰 나무
            for (var i = 0; i < 8; i++) k.Any(r, SmallPines, p, new Vector3(Rand(r, 4.5f, 9), 0, Rand(r, 0, L)), Rand(r, 2, 4));
            NearVerge(k, p, L, r, 3.6f, 8f, 6);
            for (var i = 0; i < 16; i++)
            {
                var x = Rand(r, 15, 70);
                var at = new Vector3(x, 0, Rand(r, 0, L));
                if (r.NextDouble() < 0.12) k.Any(r, FallTrees, p, at, Rand(r, 6, 9));
                else k.Pine(p, at, Rand(r, 6, 14) * (0.8f + x / 140f), r);
            }
            for (var i = 0; i < 3; i++) k.Any(r, WoodBits, p, new Vector3(Rand(r, 5, 14), 0, Rand(r, 0, L)), Rand(r, 0.5f, 1.0f));
            for (var i = 0; i < 2; i++) k.Any(r, Rocks, p, new Vector3(Rand(r, 6, 16), 0, Rand(r, 0, L)), Rand(r, 1, 2.6f));
            if (r.NextDouble() < 0.5) k.Prop("K_mushroom_redTall", p, new Vector3(Rand(r, 4, 7), 0, Rand(r, 0, L)), Rand(r, 0, 360), 0.45f);
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
                        // 앞줄 절반 넘게는 Kenney 상가(파스텔 벽), 뒷줄은 Kenney 고층·Cartoon City 건물을 섞는다
                        if (row == 0 && r.NextDouble() < 0.6 && Building(k, p, side, x0, ref z, Shops, Rand(r, 11, 17), ShopTints, r))
                        {
                            if (r.NextDouble() < 0.35) k.Any(r, Parasols, p, new Vector3(side * (x0 - 1.6f), 0, z - Rand(r, 3, 6)), 2.4f);
                            continue;
                        }
                        if (row > 0 && r.NextDouble() < 0.35 && Building(k, p, side, x0, ref z, Skyscrapers, Rand(r, 30, row == 1 ? 45 : 70), TowerTints, r)) continue;
                        if (row > 0 && r.NextDouble() < 0.3)
                        {
                            var t = k.Any(r, CityTowers, p, Vector3.zero, 1, side < 0 ? 90 : -90);
                            if (t != null) { Place(t, p, side, x0, ref z); continue; }
                        }
                        var partsFrom = p.childCount; // 이 건물의 부품(벽·창문 판·옥상·간판)을 끝에서 하나로 묶는다
                        var floors = Mathf.Max(2, Mathf.RoundToInt(Rand(r, lo, hi) / 3f));
                        var h = floors * 3f;
                        var x = side * (x0 + depth / 2);
                        var wall = C(Walls[r.Next(Walls.Length)]);
                        var trim = wall * 0.82f; trim.a = 1;
                        var bw = w - 0.8f;
                        k.Box(p, new Vector3(x, 0, z + w / 2), new Vector3(depth, h, bw), wall);
                        // 창문 판: 칸 크기가 건물 크기와 상관없이 일정 (Kit.Facade). 1층은 가게라 2층부터
                        var faceX = x - side * (depth / 2 + 0.02f);
                        var faceRot = Quaternion.Euler(0, side < 0 ? -90 : 90, 0); // 판의 앞(-z)이 도로를 보게
                        var winH = h - 4.2f;
                        if (winH > 1) k.Facade(p, new Vector3(faceX, 3.4f + winH / 2, z + w / 2), faceRot, bw - 1.2f, winH, windows);
                        // 옥상 난간
                        k.Box(p, new Vector3(x, h, z + w / 2), new Vector3(depth + 0.3f, 0.45f, bw + 0.3f), trim);
                        if (row < 2)
                        {
                            // 옥상 물건: 계단실 / 물탱크 / 실외기
                            var roofPick = r.NextDouble();
                            if (roofPick < 0.4) k.Box(p, new Vector3(x + side * Rand(r, -1, 1), h + 0.45f, z + w / 2 + Rand(r, -w * 0.25f, w * 0.25f)), new Vector3(2.2f, 2.4f, 2.6f), trim);
                            else if (roofPick < 0.75)
                            {
                                k.Pole(p, new Vector3(x, h + 0.45f, z + w * 0.35f), 0.9f, 1.4f, C("#8C8A80"));
                                k.Pole(p, new Vector3(x, h + 1.85f, z + w * 0.35f), 1.0f, 0.3f, C("#6E6A62"));
                            }
                            else for (var i = 0; i < 2; i++) k.Box(p, new Vector3(x + side * (i - 0.5f) * 1.6f, h + 0.45f, z + w * 0.65f), new Vector3(0.9f, 0.8f, 0.9f), C("#B9BEC0"));
                            // 층 띠: 3m 마다 얇은 돌출 (앞면만)
                            for (var f = 2; f < floors; f++)
                                k.Box(p, new Vector3(faceX - side * 0.08f, f * 3f, z + w / 2), new Vector3(0.18f, 0.14f, bw), trim);
                            // 발코니 한 줄 (절반쯤의 건물)
                            if (r.NextDouble() < 0.5)
                            {
                                var bz = z + w / 2 + Rand(r, -w * 0.3f, w * 0.3f);
                                for (var f = 2; f < floors; f++)
                                {
                                    k.Box(p, new Vector3(faceX - side * 0.5f, f * 3f, bz), new Vector3(1.0f, 0.12f, 1.8f), trim);
                                    k.Box(p, new Vector3(faceX - side * 0.95f, f * 3f + 0.12f, bz), new Vector3(0.06f, 0.9f, 1.8f), C("#DADDE0"));
                                }
                            }
                        }
                        if (row == 0)
                        {
                            // 1층 가게: 간판(밤에 빛난다)·차양·출입문·진열창
                            var sign = C(new[] { "#E2614B", "#4A90D0", "#58D8A0", "#F2C14E", "#B487D8", "#FF8FB8" }[r.Next(6)]);
                            k.GlowBox(p, new Vector3(side * (x0 - 0.12f), 3.0f, z + w / 2), new Vector3(0.24f, 0.8f, bw - 1.6f), sign);
                            k.Box(p, new Vector3(side * (x0 - 0.7f), 2.55f, z + w / 2), new Vector3(1.4f, 0.1f, bw - 1.6f), sign, Quaternion.Euler(0, 0, side * 12));
                            k.Box(p, new Vector3(side * (x0 - 0.05f), 0, z + w / 2 - w * 0.28f), new Vector3(0.1f, 2.2f, 1.1f), C("#4A3D34"));
                            k.Box(p, new Vector3(side * (x0 - 0.05f), 0.6f, z + w / 2 + w * 0.12f), new Vector3(0.08f, 1.5f, bw * 0.45f), C("#A9DCDA"));
                        }
                        Group(p, partsFrom, new Vector3(x, 0, z + w / 2), "Building");
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
                // Cartoon City 인도 소품: 쓰레기통·화단 덤불·버스 정류장
                if (r.NextDouble() < 0.6) k.Any(r, CityBins, p, new Vector3(walkX + side * 1.4f, 0, Rand(r, 2, L - 2)), 1, side < 0 ? 90 : -90);
                if (r.NextDouble() < 0.5) k.Any(r, CityBushes, p, new Vector3(walkX + side * 1.5f, 0, Rand(r, 2, L - 2)), 1);
                if (r.NextDouble() < 0.2) k.Prop("C_Bus_Stop_02", p, new Vector3(walkX + side * 1.2f, 0, L * 0.3f), side < 0 ? 90 : -90);
                for (var i = 0; i < 4; i++)
                    if (r.NextDouble() < 0.6) k.Person(p, new Vector3(walkX + side * Rand(r, 0.2f, 1.6f), 0, Rand(r, 0, L)), r); // 차도에서 떨어진 인도 안쪽
            }
            // 먼 스카이라인: 단순한 Kenney 건물 덩어리
            foreach (var side in new[] { -1, 1 })
                for (var i = 0; i < 2; i++)
                {
                    var far = k.Any(r, FarBlocks, p, new Vector3(side * Rand(r, 70, 110), 0, Rand(r, 0, L)), Rand(r, 25, 60), Rand(r, 0, 4) * 90);
                    if (far != null) k.Tint(far, C(TowerTints[r.Next(TowerTints.Length)]));
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

        static readonly string[] ShortPalms = { "K_tree_palmShort", "K_tree_palm" };
        static readonly string[] LowRocks = { "K_stone_largeA", "K_stone_largeB", "K_stone_largeC", "K_stone_largeD" };
        static readonly string[] ShopTints = { "#FFE9D6", "#FFF6D8", "#E3F1E4", "#DDEBFA", "#F7E1EC", "#EFE6FF", "#FFFFFF" };
        static readonly string[] TowerTints = { "#FFFFFF", "#E6F0FA", "#F4EEE4", "#E4F2EE" };

        /// names 에서 건물 하나를 높이 h 로 골라, 길 쪽 벽이 x0 에 오고 z 부터 이어지게 놓는다. 다음 자리로 z 를 옮긴다
        static bool Building(Kit k, Transform p, int side, float x0, ref float z, string[] names, float h, string[] tints, System.Random r)
        {
            var go = k.Any(r, names, p, Vector3.zero, h, (side < 0 ? 90 : -90) + BuildingFrontYaw);
            if (go == null) return false;
            k.Tint(go, C(tints[r.Next(tints.Length)]));
            Place(go, p, side, x0, ref z);
            return true;
        }

        /// p 의 from 번째 이후 자식을 at 에 둔 부모 하나로 묶는다 (지우거나 휠 때 한 덩어리로 움직이게)
        static void Group(Transform p, int from, Vector3 at, string name)
        {
            var g = new GameObject(name).transform;
            g.SetParent(p, false);
            g.localPosition = at;
            var parts = new List<Transform>();
            for (var i = from; i < p.childCount; i++) if (p.GetChild(i) != g) parts.Add(p.GetChild(i));
            foreach (var t in parts) t.SetParent(g, true);
        }

        static void Place(GameObject go, Transform p, int side, float x0, ref float z)
        {
            var b = LocalBounds(go, p);
            var dx = side > 0 ? x0 - b.min.x : -x0 - b.max.x;
            go.transform.localPosition += new Vector3(dx, 0, z - b.min.z);
            z += b.size.z + 0.6f;
        }

        /// Kenney 건물 앞(현관)이 길을 보도록 더하는 각도 (캡처로 확인)
        public static float BuildingFrontYaw = 0;

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
            // 방음벽 너머 나무 띠와 덤불, 중앙분리대 너머 숲
            for (var z = Rand(r, 0, 3); z < L; z += Rand(r, 4, 7)) k.Tree(p, new Vector3(Rand(r, 16, 22), 0, z), Rand(r, 5, 8), r);
            for (var i = 0; i < 7; i++) Bush(k, p, new Vector3(Rand(r, 5.2f, 10), 0, Rand(r, 0, L)), r);
            for (var i = 0; i < 6; i++) k.Pine(p, new Vector3(Rand(r, 12, 40), 0, Rand(r, 0, L)), Rand(r, 7, 12), r);
            for (var i = 0; i < 5; i++) k.Tree(p, new Vector3(-Rand(r, 12, 40), 0, Rand(r, 0, L)), Rand(r, 5, 9), r);
            NearVerge(k, p, L, r, -12.5f, -10.2f, 4);
            Verge(k, p, L, r, -10f, 5.2f, 0.8f);
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
            // 나트륨등에 비친 아래쪽 타일 띠. 해가 없으면 벽이 그림자 색 한 가지로만 보여서, 칸 사이 틈이 지나가며 속도가 느껴지게 한다
            foreach (var x in new[] { -6.36f, 3.36f })
            {
                for (var z = 0.25f; z < L; z += 3)
                    k.GlowBox(p, new Vector3(x, 0.35f, z + 1.25f), new Vector3(0.04f, 2.2f, 2.5f), C("#5C4126"));
                // 비상 반사등: 노면 위 1m, 6m 간격
                for (var z = 1.5f; z < L; z += 6)
                    k.GlowBox(p, new Vector3(x + (x < 0 ? 0.06f : -0.06f), 1.0f, z), new Vector3(0.04f, 0.16f, 0.4f), C("#E08A1E"));
            }
            // 한 조각 걸러 초록 비상구 표시
            if (c.index % 2 == 0)
                k.GlowBox(p, new Vector3(3.32f, 3.1f, L / 2), new Vector3(0.04f, 0.4f, 0.9f), C("#2E9E5A"));
            if (c.entrance) Portal(k, p, 0, true);
        }

        /// 터널 입구(산을 뚫은 콘크리트 벽)와 출구
        static void Portal(Kit k, Transform p, float z, bool entrance)
        {
            var concrete = C("#B0AA9E");
            k.Box(p, new Vector3(-12, -0.1f, z), new Vector3(11, 8, 1.2f), concrete);
            k.Box(p, new Vector3(9, -0.1f, z), new Vector3(11, 8, 1.2f), concrete);
            k.Box(p, new Vector3(-1.5f, 6.2f, z), new Vector3(14, 2, 1.2f), concrete);
            // 문 위와 양옆을 덮은 산. 터널 통로(x -6.8~3.8, 높이 7m 아래)와 문 앞 도로에는 닿지 않게 둔다
            var back = entrance ? 1 : -1;
            var mz = z + back * 20.6f;
            var hill = C("#4E7F3A");
            k.Ball(p, new Vector3(-1.5f, 19, mz), new Vector3(60, 24, 38), hill);
            k.Ball(p, new Vector3(-28.8f, 8, mz), new Vector3(44, 30, 38), hill);
            k.Ball(p, new Vector3(25.8f, 8, mz), new Vector3(44, 30, 38), hill);
        }
    }
}
