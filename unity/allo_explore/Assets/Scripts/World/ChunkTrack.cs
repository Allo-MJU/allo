using System.Collections.Generic;
using UnityEngine;

namespace Allo.World
{
    /// 길 위의 위치와 방향. 트랙 공간(xz 평면) 기준, yaw 0 = +z, 양수 = 오른쪽으로 돈다 (Unity Euler y 와 같다)
    public struct Pose2
    {
        public Vector3 pos;
        public float yaw;

        public Pose2(Vector3 pos, float yaw) { this.pos = pos; this.yaw = yaw; }

        public Quaternion Rot => Quaternion.Euler(0, yaw, 0);
        public Vector3 Forward => Rot * Vector3.forward;
        public Vector3 Right => Rot * Vector3.right;

        /// 이 자세를 원점으로 본 로컬 자세를 트랙 공간으로
        public Pose2 Apply(Vector3 localPos, float localYaw) => new(pos + Rot * localPos, yaw + localYaw);
    }

    /// 도로 조각 하나. 경로를 따라 이어지며, index 가 클수록 앞이다.
    public sealed class ChunkInfo
    {
        public int index;
        public string kind;
        public bool entrance; // 터널 입구
        public bool exit;     // 터널 출구 다음 첫 조각

        /// null = 직선. left | right | uturn 이면 교차로·유턴 조각
        public string turn;

        /// 경로에서 이 조각이 시작하는 거리(m)와 경로 길이
        public float start, length;

        /// 이 조각 경로의 시작 자세 (차로 가운데)
        public Pose2 path;

        /// 물체를 짓는 기준 자세와 난수 씨앗. 보통은 path 와 index 이고,
        /// 유턴 뒤에는 지나온 조각(reuseOf)을 거꾸로 달리므로 그 조각의 것을 그대로 쓴다
        public Pose2 geom;
        public int seed;
        public int reuseOf = -1;

        /// 좌·우회전 바로 뒤 두 조각은 회전 안쪽 풍경을 짓지 않는다 (지나온 조각의 풍경과 겹치므로)
        public bool trimLeft, trimRight;
        public int trimStep;

        /// 다음 조각이 좌·우회전 교차로면, 조각 끝을 넘어 가로 도로까지 뻗는 길가 물체(건물 등)를 짓지 않는다
        public bool clearEnd;

        /// 직선 조각이 휘는 각도(도, + 오른쪽). 차로 유지(keep)나 차의 진행 방향(heading)을 따라 길이 살짝 꺾인다
        public float bend;

        /// keepLeft·keepRight 로 휘기 시작한 조각이면 그 종류 (다음 조각이 반대로 휘어 S자가 된다)
        public string keep;
        public bool keepTail; // 차로 유지 S자의 두 번째(되돌리는) 조각

        public float End => start + length;
    }

    /// 차는 제자리에 있고 세상이 움직인다. 경로는 직선 조각과 교차로(좌·우회전)·유턴 조각으로 이어지고,
    /// 내비가 알려 준 다음 회전(SetTurns)을 그 거리의 조각 경계에 놓는다.
    /// 장면이 바뀌거나 회전 계획이 바뀌면 바로 앞(commit m)은 그대로 두고 그 너머를 다시 만든다.
    public sealed class ChunkTrack
    {
        // 교차로 기하는 TurnShape 에 있다 (조각 로컬, 들어올 때 +z, 우리 차로 x=0, 도로 폭 x -5.4~2.6)
        public const float UturnShift = TurnShape.UturnShift;          // 유턴 뒤 차로는 지나온 조각의 x=-2.8 (도로 폭이 그대로 겹친다)
        public const float TurnKph = 20f, UturnKph = 9f, Decel = 1.8f; // 교차로 속도와 그 앞 감속도(m/s²)
        public const float KeepBend = 14f;                            // 차로 유지: 한 조각에서 14도 꺾었다가 다음 조각에서 되돌린다
        public const float MaxBend = 12f;                             // heading 으로 휠 때 조각 하나의 최대 각도
        public const float SteerGain = 0.6f;                          // 한 번에 차이의 60%만 따라간다 (나머지는 다음 조각에서)

