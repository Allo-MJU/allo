using System.Collections;
using UnityEngine;

namespace Allo.Critters
{
    public sealed partial class CritterDirector
    {
        Coroutine _commonCare;
        Transform _commonToy;
        CritterView _commonActor;
        string _cabinCareSpecies, _cabinCareAction;
        Vector3 _cabinCarePosition;
        int _cabinCareSurface;
        float _cabinCareDeadline;

        public bool TryCabinLanding(Ray ray, out Vector3 at, out int surface)
        {
            at = Vector3.zero; surface = -1;
            if (_graph == null || _graph.Surfaces.Count == 0) return false;
            var landing = Landing(_graph, ray);
            at = landing.at; surface = landing.surf;
            return true;
        }

        public bool TryCabinRestSpot(string action, out Vector3 at, out int surface)
        {
            at = Vector3.zero; surface = -1;
            if (_graph == null || (action != "cushion" && action != "blanket")) return false;
            surface = _graph.IndexOf(action == "cushion" ? "Walk_DoorSill_L" : "Walk_DoorSill_R");
            if (surface < 0) return false;
            at = WalkGraph.Clamp(_graph.Surfaces[surface].center, _graph.Surfaces[surface]);
            return true;
        }

        // Presentation correlation only: the host still decides whether the care action is accepted.
        public void QueueCabinCareLanding(string species, string action, Vector3 at, int surface)
        {
            if (_graph == null || surface < 0 || surface >= _graph.Surfaces.Count) return;
            _cabinCareSpecies = species; _cabinCareAction = action;
            _cabinCarePosition = WalkGraph.Clamp(at, _graph.Surfaces[surface]); _cabinCareSurface = surface;
            _cabinCareDeadline = Time.unscaledTime + 5;
        }

        public void ClearCabinCareLanding() { _cabinCareSpecies = _cabinCareAction = null; }

        public bool PlaceCabinCompanion(string species, Vector3 at, int surface)
        {
            if (_graph == null || surface < 0 || surface >= _graph.Surfaces.Count || Companion == null || Companion.Id != species) return false;
            CancelCommonCare();
            Companion.Brain.Place(at, surface);
            Companion.Brain.Stay(3);
            Companion.Brain.StayAsleep = false;
            return true;
        }

        // The host has already accepted this action. This path emits no legacy reward intents.
        public bool PlayCommonCare(string speciesId, string actionId, bool reducedMotion = false)
        {
            if (!isActiveAndEnabled || string.IsNullOrEmpty(speciesId) || !_views.TryGetValue(speciesId, out var actor) ||
                _graph == null || _graph.Surfaces.Count == 0 || !IsCommonCare(actionId)) return false;
            CancelCommonCare();
            _commonActor = actor;
            var surface = actor.Brain.Surface;
            var at = WalkGraph.Clamp(actor.Brain.Position + Vector3.right * .14f, _graph.Surfaces[surface]);
            if (_cabinCareSpecies == speciesId && _cabinCareAction == actionId && Time.unscaledTime <= _cabinCareDeadline)
            { at = _cabinCarePosition; surface = _cabinCareSurface; }
            else if (Allo.App.AppSession.State != null && (actionId == "cushion" || actionId == "blanket"))
                TryCabinRestSpot(actionId, out at, out surface);
            ClearCabinCareLanding();
            if (surface < 0) surface = actor.Brain.Surface;
            _commonCare = StartCoroutine(CommonCare(actor, actionId, reducedMotion, at, surface));
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

        IEnumerator CommonCare(CritterView actor, string actionId, bool reducedMotion, Vector3 at, int surface)
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
            else if (Allo.App.AppSession.State != null && (actionId == "cushion" || actionId == "blanket"))
            {
                // Fixed patches stay where the child can see them; do not create a second prop at the actor.
                actor.Brain.Hold = true;
                actor.Brain.Place(at, surface);
                if (actionId == "blanket")
                {
                    actor.Brain.Nap(4); actor.Brain.StayAsleep = true;
                    yield return new WaitForSeconds(4);
                }
                else
                {
                    for (var beat = 0; beat < 3 && actor != null; beat++)
                    {
                        if (!reducedMotion) actor.Brain.Hop(.1f);
                        actor.Cheer(1); yield return new WaitForSeconds(.7f);
                    }
                }
            }
            else
            {
                var kind = actionId == "snack" ? Toys.SnackFor(_scene) : Allo.App.CabinEgg.CareToyKind(actionId);
                _commonToy = Toys.Make(kind); _commonToy.SetParent(transform, true);
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
