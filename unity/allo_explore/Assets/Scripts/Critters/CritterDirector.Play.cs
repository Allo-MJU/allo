using System.Collections;
using System.Collections.Generic;
using Allo.Bridge;
using UnityEngine;

namespace Allo.Critters
{
    /// 차 안 놀이. 판정하지 않고 Flutter 에 의도만 보낸다 (tap·feed·drink·lookTogether, kind 는 문구용).
    ///
    /// - 간식·공 던지기: 버튼으로 손에 들고, 화면을 톡 치거나 튕기면 그쪽으로 날아간다. 동행이 달려가 먹거나 공을 굴려 준다
    /// - 쓰다듬기: 캐릭터 위를 문지르면 기분 좋아하며 하트
    /// - 물병 탭: 컵에 물을 따라 주면 마신다 / 인형 탭: 작은 인형을 안고 잔다 / 쿠션 탭: 쿠션 위에서 통통 뛴다
    /// - 잘 때 탭: 담요를 덮어 준다 (다시 탭하면 깬다) / 실내등을 끄면 존다
    /// - 김 서린 유리에 그림을 그리면 와서 구경한다
    /// - 가끔 창밖에 풍선이 지나간다. 아이가 그쪽을 보면 같이 봤다고 알린다
    public sealed partial class CritterDirector
    {
        string _scene = "road";
        bool _lightsOff;
        Transform _held;
        Toys.Kind _heldKind;
        Transform _blanket;
        CritterView _blanketOn;
        bool _busy;
        float _petHeart, _petSent, _drawSent, _watchAt;
        float _lookTimer = 40;
        Transform _balloon;
        float _balloonAge, _balloonSeen;
        readonly System.Random _play = new(77);
        Allo.Hud _hud;

        Allo.Hud HudOrNull => _hud != null ? _hud : _hud = FindFirstObjectByType<Allo.Hud>();

        void Say(string text, float seconds = 2.4f) => HudOrNull?.Show(text, seconds);

        static Camera Cam => Camera.main;

        // ---------------- 들고 던지기 ----------------

        public bool Holding => _held != null;

        /// 간식(장면에 맞는 것)이나 공을 손에 든다. 다시 누르면 동행 옆에 살짝 내려놓는다
        public void Hold(bool ball)
        {
            var c = Companion;
            if (c == null) { Say("아직 같이 가는 친구가 없어요"); return; }
            var kind = ball ? Toys.Kind.Ball : Toys.SnackFor(_scene);
            if (_held != null)
            {
                var same = _heldKind == kind;
                if (same) { DropNear(c); return; }
                Destroy(_held.gameObject);
            }
            _held = Toys.Make(kind);
            _heldKind = kind;
            Debug.Log($"[Play] hold {kind}");
            _held.SetParent(Cam.transform, false);
            _held.localPosition = new Vector3(0, -0.13f, 0.38f);
            _held.localScale = Vector3.one * 1.3f;
            Say(ball ? "공을 던져 보세요! 화면을 톡 치거나 휙 밀어요" : "간식을 던져 줄까요? 화면을 톡 치거나 휙 밀어요");
        }

        void DropNear(CritterView c)
        {
            var surf = c.Brain.Surface;
            var at = WalkGraph.Clamp(c.Brain.Position + Flat(Cam.transform.position - c.Brain.Position).normalized * 0.12f, _graph.Surfaces[surf]);
            Launch(at, surf, false);
        }

        /// 화면의 한 점으로 던진다 (TapInput 이 손가락을 뗀 자리 + 튕긴 방향으로 조금 더)
        public void Throw(Vector2 screen)
        {
            if (_held == null) return;
            var (at, surf, missed) = Landing(_graph, Cam.ScreenPointToRay(screen));
            Debug.Log($"[Play] throw {_heldKind} → {_graph.Surfaces[surf].name} missed={missed}");
            Launch(at, surf, missed);
        }

        void Launch(Vector3 at, int surf, bool missed)
        {
            var item = _held;
            var kind = _heldKind;
            _held = null;
            item.SetParent(null, true);
            StartCoroutine(Fly(item, kind, at, surf, missed));
        }