        readonly float _len, _ahead, _behind, _commit;
        readonly Dictionary<int, ChunkInfo> _live = new();
        readonly Dictionary<int, ChunkInfo> _history = new();  // 유턴 때 되짚을 지나온 조각
        readonly List<(string type, float at)> _plan = new();  // 아직 조각이 되지 않은 회전 (경로 거리)
        ChunkInfo _last;
        string _kind;
        float _counterBend; // 차로 유지 S자의 두 번째 조각이 받을 각도

        /// 달린 경로 거리
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

        public static float TurnLength(string turn) => TurnShape.Length(turn);

        /// 조각 안 경로 거리 s 의 로컬 자세
        public static Pose2 LocalPose(string turn, float s, float len, float bend = 0)
        {
            switch (turn)
            {
                case "right":
                case "left":
                case "uturn":
                    return TurnShape.Pose(turn, s);
                default:
                {
                    s = Mathf.Clamp(s, 0, len);
                    if (Mathf.Abs(bend) < 0.01f) return new Pose2(new Vector3(0, 0, s), 0);
                    // 일정한 곡률의 호. 반지름 R 은 부호를 가진다 (+ 오른쪽으로 휜다)
                    var rad = bend * Mathf.Deg2Rad;
                    var r = len / rad;
                    var phi = rad * s / len;
                    return new Pose2(new Vector3(r * (1 - Mathf.Cos(phi)), 0, r * Mathf.Sin(phi)), bend * s / len);
                }
            }
        }

        public static Pose2 PoseIn(ChunkInfo c, float s)
        {
            var l = LocalPose(c.turn, s, c.length, c.bend);
            return c.path.Apply(l.pos, l.yaw);
        }

        /// 경로 거리 d 의 자세. 만들어진 조각 밖이면 가장 가까운 끝에서 곧게 잇는다
        public Pose2 PoseAt(float d)
        {
            foreach (var c in _live.Values)
                if (d >= c.start && d < c.End) return PoseIn(c, d - c.start);
            if (_last != null && d >= _last.End)
            {
                var e = PoseIn(_last, _last.length);
                return e.Apply(new Vector3(0, 0, d - _last.End), 0);
            }
            return new Pose2(new Vector3(0, 0, d), 0);
        }

        public Pose2 CarPose => PoseAt(Offset);

        /// 차(0)에서 meters 앞에 놓인 조각. 없으면 null
        public ChunkInfo ChunkAt(float meters)
        {
            var d = Offset + meters;
            foreach (var c in _live.Values)
                if (d >= c.start && d < c.End) return c;
            return null;
        }

        /// 차(0)에서 meters 앞에 놓인 조각의 장면. 아직 없으면 null
        public string KindAt(float meters) => ChunkAt(meters)?.kind;

        /// 경로 거리 d 다음에 오는 교차로·유턴 조각의 시작 거리. 없으면 무한대
        public float NextTurnStart(float d)
        {
            var best = float.PositiveInfinity;
            foreach (var c in _live.Values)
                if (c.turn != null && c.start >= d && c.start < best) best = c.start;
            return best;
        }

        /// 경로 거리 d 다음의 교차로·유턴·차로 유지·휜 조각 시작 거리 (캡처용). 없으면 무한대
        public float NextFeatureStart(float d)
        {
            var best = float.PositiveInfinity;
            foreach (var c in _live.Values)
                if ((c.turn != null || c.keep != null || Mathf.Abs(c.bend) > 0.01f) && c.start >= d && c.start < best) best = c.start;
            return best;
        }

        /// 교차로·유턴에서의 속도 상한(km/h). 교차로 앞에서는 Decel 로 서서히 줄어들도록 거리에 따라 높여 둔다.
        /// 직선이면 무한대 (돈 뒤 가속은 WorldDirector 가 천천히 한다)
        public float SpeedCapAt(float d)
        {
            var cap = float.PositiveInfinity;
            foreach (var c in _live.Values)
            {
                if (c.turn == null || d >= c.End) continue;
                var vt = (c.turn == "uturn" ? UturnKph : TurnKph) / 3.6f;
                var dist = Mathf.Max(0, c.start - d);
                cap = Mathf.Min(cap, Mathf.Sqrt(vt * vt + 2 * Decel * dist) * 3.6f);
            }
            return cap;
        }

