using System;
using System.Collections.Generic;
using UnityEngine;

namespace Allo.Critters
{
    /// 캐릭터가 서는 평평한 면. center 는 면 위 가운데(월드), size 는 (x 폭, z 깊이).
    public readonly struct WalkSurface
    {
        public readonly string name;
        public readonly Vector3 center;
        public readonly Vector2 size;

        public WalkSurface(string name, Vector3 center, Vector2 size)
        {
            this.name = name;
            this.center = center;
            this.size = size;
        }
    }

    /// 걷는 면들과, 점프로 건너갈 수 있는 이웃 관계.
    /// 두 면의 가장자리 사이 수평 거리가 maxJump 이하이고 높이 차가 maxRise 이하이면 이웃이다.
    public sealed class WalkGraph
    {
        /// 면 가장자리에서 이만큼 안쪽에만 선다 (떨어져 보이지 않게)
        public const float EdgeMargin = 0.08f;

        public IReadOnlyList<WalkSurface> Surfaces { get; }
        readonly List<int>[] _neighbors;

        /// 자리를 고를 때 이 조건을 만족하는 점을 먼저 고른다 (아이가 정면을 볼 때 편하게 보이는 곳). 없으면 아무 데나
        public Func<Vector3, bool> Comfortable;

        public WalkGraph(IReadOnlyList<WalkSurface> surfaces, float maxJump = 0.9f, float maxRise = 0.75f)
        {
            Surfaces = surfaces;
            _neighbors = new List<int>[surfaces.Count];
            for (var i = 0; i < surfaces.Count; i++) _neighbors[i] = new List<int>();
            for (var i = 0; i < surfaces.Count; i++)
            for (var j = i + 1; j < surfaces.Count; j++)
            {
                var a = surfaces[i];
                var b = surfaces[j];
                var gapX = Mathf.Max(0, Mathf.Abs(a.center.x - b.center.x) - (a.size.x + b.size.x) / 2);
                var gapZ = Mathf.Max(0, Mathf.Abs(a.center.z - b.center.z) - (a.size.y + b.size.y) / 2);
                var gap = Mathf.Sqrt(gapX * gapX + gapZ * gapZ);
                if (gap <= maxJump && Mathf.Abs(a.center.y - b.center.y) <= maxRise)
                {
                    _neighbors[i].Add(j);
                    _neighbors[j].Add(i);
                }
            }
        }

        public IReadOnlyList<int> Neighbors(int i) => _neighbors[i];

        public int IndexOf(string name)
        {
            for (var i = 0; i < Surfaces.Count; i++)
                if (Surfaces[i].name == name) return i;
            return -1;
        }

        /// 캐릭터 몸보다 좁은 면(머리받침 등)에서는 가운데에만 앉는다 (가장자리에 서면 떨어져 보인다)
        public const float NarrowSurface = 0.2f;

        public Vector3 RandomPoint(int i, System.Random rng)
        {
            if (Comfortable == null) return AnyPoint(i, rng);
            var first = AnyPoint(i, rng);
            if (Comfortable(first)) return first;
            for (var k = 0; k < 15; k++)
            {
                var p = AnyPoint(i, rng);
                if (Comfortable(p)) return p;
            }
            return first;
        }

        Vector3 AnyPoint(int i, System.Random rng)
        {
            var s = Surfaces[i];
            if (Mathf.Min(s.size.x, s.size.y) < NarrowSurface) return s.center;
            var hx = Mathf.Max(0, s.size.x / 2 - EdgeMargin);
            var hz = Mathf.Max(0, s.size.y / 2 - EdgeMargin);
            return new Vector3(
                s.center.x + (float)(rng.NextDouble() * 2 - 1) * hx,
                s.center.y,
                s.center.z + (float)(rng.NextDouble() * 2 - 1) * hz);
        }

        /// 면 안(가장자리 여유 안쪽)으로 끌어들인 점. 높이는 면 높이
        public static Vector3 Clamp(Vector3 p, WalkSurface s)
        {
            var hx = Mathf.Max(0, s.size.x / 2 - EdgeMargin);
            var hz = Mathf.Max(0, s.size.y / 2 - EdgeMargin);
            return new Vector3(Mathf.Clamp(p.x, s.center.x - hx, s.center.x + hx), s.center.y,
                Mathf.Clamp(p.z, s.center.z - hz, s.center.z + hz));
        }

        public int Nearest(Vector3 p)
        {
            var best = -1;
            var bestD = float.MaxValue;
            for (var i = 0; i < Surfaces.Count; i++)
            {
                var d = (Surfaces[i].center - p).sqrMagnitude;
                if (d < bestD)
                {
                    bestD = d;
                    best = i;
                }
            }
            return best;
        }
    }
}
