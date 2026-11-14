using System.Collections;
using UnityEngine;

namespace Allo.Critters
{
    public sealed partial class CritterDirector
    {
        Coroutine _commonCare;
        Transform _commonToy;
        CritterView _commonActor;

        // The host has already accepted this action. This path emits no legacy reward intents.
        public bool PlayCommonCare(string speciesId, string actionId, bool reducedMotion = false)
        {
            if (!isActiveAndEnabled || string.IsNullOrEmpty(speciesId) || !_views.TryGetValue(speciesId, out var actor) ||
                _graph == null || _graph.Surfaces.Count == 0 || !IsCommonCare(actionId)) return false;
            CancelCommonCare();
            _commonActor = actor;
            _commonCare = StartCoroutine(CommonCare(actor, actionId, reducedMotion));
            return true;
        }

        public static bool IsCommonCare(string actionId) => actionId == "snack" || actionId == "water" || actionId == "ball" ||
            actionId == "pet" || actionId == "plush" || actionId == "cushion" || actionId == "blanket";

        public void CancelCommonCare()
        {
            if (_commonCare != null) StopCoroutine(_commonCare);
            _commonCare = null;
            if (_commonActor != null) { _commonActor.Brain.Hold = false; _commonActor.Brain.StayAsleep = false; }
            _commonActor = null;
            if (_commonToy != null)
                if (Application.isPlaying) Destroy(_commonToy.gameObject); else DestroyImmediate(_commonToy.gameObject);
            _commonToy = null;
        }

        IEnumerator CommonCare(CritterView actor, string actionId, bool reducedMotion)
        {
            actor.Brain.StayAsleep = false;
            RemoveBlanket();
            actor.Cheer(2f);
            if (!reducedMotion) Fx.Burst(actor.Top, Fx.Heart, critterMaterial, 4, 0.05f);
            if (actionId == "pet")
            {
                actor.Brain.Stay(1.5f);
                yield return new WaitForSeconds(1.5f);
            }
            else
            {
                var kind = actionId == "snack" ? Toys.SnackFor(_scene) : Allo.App.CabinEgg.CareToyKind(actionId);
                _commonToy = Toys.Make(kind); _commonToy.SetParent(transform, true);
                var surface = actor.Brain.Surface;
                var at = WalkGraph.Clamp(actor.Brain.Position + Vector3.right * 0.14f, _graph.Surfaces[surface]);
                _commonToy.position = at;
                if (actionId == "blanket")
                {
                    _commonToy.SetParent(actor.transform, false);
                    _commonToy.localPosition = Vector3.up * CritterView.Height * 0.35f;
                    actor.Brain.Nap(4f); actor.Brain.StayAsleep = true;
                    yield return new WaitForSeconds(4f);
                }
                else
                {
                    if (!reducedMotion) yield return Approach(actor, at, surface, actionId == "cushion" ? 0 : 0.08f);
                    if (actor == null || _commonToy == null) { CancelCommonCare(); yield break; }
                    if (actionId == "plush") actor.Brain.Huddle(3f);
                    for (var beat = 0; beat < 3 && actor != null && _commonToy != null; beat++)
                    {
                        actor.Cheer(1f);
                        if (!reducedMotion)
                        {
                            if (actionId == "cushion") actor.Brain.Hop(0.1f);
                            Fx.Burst(actor.Top, actionId == "water" ? Fx.Spark : Fx.Heart, critterMaterial, 2, 0.04f);
                        }
                        if (actionId == "snack") _commonToy.localScale *= 0.72f;
                        if (actionId == "ball" && !reducedMotion)
                        {
                            var from = _commonToy.position;
                            var to = WalkGraph.Clamp(from + Vector3.forward * (beat % 2 == 0 ? 0.14f : -0.14f), _graph.Surfaces[surface]);
                            for (var t = 0f; t < 0.5f && _commonToy != null; t += Time.deltaTime)
                            {
                                _commonToy.position = Vector3.Lerp(from, to, t / 0.5f);
                                _commonToy.Rotate(Vector3.right, 450f * Time.deltaTime);
                                yield return null;
                            }
                        }
                        else yield return new WaitForSeconds(0.7f);
                    }
                }
            }
            _commonCare = null;
            CancelCommonCare();
        }
    }
}