        public (List<ChunkInfo> spawn, List<int> despawn) Advance(float meters)
        {
            if (meters <= 0 || _kind == null) return (new List<ChunkInfo>(), new List<int>());
            // 한 번에 아무리 많이 가도 보이는 범위만 다시 채운다
            Offset += Mathf.Min(meters, _ahead + _behind + _len * 2);
            for (var i = _plan.Count - 1; i >= 0; i--)
                if (_plan[i].at < Offset) _plan.RemoveAt(i);
            return Fill();
        }

        public (List<ChunkInfo> spawn, List<int> despawn) SetScene(string kind)
        {
            if (kind == _kind) return (new List<ChunkInfo>(), new List<int>());
            _kind = kind;
            return Rebuild();
        }

        /// 내비가 알려 준 다음 회전들. inM 은 지금 위치에서 남은 거리.
        /// 같은 종류가 45m 안에서 다시 오면 처음 자리를 지킨다 (1초마다 오는 거리의 흔들림에 길이 다시 지어지지 않게)
        public (List<ChunkInfo> spawn, List<int> despawn) SetTurns(IEnumerable<(string type, float inM)> turns)
        {
            var known = new List<(string type, float at)>(_plan);
            foreach (var c in _live.Values)
            {
                if (c.turn != null && c.start >= Offset) known.Add((c.turn, c.start));
                if (c.keep != null && c.start >= Offset) known.Add((c.keep, c.start));
            }
            var next = new List<(string type, float at)>();
            foreach (var (type, inM) in turns)
            {
                if (type != "left" && type != "right" && type != "uturn" && type != "keepLeft" && type != "keepRight") continue;
                var at = Offset + inM - TurnShape.Lead;
                foreach (var k in known)
                    if (k.type == type && Mathf.Abs(k.at - at) < 45) { at = k.at; break; }
                next.Add((type, at));
            }
            next.Sort((a, b) => a.at.CompareTo(b.at));
            known.Sort((a, b) => a.at.CompareTo(b.at));
            var same = next.Count == known.Count;
            for (var i = 0; same && i < next.Count; i++)
                same = next[i].type == known[i].type && Mathf.Approximately(next[i].at, known[i].at);
            if (same) return (new List<ChunkInfo>(), new List<int>());
            _plan.Clear();
            _plan.AddRange(next);
            // 바로 앞(commit)에 이미 놓인 교차로는 계획과 달라도 그대로 둔다. 그 밖의 교차로는 새 계획으로 다시 놓는다
            var keep = Offset + _commit;
            _plan.RemoveAll(p => p.at < keep && HasTurnChunkNear(p.type, p.at));
            return Rebuild(fromPlanOnly: true);
        }

        /// 바로 앞(commit m)까지는 두고 그 너머 조각을 지운 뒤 계획대로 다시 잇는다
        bool HasTurnChunkNear(string type, float at)
        {
            foreach (var c in _live.Values)
                if ((c.turn == type || c.keep == type) && Mathf.Abs(c.start - at) < 45) return true;
            return false;
        }

        /// fromPlanOnly 가 아니면(장면만 바뀐 경우) 지운 교차로를 계획으로 되돌려 다시 놓는다
        (List<ChunkInfo>, List<int>) Rebuild(bool fromPlanOnly = false)
        {
            var despawn = new List<int>();
            var cut = Offset + _commit;
            var drop = new List<int>();
            foreach (var (i, c) in _live)
                if (c.start >= cut) drop.Add(i);
            drop.Sort();
            foreach (var i in drop)
            {
                var c = _live[i];
                // 지운 조각에 들어 있던 회전은 계획으로 되돌린다
                var t = c.turn ?? c.keep;
                if (!fromPlanOnly && t != null && !_plan.Exists(p => p.type == t && Mathf.Abs(p.at - c.start) < 45)) _plan.Add((t, c.start));
                _live.Remove(i);
                _history.Remove(i);
                despawn.Add(i);
            }
            _last = null;
            foreach (var c in _live.Values)
                if (_last == null || c.index > _last.index) _last = c;
            _counterBend = _last != null && _last.keep != null ? -_last.bend : 0;
            var (s, d) = Fill();
            despawn.AddRange(d);
            return (s, despawn);
        }

