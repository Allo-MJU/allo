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
        float _petHeart, _petSent, _petTalk, _drawSent, _watchAt;
        float _lookTimer = 30;
        Transform _sky;         // 창밖 손님 (풍선·연·새·비행기·별똥별·고래)
        float _skyAge, _skySeen;
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
                Speak("snack", null, 3f, c);
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
                Speak("ball", "*", 3f, c);
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
            if (Time.time - _petTalk > 9f && v.Brain.State != CritterState.Sleep)
            {
                _petTalk = Time.time;
                Speak("pet", "*", 2.6f, v);
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
        /// 옆자리 인형·쿠션을 탭: 동행에게 건넨다. real 이 있으면(3D 모델) 그 물건이 직접 날아갔다가 놀이 뒤 제자리로 돌아오고,
        /// 없으면(도형) 작은 복사본을 던졌다가 줄여 없앤다
        public void Toy(Toys.Kind kind, Vector3 from, Transform real = null)
        {
            var c = Actor; // 동행이 없으면(알만 있을 때) 친구가 대신 논다
            if (c == null || _busy || (real != null && _propBusy.Contains(real))) return;
            StartCoroutine(GiveToy(kind, from, c, real));
        }

        /// 쿠션을 눕혔을 때 두께 배율 (세운 쿠션 두께 13cm → 약 6cm 방석). 동행이 위에서 통통 뛴다
        const float CushionFlat = 0.5f;

        IEnumerator GiveToy(Toys.Kind kind, Vector3 from, CritterView c, Transform real = null)
        {
            _busy = true;
            Debug.Log($"[Play] toy {kind} real={real != null}");
            var surf = c.Brain.Surface;
            var at = _graph.RandomPoint(surf, _play);
            if (Vector3.Distance(at, c.Brain.Position) > 0.35f)
                at = WalkGraph.Clamp(c.Brain.Position + (at - c.Brain.Position).normalized * 0.25f, _graph.Surfaces[surf]);
            at = Comfy(at, surf);
            Transform item;
            Vector3 homePos = default, homeScale = default;
            Quaternion homeRot = default;
            var lay = kind == Toys.Kind.Cushion;
            if (real != null)
            {
                item = real;
                _propBusy.Add(real);
                homePos = real.position; homeRot = real.rotation; homeScale = real.localScale;
                from = real.position;
            }
            else item = Toys.Make(kind);
            // 날아가는 동안 동행 쪽을 보게 돌리고, 쿠션은 등을 대고 눕힌다(앞면이 위). 눕힌 쿠션의 가운데가 at 에 오게 맞춘다
            var face = Quaternion.LookRotation(Flat(Eye - at).normalized);
            var endRot = real == null ? item.rotation : lay ? face * Quaternion.Euler(-90, 0, 0) : face;
            var endScale = real != null && lay ? Vector3.Scale(homeScale, new Vector3(1, 1, CushionFlat)) : item.localScale;
            var endPos = at;
            if (real != null && lay)
            {
                var keep = (item.rotation, item.localScale, item.position);
                item.SetPositionAndRotation(at, endRot);
                item.localScale = endScale;
                var b = Toys.BoundsOf(item);
                endPos = at + new Vector3(at.x - b.center.x, at.y - b.min.y, at.z - b.center.z);
                (item.rotation, item.localScale, item.position) = keep;
            }
            var startRot = item.rotation;
            var startScale = item.localScale;
            for (var t = 0f; t < 0.6f; t += Time.deltaTime)
            {
                var k = t / 0.6f;
                item.position = Vector3.Lerp(from, endPos, k) + Vector3.up * (Mathf.Sin(k * Mathf.PI) * 0.25f);
                if (real != null)
                {
                    item.rotation = Quaternion.Slerp(startRot, endRot, k);
                    item.localScale = Vector3.Lerp(startScale, endScale, k);
                }
                yield return null;
            }
            item.position = endPos;
            item.rotation = endRot;
            item.localScale = endScale;
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
                    yield return Approach(c, at, surf, real != null ? 0.18f : 0.07f); // 진짜 인형은 동행만큼 커서 몸 반 너비만큼 떨어져 붙는다
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
                            // 눌렸다 펴지기: 도형은 세로(y), 눕힌 모델은 두께(로컬 z)를 누른다
                            item.localScale = real != null ? Vector3.Scale(endScale, new Vector3(1.1f, 1.1f, 0.6f)) : new Vector3(1.1f, 0.6f, 1.1f);
                            yield return new WaitForSeconds(0.1f);
                            item.localScale = real != null ? endScale : Vector3.one;
                            yield return new WaitForSeconds(0.5f);
                        }
                    }
                    break;
            }
            if (c != null) c.Brain.Hold = false;
            _busy = false;
            if (real == null)
            {
                yield return Shrink(item, kind == Toys.Kind.Plush ? 6 : 1.5f);
                yield break;
            }
            // 진짜 물건: 조금 두었다가 제자리로 날아가 다시 선다
            yield return new WaitForSeconds(kind == Toys.Kind.Plush ? 6 : 1.5f);
            var p0 = item.position; var r0 = item.rotation; var s0 = item.localScale;
            for (var t = 0f; t < 0.7f; t += Time.deltaTime)
            {
                var k = t / 0.7f;
                item.position = Vector3.Lerp(p0, homePos, k) + Vector3.up * (Mathf.Sin(k * Mathf.PI) * 0.25f);
                item.rotation = Quaternion.Slerp(r0, homeRot, k);
                item.localScale = Vector3.Lerp(s0, homeScale, k);
                yield return null;
            }
            item.SetPositionAndRotation(homePos, homeRot);
            item.localScale = homeScale;
            _propBusy.Remove(real);
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
                Speak("wake", "*", 2.8f, v);
                return true;
            }
            if (v.Brain.State != CritterState.Sleep) return false;
            RemoveBlanket();
            _blanket = Toys.Make(Toys.Kind.Blanket);
            _blanket.SetParent(v.transform, false);
            _blanket.localPosition = Vector3.zero; // 발 자리에 돔을 씌운다 (그림 아래 절반을 가려 머리만 내놓는다)
            _blanket.rotation = Quaternion.LookRotation(Flat(Cam.transform.position - v.transform.position).normalized); // 접힌 윗단이 카메라 쪽
            if (v.Is3D)
            {
                // 3D 몸은 그림보다 길고 높다: 돔을 몸이 보는 쪽으로 돌려 몸 크기에 맞추고 키 절반까지 올려 머리만 내놓는다
                var f = v.Footprint;
                var H = CritterView.Height;
                _blanket.rotation = Quaternion.Euler(0, v.Yaw, 0);
                // 높이: 도형 돔은 1.7배면 등까지 왔지만, 담요 모델(키 0.10m)은 2.4배라야 등을 덮는다
                var high = Toys.PropModel(Toys.Kind.Blanket) != null ? 2.4f : 1.7f;
                _blanket.localScale = new Vector3(f.x * 1.3f / (1.2f * H), high, f.y * 0.8f / (0.95f * H));
            }
            _blanketOn = v;
            v.Brain.StayAsleep = true;
            Fx.Burst(v.Top, Fx.Heart, critterMaterial, 3, 0.05f);
            Speak("blanket", "*", 3f, v);
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
            if (_sky != null) { SkyTick(dt); return; }
            if (Companion == null || _busy || Holding || !_mood.moving || _mood.tunnel) return;
            _lookTimer -= dt;
            if (_lookTimer > 0) return;
            _lookTimer = 32 + (float)_play.NextDouble() * 25;
            SpawnSky();
        }

        Vector3 Eye => childEye != null ? childEye.position : Cam.transform.position;

        Vector3 Fwd => frontEye != null && childEye != null ? Forward : Flat(Cam.transform.forward).normalized;

        /// 장면에 어울리는 창밖 손님을 고른다. 비·터널에서는 없다
        Toys.Kind? PickSky()
        {
            if (_mood.tunnel || _mood.rain) return null;
            Toys.Kind[] pool = _mood.night ? new[] { Toys.Kind.Star, Toys.Kind.Star, Toys.Kind.Plane }
                : _scene switch
                {
                    "coast" => new[] { Toys.Kind.Whale, Toys.Kind.Birds, Toys.Kind.Kite },
                    "mountain" => new[] { Toys.Kind.Balloon, Toys.Kind.Birds, Toys.Kind.Kite },
                    "city" => new[] { Toys.Kind.Kite, Toys.Kind.Plane, Toys.Kind.Balloon },
                    "highway" => new[] { Toys.Kind.Plane, Toys.Kind.Birds, Toys.Kind.Balloon },
                    _ => new[] { Toys.Kind.Balloon, Toys.Kind.Birds, Toys.Kind.Kite },
                };
            return pool[_play.Next(pool.Length)];
        }

        static string SkyName(Toys.Kind k) => k switch
        {
            Toys.Kind.Kite => "kite", Toys.Kind.Birds => "birds", Toys.Kind.Plane => "plane",
            Toys.Kind.Star => "star", Toys.Kind.Whale => "whale", _ => "balloon",
        };

        /// 창밖 손님: 풍선·연·새 떼·비행기·별똥별·고래. 옆 창 밖에 나타나 천천히 지나간다.
        /// 동행이 그쪽을 보며 말하고, 아이가 그쪽을 보면 같이 봤다고 알린다
        void SpawnSky()
        {
            var kind = PickSky();
            if (kind == null) return;
            var right = Vector3.Cross(Vector3.up, Fwd).normalized;
            var c = Companion;
            var side = c != null && Vector3.Dot(c.Brain.Position - Eye, right) < 0 ? -1 : 1;
            _skyKind = kind.Value;
            _sky = Toys.Make(_skyKind);
            _skySide = side;
            _skyAge = 0;
            _skySeen = 0;
            var basePos = Eye + right * (side * 9) + Fwd * 9;
            switch (_skyKind)
            {
                case Toys.Kind.Kite: _sky.position = basePos + Vector3.up * 1.5f; _sky.localScale = Vector3.one * 0.9f; break;
                case Toys.Kind.Birds: _sky.position = basePos + Fwd * 4 + Vector3.up * 2.2f; _sky.localScale = Vector3.one * 0.7f; break;
                case Toys.Kind.Plane: _sky.position = Eye + right * (side * 14) + Fwd * 30 + Vector3.up * 9f; _sky.localScale = Vector3.one * 1.6f; break;
                case Toys.Kind.Star: _sky.position = Eye + right * (side * 12) + Fwd * 10 + Vector3.up * 8f; _sky.localScale = Vector3.one * 0.9f; break;
                case Toys.Kind.Whale: _sky.position = Eye + right * (side * 16) + Fwd * 6 + Vector3.down * 1.2f; _sky.localScale = Vector3.one * 1.3f; break;
                default: _sky.position = basePos + Vector3.down * 1.2f; break;
            }
            _skyLook = _skyKind == Toys.Kind.Balloon ? Vector3.up * 1.6f : Vector3.up * 0.5f;
            if (c != null && c.Brain.State != CritterState.Sleep)
            {
                c.Brain.Peek(5);
                Fx.Burst(c.Top, Fx.Spark, critterMaterial, 3, 0.05f);
            }
            Debug.Log($"[Play] sky {_skyKind} side={side}");
            var name = SkyName(_skyKind);
            if (Speak("window", name, 3.6f) == null)
                Say((side > 0 ? "오른쪽" : "왼쪽") + " 창밖을 봐요! 같이 볼까요?");
        }

        Toys.Kind _skyKind;
        int _skySide;
        Vector3 _skyLook;

        void SkyTick(float dt)
        {
            _skyAge += dt;
            var t = _skyAge;
            switch (_skyKind)
            {
                case Toys.Kind.Kite:
                    _sky.position += (-Fwd * 0.9f + Vector3.up * 0.12f) * dt;
                    _sky.rotation = Quaternion.LookRotation(Flat(Eye - _sky.position).normalized) * Quaternion.Euler(Mathf.Sin(t * 1.7f) * 14, 0, Mathf.Sin(t * 2.3f) * 18);
                    break;
                case Toys.Kind.Birds:
                    _sky.position += (-Fwd * 0.6f + Vector3.up * 0.05f + Vector3.Cross(Vector3.up, Fwd) * _skySide * -0.3f) * dt;
                    _sky.rotation = Quaternion.LookRotation(Flat(Eye - _sky.position).normalized);
                    foreach (Transform w in _sky)
                    {
                        if (w.name == "WingL") w.localRotation = Quaternion.Euler(0, 0, 10 + Mathf.Sin(t * 9) * 35);
                        else if (w.name == "WingR") w.localRotation = Quaternion.Euler(0, 0, -10 - Mathf.Sin(t * 9) * 35);
                    }
                    break;
                case Toys.Kind.Plane:
                    _sky.position += (-Fwd * 6f) * dt; // 하늘 높이 앞에서 뒤로
                    _sky.rotation = Quaternion.LookRotation(Vector3.Cross(Vector3.up, -Fwd)) * Quaternion.Euler(0, -90, 0);
                    foreach (Transform w in _sky) if (w.name == "Blink") w.gameObject.SetActive(Mathf.Repeat(t, 1f) < 0.5f);
                    break;
                case Toys.Kind.Star:
                {
                    // 2초마다 한 번씩 슝 떨어진다 (세 번)
                    var cycle = Mathf.Repeat(t, 2.4f);
                    var k = Mathf.Clamp01(cycle / 1.1f);
                    var right = Vector3.Cross(Vector3.up, Fwd);
                    var from = Eye + right * (_skySide * 12) + Fwd * 10 + Vector3.up * 8f;
                    _sky.position = from + (Fwd * -5f + Vector3.down * 4.5f) * k;
                    _sky.rotation = Quaternion.LookRotation(Flat(Eye - _sky.position).normalized) * Quaternion.Euler(0, 0, -35);
                    _sky.gameObject.SetActive(cycle < 1.1f);
                    if (k > 0.1f && Mathf.Repeat(t, 0.15f) < dt) Fx.Burst(_sky.position, Fx.Spark, critterMaterial, 1, 0.5f, 0.2f);
                    break;
                }
                case Toys.Kind.Whale:
                {
                    _sky.position += (-Fwd * 0.8f) * dt;
                    var bob = Mathf.Sin(t * 1.2f) * 0.35f;
                    var p = _sky.position; p.y = Eye.y - 1.2f + bob; _sky.position = p;
                    _sky.rotation = Quaternion.LookRotation(-Fwd) * Quaternion.Euler(0, 90, 0) * Quaternion.Euler(Mathf.Sin(t * 1.2f) * 6, 0, 0);
                    foreach (Transform w in _sky)
                    {
                        if (w.name == "Tail") w.localRotation = Quaternion.Euler(0, 0, Mathf.Sin(t * 2.5f) * 18);
                        else if (w.name == "Spout") w.localScale = Vector3.one * (0.1f + Mathf.Max(0, Mathf.Sin(t * 1.2f)) * 0.5f);
                    }
                    if (Mathf.Repeat(t, 5.2f) < dt) Fx.Burst(_sky.position + Vector3.up * 1.4f, Fx.Bubble, critterMaterial, 6, 0.6f, 0.9f);
                    break;
                }
                default: // 풍선
                    _sky.position += (-Fwd * 1.2f + Vector3.up * 0.15f) * dt;
                    _sky.Rotate(0, 20 * dt, 0);
                    break;
            }
            var cam = Cam;
            var to = _sky.position + _skyLook - cam.transform.position;
            if (Vector3.Angle(cam.transform.forward, to) < 16) _skySeen += dt;
            var life = _skyKind == Toys.Kind.Plane ? 11f : _skyKind == Toys.Kind.Star ? 7.3f : 14f;
            if (_skySeen > 0.4f)
            {
                Fx.Burst(_sky.position + _skyLook, Fx.Spark, critterMaterial, 8, 0.8f, 0.8f);
                var c = Companion;
                if (c != null)
                {
                    c.Cheer(2);
                    c.Brain.Hop(0.08f);
                    Fx.Burst(c.Top, Fx.Heart, critterMaterial, 5, 0.06f);
                }
                FlutterBridge.Send("lookTogether");
                Debug.Log($"[Play] looked together ({_skyKind})");
                Speak("window_done", SkyName(_skyKind), 3.4f);
                Destroy(_sky.gameObject);
                _sky = null;
                _lookTimer = 25 + (float)_play.NextDouble() * 20; // 같이 본 뒤엔 조금 더 빨리 다음 손님
                return;
            }
            if (_skyAge > life)
            {
                Destroy(_sky.gameObject);
                _sky = null;
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