        /// 화면 광선이 닿는 걷는 면의 점. 아무 면에도 안 닿으면(빗나감) 광선과 가장 가까운 면 위 점
        public static (Vector3 at, int surf, bool missed) Landing(WalkGraph g, Ray ray)
        {
            var _graph = g;
            var best = -1; var bestT = float.MaxValue; var bestP = Vector3.zero;
            for (var i = 0; i < _graph.Surfaces.Count; i++)
            {
                var s = _graph.Surfaces[i];
                if (ray.direction.y > -1e-4f) continue;
                var t = (s.center.y - ray.origin.y) / ray.direction.y;
                if (t <= 0 || t >= bestT) continue;
                var p = ray.origin + ray.direction * t;
                if (Mathf.Abs(p.x - s.center.x) > s.size.x / 2 + 0.03f || Mathf.Abs(p.z - s.center.z) > s.size.y / 2 + 0.03f) continue;
                best = i; bestT = t; bestP = p;
            }
            if (best >= 0) return (WalkGraph.Clamp(bestP, _graph.Surfaces[best]), best, false);
            // 빗나감: 광선 위 1.2m 지점에서 가장 가까운 면
            var probe = ray.origin + ray.direction * 1.2f;
            var near = 0; var nd = float.MaxValue; var np = Vector3.zero;
            for (var i = 0; i < _graph.Surfaces.Count; i++)
            {
                var q = WalkGraph.Clamp(probe, _graph.Surfaces[i]);
                var d = (q - probe).sqrMagnitude;
                if (d < nd) { nd = d; near = i; np = q; }
            }
            // 노린 곳 바로 앞에 떨어졌으면 빗나간 것으로 치지 않는다
            var floorT = ray.direction.y < -1e-4f ? (np.y - ray.origin.y) / ray.direction.y : -1;
            var aimed = floorT > 0 ? ray.origin + ray.direction * floorT : probe;
            return (np, near, Vector3.Distance(Flat(aimed), Flat(np)) > 0.4f);
        }

        IEnumerator Fly(Transform item, Toys.Kind kind, Vector3 at, int surf, bool missed)
        {
            var from = item.position;
            item.localScale = Vector3.one;
            var dist = Vector3.Distance(from, at);
            var dur = Mathf.Clamp(0.35f + dist * 0.25f, 0.4f, 0.8f);
            var arc = 0.12f + dist * 0.15f;
            for (var t = 0f; t < dur; t += Time.deltaTime)
            {
                var k = t / dur;
                item.position = Vector3.Lerp(from, at, k) + Vector3.up * (Mathf.Sin(k * Mathf.PI) * arc);
                item.Rotate(0, 540 * Time.deltaTime, 0, Space.World);
                yield return null;
            }
            item.position = at;
            // 빗나가면 두 번 통통 튀며 굴러간다
            if (missed || kind == Toys.Kind.Ball)
            {
                var roll = Flat(at - from).normalized * 0.08f;
                var to = WalkGraph.Clamp(at + roll, _graph.Surfaces[surf]);
                for (var b = 0; b < 2; b++)
                for (var t = 0f; t < 0.25f; t += Time.deltaTime)
                {
                    var k = t / 0.25f;
                    item.position = Vector3.Lerp(at, to, (b + k) / 2) + Vector3.up * (Mathf.Sin(k * Mathf.PI) * (b == 0 ? 0.05f : 0.02f));
                    yield return null;
                }
                at = to;
                item.position = at;
            }
            var comfy = Comfy(at, surf);
            if ((comfy - at).sqrMagnitude > 1e-4f)
            {
                var from2 = at;
                for (var t = 0f; t < 0.4f; t += Time.deltaTime)
                {
                    item.position = Vector3.Lerp(from2, comfy, t / 0.4f);
                    yield return null;
                }
                at = comfy;
                item.position = at;
            }
            if (missed) Say("앗, 빗나갔다! 그래도 주우러 가요");
            yield return Toys.IsSnack(kind) ? Eat(item, kind, at, surf) : Fetch(item, at, surf);
        }

        /// 물건 옆으로 간다. 닿거나 timeout 이면 true/false
        IEnumerator Approach(CritterView c, Vector3 at, int surf, float gap)
        {
            var from = Flat(c.Brain.Position - at);
            var stand = at + (from.sqrMagnitude > 1e-4f ? from.normalized : Vector3.back) * gap;
            c.Brain.Hold = true;
            c.Brain.StayAsleep = false;
            RemoveBlanket();
            c.Brain.MoveTo(stand, surf);
            for (var w = 0f; w < 7f && c != null; w += Time.deltaTime)
            {
                if (c.Brain.AtTarget && c.Brain.State != CritterState.Jump) yield break;
                yield return null;
            }
        }