        (List<ChunkInfo>, List<int>) Fill()
        {
            var spawn = new List<ChunkInfo>();
            var despawn = new List<int>();
            while (_last == null || _last.End <= Offset + _ahead)
            {
                var prev = _last;
                var c = Next();
                // 교차로 바로 앞 조각은 끝을 넘는 물체를 빼고 다시 짓는다 (이미 지었으면 지우고 다시)
                // 차 바로 밑 조각은 다시 지으면 튀어 보이므로 그대로 둔다
                if (prev != null && (c.turn == "left" || c.turn == "right") && !prev.clearEnd && (spawn.Contains(prev) || prev.start >= Offset + 10))
                {
                    prev.clearEnd = true;
                    if (!spawn.Contains(prev))
                    {
                        despawn.Add(prev.index);
                        spawn.Add(prev);
                    }
                }
                _live[c.index] = c;
                _history[c.index] = c;
                spawn.Add(c);
                _last = c;
            }
            foreach (var i in new List<int>(_live.Keys))
            {
                var c = _live[i];
                if (c.End > Offset - _behind || c == _last) continue;
                _live.Remove(i);
                // 이번에 만들자마자 뒤로 지나간 조각은 짓지도 지우지도 않는다
                if (spawn.Remove(c)) continue;
                despawn.Add(i);
            }
            // 유턴 때 되짚을 수 있게 지나온 조각을 조금 더 오래 기억한다
            foreach (var i in new List<int>(_history.Keys))
                if (_history[i].End < Offset - _ahead - 100) _history.Remove(i);
            return (spawn, despawn);
        }

        ChunkInfo Next()
        {
            if (_last == null)
            {
                // 처음: 차 뒤까지 채우도록 뒤에서 시작한다
                var first = Mathf.FloorToInt((Offset - _behind) / _len);
                var p0 = new Pose2(new Vector3(0, 0, first * _len), 0);
                return Straight(first, first * _len, p0, null);
            }
            var index = _last.index + 1;
            var start = _last.End;
            var end = PoseIn(_last, _last.length);

            // 유턴 뒤: 지나온 조각을 거꾸로 달린다 (물체는 그 조각 그대로라 장면이 튀지 않는다)
            var mirrorOf = _last.turn == "uturn" ? _last.index - 1 : _last.reuseOf >= 0 ? _last.reuseOf - 1 : -1;
            // 장면이 바뀌었으면(차가 보낸 envTags 가 기준) 새 장면으로 짓는다. 다만 지나온 조각이 아직 남아 있으면
            // 같은 자리에 두 벌이 겹치지 않도록 그 조각을 그대로 되짚는다
            if (mirrorOf >= 0 && _history.TryGetValue(mirrorOf, out var r) && r.turn == null && Mathf.Abs(r.bend) < 0.01f
                && (r.kind == _kind || _live.ContainsKey(r.index)) && !TurnWithin(start, start + r.length))
            {
                var back = PoseIn(r, r.length);
                return new ChunkInfo
                {
                    index = index, kind = r.kind, entrance = r.entrance, exit = r.exit,
                    start = start, length = r.length,
                    path = new Pose2(back.pos + back.Right * UturnShift, back.yaw + 180),
                    geom = r.geom, seed = r.seed, reuseOf = r.index,
                };
            }

            // 계획된 회전이 이 조각 안에 들면 교차로를 놓는다 (터널·고속도로에서는 좌·우회전·유턴을 그리지 않는다).
            // 차로 유지는 이 조각을 살짝 꺾고 다음 조각에서 되돌린다 (고속도로 나들목에서도 그린다)
            if (_kind != "tunnel" && _counterBend == 0)
                for (var i = 0; i < _plan.Count; i++)
                {
                    var (type, at) = _plan[i];
                    if (at < start - 1 || at >= start + _len) continue;
                    if (type == "keepLeft" || type == "keepRight")
                    {
                        _plan.RemoveAt(i);
                        var kc = Straight(index, start, end, _last);
                        kc.bend = type == "keepRight" ? KeepBend : -KeepBend;
                        kc.keep = type;
                        _counterBend = -kc.bend;
                        return kc;
                    }
                    if (_kind == "highway") continue;
                    {
                        _plan.RemoveAt(i);
                        var j = new ChunkInfo
                        {
                            index = index, kind = _kind, turn = type, start = start, length = TurnLength(type),
                            path = end, geom = end, seed = index,
                        };
                        return j;
                    }
                }
            var st = Straight(index, start, end, _last);
            if (_counterBend != 0)
            {
                st.bend = _counterBend;
                st.keepTail = true;
                _counterBend = 0;
            }
            return st;
        }

