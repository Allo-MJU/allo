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

        public Vector3 RandomPoint(int i, System.Random rng)
        {
            var s = Surfaces[i];
            var hx = Mathf.Max(0, s.size.x / 2 - EdgeMargin);
            var hz = Mathf.Max(0, s.size.y / 2 - EdgeMargin);
            return new Vector3(
                s.center.x + (float)(rng.NextDouble() * 2 - 1) * hx,
                s.center.y,
                s.center.z + (float)(rng.NextDouble() * 2 - 1) * hz);
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
