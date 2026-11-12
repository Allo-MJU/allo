using Allo.Bridge;

namespace Allo.Critters
{
    /// egg 메시지가 올 때 둥지의 알을 어떻게 바꿀지 고른다. 순수 로직이라 EditMode 테스트로 확인한다.
    ///
    /// - incubating 이 오면 알을 둔다 (다른 eggId 면 새 알로 바꾼다)
    /// - 둥지에 있던 알과 같은 eggId 가 hatched 로 오면 깨어난다 (한 번만)
    /// - 처음부터 hatched 로 오거나 다른 알이 hatched 로 오면 연출 없이 알을 치운다
    public sealed class EggTracker
    {
        public enum Change { None, Appear, Replace, Update, Hatch, Vanish }

        public bool Present { get; private set; }
        public string EggId { get; private set; }

        /// 금이 가는 단계: 0 없음, 1 (50% 이상), 2 (80% 이상), 3 (95% 이상, 곧 깨어남)
        public static int CrackStage(float progress) => progress >= 0.95f ? 3 : progress >= 0.8f ? 2 : progress >= 0.5f ? 1 : 0;

        public Change Apply(EggState e)
        {
            if (e == null) return Change.None;
            var id = e.eggId ?? "";
            switch (e.state)
            {
                case "incubating":
                    if (!Present)
                    {
                        Present = true;
                        EggId = id;
                        return Change.Appear;
                    }
                    if (id != EggId)
                    {
                        EggId = id;
                        return Change.Replace;
                    }
                    return Change.Update;
                case "hatched":
                    if (!Present) return Change.None;
                    Present = false;
                    return id == EggId ? Change.Hatch : Change.Vanish;
                default:
                    if (!Present) return Change.None;
                    Present = false;
                    return Change.Vanish;
            }
        }
    }
}