        /// 차의 진행 방향을 따라 앞길을 휜다. 바로 앞(commit) 너머 첫 직선 조각을 desiredYaw 로 끝나게 휘고,
        /// 그 뒤 조각들은 모양을 그대로 둔 채 새 끝에 맞춰 옮긴다. 그 조각이 교차로·차로 유지·유턴 되짚기 조각이거나
        /// 차이가 3도 안쪽이면 null
        public (ChunkInfo bent, List<ChunkInfo> moved)? SteerTo(float desiredYaw)
        {
            ChunkInfo target = null;
            foreach (var c in _live.Values)
                if (c.start >= Offset + _commit && (target == null || c.index < target.index)) target = c;
            if (target == null || target.turn != null || target.reuseOf >= 0 || target.keep != null) return null;
            if (target.keepTail) return null;
            // 뒤 조각은 통째로 옮길 뿐이라 교차로가 있어도 된다. 유턴 뒤 되짚는 조각은 지나온 자리에 묶여 있어 옮길 수 없다
            foreach (var c in _live.Values)
                if (c.index > target.index && c.reuseOf >= 0) return null;
            var endYaw = PoseIn(target, target.length).yaw;
            var delta = Mathf.DeltaAngle(endYaw, desiredYaw);
            if (Mathf.Abs(delta) < 3) return null;
            var nb = Mathf.Clamp(target.bend + delta * SteerGain, -MaxBend, MaxBend);
            if (Mathf.Approximately(nb, target.bend)) return null;
            target.bend = nb;
            var moved = new List<ChunkInfo>();
            var prev = target;
            for (var i = target.index + 1; _live.TryGetValue(i, out var c); i++)
            {
                c.path = PoseIn(prev, prev.length);
                c.geom = c.path;
                moved.Add(c);
                prev = c;
            }
            return (target, moved);
        }

        bool TurnWithin(float a, float b)
        {
            foreach (var (_, at) in _plan)
                if (at >= a - 1 && at < b) return true;
            return false;
        }

        ChunkInfo Straight(int index, float start, Pose2 pose, ChunkInfo prev)
        {
            var c = Plain(index, start, pose, prev);
            if (prev != null && (prev.turn == "left" || prev.turn == "right"))
            {
                c.trimLeft = prev.turn == "left";
                c.trimRight = prev.turn == "right";
                c.trimStep = 1;
            }
            else if (prev != null && prev.trimStep == 1)
            {
                c.trimLeft = prev.trimLeft;
                c.trimRight = prev.trimRight;
                c.trimStep = 2;
            }
            return c;
        }

        ChunkInfo Plain(int index, float start, Pose2 pose, ChunkInfo prev) => new()
        {
            index = index,
            kind = _kind,
            start = start,
            length = _len,
            path = pose,
            geom = pose,
            seed = index,
            entrance = _kind == "tunnel" && prev != null && prev.kind != "tunnel",
            exit = _kind != "tunnel" && prev != null && prev.kind == "tunnel",
        };
    }
}
