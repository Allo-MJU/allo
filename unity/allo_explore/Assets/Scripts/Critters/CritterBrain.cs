using UnityEngine;

namespace Allo.Critters
{
    public enum CritterState { Idle, Walk, Jump, Peek, Tumble, Sleep, Huddle }

    /// 차 신호에서 온 분위기. scene 메시지에서 만든다.
    public struct Mood
    {
        public bool night;
        public bool rain;
        public bool tunnel;
        public bool moving;
    }

    /// 캐릭터 하나의 행동 결정. 그리기와 분리된 순수 로직이라 EditMode 테스트로 확인한다.
    ///
    /// - Idle 로 잠깐 쉬다가 같은 면 안에서 걷거나(Walk) 이웃 면으로 뛴다(Jump)
    /// - 밤: 쉬는 대신 존다(Sleep) / 비: 창턱으로 가서 밖을 본다(Peek)
    /// - 터널: 팔걸이 쪽으로 모여 웅크린다(Huddle) / 정차: 더 자주 움직인다
    /// - Jolt(급제동·급조향): 하던 일을 멈추고 구른다(Tumble)
    /// 위치(Position)는 상태에 맞게 Target 쪽으로 옮긴다. 점프 높이는 그리는 쪽이 Progress 로 계산한다.
    public sealed class CritterBrain
    {
        public const float TumbleSeconds = 1.2f;
        public const float WalkSpeed = 0.35f;   // m/s
        public const float JumpSeconds = 0.55f;

        readonly WalkGraph _g;
        readonly System.Random _rng;
        float _timer;
        float _stateTime;

        public CritterState State { get; private set; } = CritterState.Idle;
        public int Surface { get; private set; }
        public Vector3 Position { get; private set; }
        public Vector3 Target { get; private set; }

        /// 점프 출발점 (그리는 쪽이 포물선을 그린다)
        public Vector3 JumpFrom { get; private set; }

        /// 현재 상태에서 흐른 비율 0~1 (점프·구르기)
        public float Progress => State switch
        {
            CritterState.Jump => Mathf.Clamp01(_stateTime / JumpSeconds),
            CritterState.Tumble => Mathf.Clamp01(_stateTime / TumbleSeconds),
            _ => 0,
        };

        public CritterBrain(WalkGraph g, int startSurface, int seed)
        {
            _g = g;
            _rng = new System.Random(seed);
            Surface = Mathf.Clamp(startSurface, 0, g.Surfaces.Count - 1);
            Position = Target = g.RandomPoint(Surface, _rng);
            _timer = Range(0.5f, 2f);
        }

        public void Jolt()
        {
            State = CritterState.Tumble;
            _stateTime = 0;
            _timer = TumbleSeconds;
            // 앞으로(-z) 조금 쏠린 자리에서 일어난다. 면 밖으로는 나가지 않는다
            var s = _g.Surfaces[Surface];
            var p = Position + new Vector3(0, 0, -0.15f);
            Target = Clamp(p, s);
        }

        public void Tick(float dt, Mood mood)
        {
            _stateTime += dt;
            _timer -= dt;
            switch (State)
            {
                case CritterState.Walk:
                case CritterState.Peek when Position != Target:
                case CritterState.Huddle when Position != Target:
                    Position = Vector3.MoveTowards(Position, Target, WalkSpeed * dt);
                    if (State == CritterState.Walk && Position == Target) Decide(mood);
                    break;
                case CritterState.Jump:
                    if (_stateTime >= JumpSeconds)
                    {
                        Position = Target;
                        Decide(mood);
                    }
                    break;
                case CritterState.Tumble:
                    Position = Vector3.Lerp(Position, Target, Mathf.Clamp01(dt * 4));
                    if (_timer <= 0)
                    {
                        Position = Target;
                        Decide(mood);
                    }
                    break;
                default:
                    if (_timer <= 0) Decide(mood);
                    break;
            }
            // 분위기가 바뀌면 오래 기다리지 않고 바로 반응한다
            if (mood.night && State == CritterState.Idle) Enter(CritterState.Sleep, Position, Range(4, 9));
            if (!mood.night && State == CritterState.Sleep) Enter(CritterState.Idle, Position, Range(0.3f, 1));
            if (!mood.tunnel && State == CritterState.Huddle && _timer > 1) _timer = 1;
        }

        void Decide(Mood mood)
        {
            var roam = mood.moving ? 1f : 0.5f; // 정차 중엔 더 자주 움직인다
            if (mood.tunnel)
            {
                var arm = FindSurface("Walk_Armrest", "Walk_RearSeat");
                if (arm >= 0 && arm != Surface && IsNeighbor(arm)) { JumpTo(arm); return; }
                Enter(CritterState.Huddle, _g.RandomPoint(Surface, _rng), Range(3, 6));
                return;
            }
            if (mood.night && _rng.NextDouble() < 0.7)
            {
                Enter(CritterState.Sleep, Position, Range(5, 10));
                return;
            }
            if (mood.rain && _rng.NextDouble() < 0.6)
            {
                var sill = _g.Surfaces[Surface].name.StartsWith("Walk_DoorSill") ? Surface : NeighborStartingWith("Walk_DoorSill");
                if (sill == Surface) { Enter(CritterState.Peek, _g.RandomPoint(Surface, _rng), Range(3, 7)); return; }
                if (sill >= 0) { JumpTo(sill); return; }
            }
            var r = _rng.NextDouble();
            if (State != CritterState.Idle && r < 0.4)
                Enter(CritterState.Idle, Position, Range(0.8f, 2.5f) * roam);
            else if (r < 0.75 || _g.Neighbors(Surface).Count == 0)
                Enter(CritterState.Walk, _g.RandomPoint(Surface, _rng), 0);
            else
                JumpTo(_g.Neighbors(Surface)[_rng.Next(_g.Neighbors(Surface).Count)]);
        }

        void JumpTo(int surface)
        {
            JumpFrom = Position;
            Surface = surface;
            Enter(CritterState.Jump, _g.RandomPoint(surface, _rng), JumpSeconds);
        }

        void Enter(CritterState s, Vector3 target, float seconds)
        {
            State = s;
            Target = target;
            _timer = seconds;
            _stateTime = 0;
        }

        bool IsNeighbor(int i)
        {
            foreach (var n in _g.Neighbors(Surface)) if (n == i) return true;
            return false;
        }

        int NeighborStartingWith(string prefix)
        {
            foreach (var n in _g.Neighbors(Surface))
                if (_g.Surfaces[n].name.StartsWith(prefix)) return n;
            return -1;
        }

        int FindSurface(params string[] names)
        {
            foreach (var n in names)
            {
                var i = _g.IndexOf(n);
                if (i >= 0) return i;
            }
            return -1;
        }

        static Vector3 Clamp(Vector3 p, WalkSurface s)
        {
            var hx = Mathf.Max(0, s.size.x / 2 - WalkGraph.EdgeMargin);
            var hz = Mathf.Max(0, s.size.y / 2 - WalkGraph.EdgeMargin);
            return new Vector3(Mathf.Clamp(p.x, s.center.x - hx, s.center.x + hx), s.center.y,
                Mathf.Clamp(p.z, s.center.z - hz, s.center.z + hz));
        }

        float Range(float a, float b) => a + (float)_rng.NextDouble() * (b - a);
    }
}
