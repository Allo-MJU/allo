using System.Collections.Generic;
using UnityEngine;

namespace Allo.World
{
    /// 도로 조각 하나. index 번째 조각은 출발점에서 index × 길이 m 앞에서 시작한다.
    public sealed class ChunkInfo
    {
        public int index;
        public string kind;
        public bool entrance; // 터널 입구
        public bool exit;     // 터널 출구 다음 첫 조각
    }

    /// 차는 제자리에 있고 세상이 뒤로 흐른다. 달린 거리(Offset)에 맞춰
    /// 앞에 조각을 붙이고 뒤에서 뗀다. 장면이 바뀌면 바로 앞(commit m)은 그대로 두고
    /// 그 너머를 새 장면으로 다시 만든다 (8초마다 바뀌어도 금방 보이게).
    public sealed class ChunkTrack
    {
        readonly float _len, _ahead, _behind, _commit;
        readonly Dictionary<int, ChunkInfo> _live = new();
        string _kind;

        public float Offset { get; private set; }
        public float ChunkLength => _len;
        public IReadOnlyDictionary<int, ChunkInfo> Live => _live;

        public ChunkTrack(float chunkLength = 30, float ahead = 300, float behind = 60, float commit = 25)
        {
            _len = chunkLength;
            _ahead = ahead;
            _behind = behind;
            _commit = commit;
        }

        /// 조각이 차(0) 기준 몇 m 앞에서 시작하는지
        public float StartOf(int index) => index * _len - Offset;

        public (List<ChunkInfo> spawn, List<int> despawn) Advance(float meters)
        {
            if (meters <= 0 || _kind == null) return (new List<ChunkInfo>(), new List<int>());
            // 한 번에 아무리 많이 가도 보이는 범위만 다시 채운다
            Offset += Mathf.Min(meters, _ahead + _behind + _len * 2);
            return Fill();
        }

        public (List<ChunkInfo> spawn, List<int> despawn) SetScene(string kind)
        {
            var spawn = new List<ChunkInfo>();
            var despawn = new List<int>();
            if (kind == _kind) return (spawn, despawn);
            _kind = kind;
            var first = Mathf.FloorToInt((Offset + _commit) / _len) + 1;
            var keep = new List<int>(_live.Keys);
            foreach (var i in keep)
                if (i >= first)
                {
                    _live.Remove(i);
                    despawn.Add(i);
                }
            var (s, d) = Fill();
            spawn.AddRange(s);
            despawn.AddRange(d);
            return (spawn, despawn);
        }

        (List<ChunkInfo>, List<int>) Fill()
        {
            var spawn = new List<ChunkInfo>();
            var despawn = new List<int>();
            var lo = Mathf.FloorToInt((Offset - _behind) / _len);
            var hi = Mathf.FloorToInt((Offset + _ahead) / _len);
            foreach (var i in new List<int>(_live.Keys))
                if (i < lo || i > hi)
                {
                    _live.Remove(i);
                    despawn.Add(i);
                }
            for (var i = lo; i <= hi; i++)
            {
                if (_live.ContainsKey(i)) continue;
                _live.TryGetValue(i - 1, out var prev);
                var c = new ChunkInfo
                {
                    index = i,
                    kind = _kind,
                    entrance = _kind == "tunnel" && prev != null && prev.kind != "tunnel",
                    exit = _kind != "tunnel" && prev != null && prev.kind == "tunnel",
                };
                _live[i] = c;
                spawn.Add(c);
            }
            return (spawn, despawn);
        }
    }
}