        IEnumerator Eat(Transform item, Toys.Kind kind, Vector3 at, int surf)
        {
            var c = Companion;
            if (c == null) { Destroy(item.gameObject, 2); yield break; }
            _busy = true;
            yield return Approach(c, at, surf, 0.09f);
            for (var bite = 0; bite < 3 && c != null; bite++)
            {
                c.Brain.Hop(0);
                c.Cheer(1.8f);
                Fx.Burst(item.position + Vector3.up * 0.06f, Fx.Heart, critterMaterial, 2, 0.045f, 0.05f);
                item.localScale *= 0.7f;
                yield return new WaitForSeconds(0.45f);
            }
            Destroy(item.gameObject);
            if (c != null)
            {
                Fx.Burst(c.Top, Fx.Heart, critterMaterial, 6, 0.07f);
                FlutterBridge.Send("feed", FlutterBridge.Field("kind", Toys.Code(kind)));
                Debug.Log($"[Play] ate {kind}");
                c.Brain.Hold = false;
            }
            _busy = false;
        }

        /// 공: 달려가서 아이 쪽으로 굴려 준다
        IEnumerator Fetch(Transform ball, Vector3 at, int surf)
        {
            var c = Companion;
            if (c == null) { Destroy(ball.gameObject, 2); yield break; }
            _busy = true;
            yield return Approach(c, at, surf, 0.1f);
            if (c != null)
            {
                c.Brain.Hop(0.05f);
                c.Cheer(1.5f);
                // 같은 면에서 아이 눈에 가장 가까운 편한 자리 쪽으로
                var eye = childEye != null ? childEye.position : Cam.transform.position;
                var to = Comfy(WalkGraph.Clamp(Vector3.Lerp(at, new Vector3(eye.x, at.y, eye.z), 0.6f), _graph.Surfaces[surf]), surf);
                for (var t = 0f; t < 0.8f && ball != null; t += Time.deltaTime)
                {
                    ball.position = Vector3.Lerp(at, to, t / 0.8f);
                    ball.Rotate(Vector3.Cross(Vector3.up, Flat(to - at)).normalized, 600 * Time.deltaTime, Space.World);
                    yield return null;
                }
                Fx.Burst(c.Top, Fx.Heart, critterMaterial, 5, 0.06f);
                FlutterBridge.Send("tap", FlutterBridge.Field("kind", "ball"));
                Debug.Log("[Play] ball back");
                c.Brain.Hold = false;
            }
            _busy = false;
            yield return Shrink(ball, 2.5f);
        }

        IEnumerator Shrink(Transform t, float after)
        {
            yield return new WaitForSeconds(after);
            for (var k = 0f; k < 0.3f && t != null; k += Time.deltaTime)
            {
                t.localScale = Vector3.one * (1 - k / 0.3f);
                yield return null;
            }
            if (t != null) Destroy(t.gameObject);
        }

        // ---------------- 쓰다듬기 ----------------

        /// 문지르는 동안 계속 부른다
        public void Pet(CritterView v)
        {
            if (v == null) return;
            v.Brain.Stay(1.2f);
            v.Cheer(1.2f);
            if (Time.time - _petHeart > 0.3f)
            {
                _petHeart = Time.time;
                Fx.Burst(v.Top, Fx.Heart, critterMaterial, 1, 0.06f, 0.05f);
            }
            if (v.Id == CompanionId && Time.time - _petSent > 3f)
            {
                _petSent = Time.time;
                FlutterBridge.Send("tap", FlutterBridge.Field("kind", "pet"));
                Debug.Log("[Play] pet");
            }
        }

        // ---------------- 차 안 물건 ----------------

        /// 물병: 동행 옆에 컵을 놓으면 홀짝 마신다
        public void Water(Vector3 from)
        {
            var c = Actor; // 동행이 없으면(알만 있을 때) 친구가 대신 논다
            if (c == null || _busy) return;
            StartCoroutine(GiveToy(Toys.Kind.Cup, from, c));
        }

        /// 인형·쿠션: 작은 것이 동행 옆으로 통 날아간다
        public void Toy(Toys.Kind kind, Vector3 from)
        {
            var c = Actor; // 동행이 없으면(알만 있을 때) 친구가 대신 논다
            if (c == null || _busy) return;
            StartCoroutine(GiveToy(kind, from, c));
        }

