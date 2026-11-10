using UnityEngine;

namespace Allo.World
{
    /// 교차로 회전·유턴 경로의 모양. 조각 로컬(들어올 때 +z, 우리 차로 x=0) 기준.
    /// 방향은 smootherstep(6u⁵-15u⁴+10u³)으로 바뀌어 곡률이 0 에서 서서히 커졌다가 다시 0 이 된다
    /// (실제 도로의 완화곡선처럼 핸들을 천천히 감았다 푼다). 위치는 방향을 적분해 표로 만들어 둔다.
    public static class TurnShape
    {
        public const float Lead = 1f;      // 회전을 시작하기 전 직진
        public const float Exit = 0.5f;    // 회전을 마친 뒤 조각 끝까지 직진
        public const float RightCurve = 30f, LeftCurve = 36f; // 도는 구간 길이. 가장 급한 곳의 반지름이 약 10m·12m
        public const float UturnShift = -2.8f;                 // 유턴 뒤 차로 (ChunkTrack.UturnShift 와 같다)
        public const float UturnLen = 10f;                     // 유턴 조각의 물체 길이
        const int N = 400;

        sealed class Table
        {
            public float len;
            public Vector3[] pos;
            public float[] yaw;
        }

        static Table _right, _left, _uturn;

        static float S(float u) => u * u * u * (u * (u * 6 - 15) + 10);

        /// lead 직진 → curve 길이 동안 totalYaw 만큼 돌기 → exit 직진
        static Table Make(float lead, float curve, float totalYaw, float exit)
        {
            var t = new Table { len = lead + curve + exit, pos = new Vector3[N + 1], yaw = new float[N + 1] };
            float YawAt(float s) => s <= lead ? 0 : s >= lead + curve ? totalYaw : totalYaw * S((s - lead) / curve);
            var p = Vector3.zero;
            const int sub = 8;
            var ds = t.len / N;
            t.pos[0] = p;
            t.yaw[0] = 0;
            for (var i = 1; i <= N; i++)
            {
                for (var k = 0; k < sub; k++)
                {
                    var s = (i - 1) * ds + (k + 0.5f) * ds / sub;
                    var a = YawAt(s) * Mathf.Deg2Rad;
                    p += new Vector3(Mathf.Sin(a), 0, Mathf.Cos(a)) * (ds / sub);
                }
                t.pos[i] = p;
                t.yaw[i] = YawAt(i * ds);
            }
            return t;
        }

        static Table Get(string turn)
        {
            switch (turn)
            {
                case "right": return _right ??= Make(Lead, RightCurve, 90, Exit);
                case "left": return _left ??= Make(Lead, LeftCurve, -90, Exit);
                case "uturn":
                    if (_uturn != null) return _uturn;
                    // 옆으로 정확히 UturnShift 만큼 비키도록 도는 길이를 정한다
                    var probe = Make(0, 1, -180, 0);
                    var lu = Mathf.Abs(UturnShift / probe.pos[N].x);
                    var zMax = 0f;
                    foreach (var q in probe.pos) zMax = Mathf.Max(zMax, q.z * lu);
                    var a = UturnLen - zMax - 0.3f;
                    return _uturn = Make(a, lu, -180, a);
                default: return null;
            }
        }

        public static float Length(string turn) => Get(turn)?.len ?? 0;

        public static Pose2 Pose(string turn, float s)
        {
            var t = Get(turn);
            var f = Mathf.Clamp01(s / t.len) * N;
            var i = Mathf.Min(N - 1, Mathf.FloorToInt(f));
            var w = f - i;
            return new Pose2(Vector3.Lerp(t.pos[i], t.pos[i + 1], w), Mathf.Lerp(t.yaw[i], t.yaw[i + 1], w));
        }

        /// 회전한 뒤 차로가 지나는 z (가로 도로의 우리 차로)
        public static float LaneZ(string turn) => Get(turn).pos[N].z;

        /// 경로가 끝나는 x (그 다음 조각이 시작하는 곳)
        public static float ExitX(string turn) => Get(turn).pos[N].x;

        /// 가로 도로의 가까운·먼 가장자리 z. 도로 폭 x -5.4~2.6 를 돈 방향으로 옮긴 것이다
        public static (float near, float far) CrossEdges(string turn)
        {
            var zc = LaneZ(turn);
            return turn == "right" ? (zc - 2.6f, zc + 5.4f) : (zc - 5.4f, zc + 2.6f);
        }

        /// 가로 도로에 닿기 전에 차가 우리 도로 밖(모서리)을 지나는 구간을 덮는 포장 (xMin, xMax, zMin, zMax). 없으면 null
        public static Vector4? Apron(string turn)
        {
            if (turn != "right" && turn != "left") return null;
            var t = Get(turn);
            var (near, _) = CrossEdges(turn);
            var right = turn == "right";
            var zMin = float.PositiveInfinity;
            foreach (var p in t.pos)
                if (p.z < near && (right ? p.x > 1.8f : p.x < -4.6f)) zMin = Mathf.Min(zMin, p.z);
            if (float.IsInfinity(zMin)) return null;
            var ex = ExitX(turn);
            return right ? new Vector4(2.4f, ex, zMin - 2, near + 0.1f) : new Vector4(ex, -5.2f, zMin - 2, near + 0.1f);
        }
    }
}
