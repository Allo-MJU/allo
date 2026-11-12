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

        /// 점프를 보통보다 이만큼(m) 더 높이 (쿠션 트램펄린)
        public float JumpBoost { get; private set; }

        /// 놀이 중 (먹이·공·인형). 목적지에 닿아도 제멋대로 돌아다니지 않고 기다린다
        public bool Hold;

        /// 담요를 덮었다. 깨울 때까지 계속 잔다
        public bool StayAsleep;

        /// 이 시간(초) 동안은 밤·터널이어도 잠들지 않는다 (알에서 막 깨어났을 때)
        public float AwakeFor;

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

        /// 탭 반응: 제자리에서 폴짝 뛴다 (구르는 중이면 무시)
        public void Poke()
        {
            if (State == CritterState.Tumble) return;
            var s = _g.Surfaces[Surface];
            JumpFrom = Position;
            Enter(CritterState.Jump, Clamp(Position + new Vector3(Range(-0.1f, 0.1f), 0, Range(-0.1f, 0.1f)), s), JumpSeconds);
        }

        /// 같은 면 안의 한 점으로 걸어간다 (먹이 쪽). 도착하면 평소 행동으로 돌아간다
        public void GoTo(Vector3 target)
        {
            if (State == CritterState.Tumble) return;
            Enter(CritterState.Walk, Clamp(target, _g.Surfaces[Surface]), 0);
        }

        public bool AtTarget => Position == Target;

        /// 다른 면의 한 점으로 간다: 같은 면이면 걷고, 아니면 그 점으로 바로 뛴다 (던진 먹이를 쫓을 때)
        public void MoveTo(Vector3 target, int surface)
        {
            if (State == CritterState.Tumble) return;
            surface = Mathf.Clamp(surface, 0, _g.Surfaces.Count - 1);
            var p = WalkGraph.Clamp(target, _g.Surfaces[surface]);
            if (surface == Surface)
            {
                Enter(CritterState.Walk, p, 0);
                return;
            }
            JumpFrom = Position;
            Surface = surface;
            Enter(CritterState.Jump, p, JumpSeconds);
        }

        /// 그 면의 한 점에 바로 세운다 (알에서 깨어난 자리). 하던 행동은 멈춘다
        public void Place(Vector3 at, int surface)
        {
            Surface = Mathf.Clamp(surface, 0, _g.Surfaces.Count - 1);
            Position = Target = WalkGraph.Clamp(at, _g.Surfaces[Surface]);
            JumpFrom = Position;
            State = CritterState.Idle;
            _stateTime = 0;
            _timer = Range(1.5f, 3f);
        }

        /// 제자리에서 높이 뛴다 (boost m 만큼 더)
        public void Hop(float boost)
        {
            if (State == CritterState.Tumble) return;
            JumpFrom = Position;
            Enter(CritterState.Jump, Position, JumpSeconds);
            JumpBoost = boost;
        }

        /// 그 자리에서 seconds 동안 가만히 (쓰다듬기)
        public void Stay(float seconds)
        {
            if (State is CritterState.Tumble or CritterState.Jump) return;
            Enter(CritterState.Idle, Position, seconds);
        }

        /// 그 자리에서 웅크리거나(인형 안기) 창밖을 보거나(그림 구경) 잔다
        public void Huddle(float seconds) => Enter(CritterState.Huddle, Position, seconds);
        public void Peek(float seconds) => Enter(CritterState.Peek, Position, seconds);
        public void Nap(float seconds) => Enter(CritterState.Sleep, Position, seconds);

        public void Tick(float dt, Mood mood)
        {
            _stateTime += dt;
            _timer -= dt;
            if (AwakeFor > 0) AwakeFor -= dt;
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
            if (StayAsleep && State == CritterState.Idle) Enter(CritterState.Sleep, Position, 3);
            if (Hold) return;
            if (mood.night && AwakeFor <= 0 && State == CritterState.Idle) Enter(CritterState.Sleep, Position, Range(4, 9));
            if (!mood.night && !StayAsleep && State == CritterState.Sleep) Enter(CritterState.Idle, Position, Range(0.3f, 1));
            if (!mood.tunnel && State == CritterState.Huddle && _timer > 1) _timer = 1;
        }

        void Decide(Mood mood)
        {
            if (StayAsleep) { Enter(CritterState.Sleep, Position, 3); return; }
            if (Hold) { Enter(CritterState.Idle, Position, 0.5f); return; }
            var roam = mood.moving ? 1f : 0.5f; // 정차 중엔 더 자주 움직인다
            if (mood.tunnel)
            {
                var arm = FindSurface("Walk_Armrest", "Walk_RearSeat_L", "Walk_RearSeat_R");
                if (arm >= 0 && arm != Surface && IsNeighbor(arm)) { JumpTo(arm); return; }
                Enter(CritterState.Huddle, _g.RandomPoint(Surface, _rng), Range(3, 6));
                return;
            }
            if (mood.night && AwakeFor <= 0 && _rng.NextDouble() < 0.7)
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
                JumpTo(PickNeighbor());
        }

        /// 이웃 면을 고른다. 앞좌석 사이 바닥은 정면 화면 아래 밖이라 다른 면의 1/4 만 고른다
        int PickNeighbor()
        {
            var ns = _g.Neighbors(Surface);
            var total = 0f;
            foreach (var n in ns) total += Weight(n);
            var r = (float)_rng.NextDouble() * total;
            foreach (var n in ns)
            {
                r -= Weight(n);
                if (r <= 0) return n;
            }
            return ns[ns.Count - 1];
        }

        float Weight(int surface) => _g.Surfaces[surface].name == "Walk_Floor" ? 0.25f : 1f;

        void JumpTo(int surface)
        {
            JumpFrom = Position;
            Surface = surface;
            Enter(CritterState.Jump, _g.RandomPoint(surface, _rng), JumpSeconds);
        }

        void Enter(CritterState s, Vector3 target, float seconds)
        {
            JumpBoost = 0;
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

        static Vector3 Clamp(Vector3 p, WalkSurface s) => WalkGraph.Clamp(p, s);

        float Range(float a, float b) => a + (float)_rng.NextDouble() * (b - a);
    }
}