        IEnumerator GiveToy(Toys.Kind kind, Vector3 from, CritterView c)
        {
            _busy = true;
            Debug.Log($"[Play] toy {kind}");
            var surf = c.Brain.Surface;
            var at = _graph.RandomPoint(surf, _play);
            if (Vector3.Distance(at, c.Brain.Position) > 0.35f)
                at = WalkGraph.Clamp(c.Brain.Position + (at - c.Brain.Position).normalized * 0.25f, _graph.Surfaces[surf]);
            at = Comfy(at, surf);
            var item = Toys.Make(kind);
            for (var t = 0f; t < 0.6f; t += Time.deltaTime)
            {
                var k = t / 0.6f;
                item.position = Vector3.Lerp(from, at, k) + Vector3.up * (Mathf.Sin(k * Mathf.PI) * 0.25f);
                yield return null;
            }
            item.position = at;
            switch (kind)
            {
                case Toys.Kind.Cup:
                    yield return Approach(c, at, surf, 0.08f);
                    for (var sip = 0; sip < 3 && c != null; sip++)
                    {
                        c.Cheer(1);
                        Fx.Burst(at + Vector3.up * 0.07f, Fx.Spark, critterMaterial, 2, 0.035f, 0.03f);
                        yield return new WaitForSeconds(0.5f);
                    }
                    if (c != null) FlutterBridge.Send("drink");
                    break;
                case Toys.Kind.Plush:
                    yield return Approach(c, at, surf, 0.07f);
                    if (c != null)
                    {
                        FlutterBridge.Send("tap", FlutterBridge.Field("kind", "plush"));
                        if (_lightsOff || _mood.night) c.Brain.Nap(8);
                        else c.Brain.Huddle(4);
                        for (var i = 0; i < 4 && c != null; i++)
                        {
                            Fx.Burst(c.Top, Fx.Heart, critterMaterial, 1, 0.06f, 0.04f);
                            yield return new WaitForSeconds(1);
                        }
                    }
                    break;
                case Toys.Kind.Cushion:
                    yield return Approach(c, at, surf, 0f);
                    if (c != null)
                    {
                        FlutterBridge.Send("tap", FlutterBridge.Field("kind", "cushion"));
                        for (var i = 0; i < 4 && c != null; i++)
                        {
                            c.Brain.Hop(0.12f + i * 0.05f);
                            c.Cheer(1);
                            item.localScale = new Vector3(1.1f, 0.6f, 1.1f);
                            yield return new WaitForSeconds(0.1f);
                            item.localScale = Vector3.one;
                            yield return new WaitForSeconds(0.5f);
                        }
                    }
                    break;
            }
            if (c != null) c.Brain.Hold = false;
            _busy = false;
            yield return Shrink(item, kind == Toys.Kind.Plush ? 6 : 1.5f);
        }

        /// 실내등을 끄면 밤처럼 존다
        public void SetLightsOff(bool off)
        {
            _lightsOff = off;
            Debug.Log($"[Play] lights off={off}");
        }

        /// 자는 캐릭터를 탭하면 담요를 덮어 준다. 덮인 걸 다시 탭하면 걷어 내고 깨운다. 처리했으면 true
        public bool ToggleBlanket(CritterView v)
        {
            if (v == null) return false;
            Debug.Log($"[Play] blanket? state={v.Brain.State} on={_blanketOn == v}");
            if (_blanketOn == v)
            {
                RemoveBlanket();
                v.Brain.StayAsleep = false;
                v.Brain.Poke();
                return true;
            }
            if (v.Brain.State != CritterState.Sleep) return false;
            RemoveBlanket();
            _blanket = Toys.Make(Toys.Kind.Blanket);
            _blanket.SetParent(v.transform, false);
            _blanket.localPosition = Vector3.up * (CritterView.Height * 0.35f);
            _blanket.localScale = new Vector3(1.1f, 1, 1.1f);
            _blanketOn = v;
            v.Brain.StayAsleep = true;
            Fx.Burst(v.Top, Fx.Heart, critterMaterial, 3, 0.05f);
            if (v.Id == CompanionId) FlutterBridge.Send("tap", FlutterBridge.Field("kind", "blanket"));
            return true;
        }

        void RemoveBlanket()
        {
            if (_blanket != null) Destroy(_blanket.gameObject);
            _blanket = null;
            if (_blanketOn != null) _blanketOn.Brain.StayAsleep = false;
            _blanketOn = null;
        }

        // ---------------- 김 서린 유리 그림 ----------------

        /// 유리에 그림을 그리는 동안 부른다: 동행이 그 창에 가까운 자리로 와서 구경한다
        public void Watch(Vector3 glassPoint)
        {
            var c = Actor; // 동행이 없으면(알만 있을 때) 친구가 대신 논다
            if (c == null || _busy || Time.time - _watchAt < 2.5f) return;
            _watchAt = Time.time;
            var near = 0; var nd = float.MaxValue; var np = Vector3.zero;
            for (var i = 0; i < _graph.Surfaces.Count; i++)
            {
                var q = WalkGraph.Clamp(glassPoint, _graph.Surfaces[i]);
                var d = (q - glassPoint).sqrMagnitude;
                if (d < nd) { nd = d; near = i; np = q; }
            }
            np = Comfy(np, near);
            Debug.Log($"[Play] watch → {_graph.Surfaces[near].name}");
            StartCoroutine(GoWatch(c, np, near));
        }

