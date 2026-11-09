using System.Collections.Generic;
using System.Linq;
using Allo.Bridge;

namespace Allo.Critters
{
    /// cast 메시지가 올 때 새로 만들 캐릭터와 치울 캐릭터를 고른다. 같은 캐릭터는 다시 만들지 않는다.
    public static class CastDiff
    {
        public static IEnumerable<CastMember> Members(CastState cast)
        {
            var seen = new HashSet<string>();
            if (cast.companion != null && !string.IsNullOrEmpty(cast.companion.id) && seen.Add(cast.companion.id))
                yield return cast.companion;
            foreach (var f in cast.friends ?? new CastMember[0])
                if (f != null && !string.IsNullOrEmpty(f.id) && seen.Add(f.id))
                    yield return f;
        }

        public static (List<string> add, List<string> remove) Compute(IEnumerable<string> current, CastState cast)
        {
            var want = Members(cast).Select(m => m.id).ToList();
            var have = current.ToList();
            return (want.Where(id => !have.Contains(id)).ToList(), have.Where(id => !want.Contains(id)).ToList());
        }
    }
}