        IEnumerator GoWatch(CritterView c, Vector3 at, int surf)
        {
            _busy = true;
            yield return Approach(c, at, surf, 0);
            if (c != null)
            {
                c.Brain.Peek(3);
                c.Brain.Hold = false;
            }
            _busy = false;
        }

        /// 그림을 다 그렸다 (손을 뗌)
        public void DrawDone()
        {
            var c = Actor; // 동행이 없으면(알만 있을 때) 친구가 대신 논다
            if (c == null || Time.time - _drawSent < 5f) return;
            _drawSent = Time.time;
            c.Cheer(1.5f);
            Fx.Burst(c.Top, Fx.Heart, critterMaterial, 3, 0.06f);
            FlutterBridge.Send("tap", FlutterBridge.Field("kind", "draw"));
        }

        // ---------------- 같이 창밖 보기 (풍선) ----------------

        void PlayTick(float dt)
        {
            if (_balloon != null) { BalloonTick(dt); return; }
            if (Companion == null || _busy || Holding || !_mood.moving || _mood.tunnel) return;
            _lookTimer -= dt;
            if (_lookTimer > 0) return;
            _lookTimer = 50 + (float)_play.NextDouble() * 40;
            SpawnBalloon();
        }

        Vector3 Eye => childEye != null ? childEye.position : Cam.transform.position;

        Vector3 Fwd => frontEye != null && childEye != null ? Forward : Flat(Cam.transform.forward).normalized;

        void SpawnBalloon()
        {
            var right = Vector3.Cross(Vector3.up, Fwd).normalized;
            var c = Companion;
            var side = c != null && Vector3.Dot(c.Brain.Position - Eye, right) < 0 ? -1 : 1;
            _balloon = Toys.Make(Toys.Kind.Balloon);
            _balloon.position = Eye + right * (side * 9) + Fwd * 9 + Vector3.down * 1.2f;
            _balloonAge = 0;
            _balloonSeen = 0;
            if (c != null && c.Brain.State != CritterState.Sleep)
            {
                c.Brain.Peek(5);
                Fx.Burst(c.Top, Fx.Spark, critterMaterial, 3, 0.05f);
            }
            Debug.Log($"[Play] balloon side={side}");
            Say(side > 0 ? "오른쪽 창밖에 풍선이 있어요! 같이 볼까요?" : "왼쪽 창밖에 풍선이 있어요! 같이 볼까요?");
        }

        void BalloonTick(float dt)
        {
            _balloonAge += dt;
            // 차보다 조금 느리게 날아 천천히 뒤로 지나간다
            _balloon.position += (-Fwd * 1.2f + Vector3.up * 0.15f) * dt;
            _balloon.Rotate(0, 20 * dt, 0);
            var cam = Cam;
            var to = _balloon.position + Vector3.up * 1.6f - cam.transform.position;
            if (Vector3.Angle(cam.transform.forward, to) < 16) _balloonSeen += dt;
            if (_balloonSeen > 0.4f)
            {
                Fx.Burst(_balloon.position + Vector3.up * 1.6f, Fx.Spark, critterMaterial, 8, 0.8f, 0.8f);
                var c = Companion;
                if (c != null)
                {
                    c.Cheer(2);
                    c.Brain.Hop(0.08f);
                    Fx.Burst(c.Top, Fx.Heart, critterMaterial, 5, 0.06f);
                }
                FlutterBridge.Send("lookTogether");
                Debug.Log("[Play] looked together");
                Destroy(_balloon.gameObject);
                _balloon = null;
                return;
            }
            if (_balloonAge > 14)
            {
                Destroy(_balloon.gameObject);
                _balloon = null;
            }
        }

        static Vector3 Flat(Vector3 v) => new(v.x, 0, v.z);

        /// p 가 아이에게 잘 안 보이는 자리(발밑·바로 옆)면, 같은 면에서 잘 보이는 가장 가까운 자리로 옮긴다
        Vector3 Comfy(Vector3 p, int surf)
        {
            if (_graph.Comfortable == null || _graph.Comfortable(p)) return p;
            var best = p; var bd = float.MaxValue;
            for (var i = 0; i < 48; i++)
            {
                var q = _graph.RandomPoint(surf, _play);
                if (!_graph.Comfortable(q)) continue;
                var d = (q - p).sqrMagnitude;
                if (d < bd) { bd = d; best = q; }
            }
            return best;
        }
    }
}
