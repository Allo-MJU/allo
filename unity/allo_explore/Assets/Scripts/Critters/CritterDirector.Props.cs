using System.Collections;
using System.Collections.Generic;
using Allo.Bridge;
using UnityEngine;

namespace Allo.Critters
{
    /// 차 안 물건 놀이 (tools/blender/cabin.py props). 판정하지 않고 Flutter 에 tap{kind} 로 의도만 알린다.
    ///
    /// - 흔들 인형(대시보드): 크게 흔들리고 동행이 따라 고개를 까딱
    /// - 장난감 자동차(바닥): 부릉 달려갔다 돌아오고 동행이 쫓아간다
    /// - 오르골(뒷좌석): 뚜껑이 열리고 음표, 모두 춤춘다. 알이 있으면 알에게 노래 (care sing)
    /// - 그림책(뒷좌석): 표지가 열리고 동행이 옆에 와서 같이 본다
    /// - 비눗방울 병(문 주머니): 비눗방울이 떠다닌다. 톡 치면 터지고, 캐릭터가 잡으려 뛴다
    /// - 휴지 상자(뒷선반): 휴지가 폴폴 나와 떨어지고, 동행이 에취!
    public sealed partial class CritterDirector
    {
        static readonly string[] PropNames = { "Bobble", "ToyCar", "MusicBox", "Book", "BubbleJar", "TissueBox" };

        readonly HashSet<Transform> _propBusy = new();
        readonly List<Bubble> _bubbles = new();
        float _bubbleSent;

        /// 탭한 물체가 이 놀이 물건이면 처리하고 true
        public bool TryProp(RaycastHit hit)
        {
            var bubble = hit.collider.GetComponent<Bubble>();
            if (bubble != null) { PopBubble(bubble); return true; }
            var (root, name) = PropRoot(hit.collider.transform);
            if (root == null) return false;
            if (_propBusy.Contains(root)) return true;
            Debug.Log($"[Props] {name}");
            switch (name)
            {
                case "Bobble": StartCoroutine(BobbleNod(root)); break;
                case "ToyCar": StartCoroutine(DriveToyCar(root)); break;
                case "MusicBox": StartCoroutine(PlayMusicBox(root)); break;
                case "Book": StartCoroutine(ReadBook(root)); break;
                case "BubbleJar": StartCoroutine(BlowBubbles(root)); break;
                case "TissueBox": StartCoroutine(PullTissue(root)); break;
            }
            return true;
        }

        /// 이름이 놀이 물건 이름과 같은 가장 가까운 조상 (BobbleHead → Bobble)
        public static (Transform root, string name) PropRoot(Transform t)
        {
            for (var p = t; p != null; p = p.parent)
                foreach (var n in PropNames)
                    if (p.name == n) return (p, n);
            return (null, null);
        }

        static void PunchAll(Transform root)
        {
            foreach (var w in root.GetComponentsInChildren<Wobble>()) w.Punch();
        }

        void TellPlay(CritterView c, string kind)
        {
            if (c != null && c.Id == CompanionId) FlutterBridge.Send("tap", FlutterBridge.Field("kind", kind));
        }

        /// 물건 가까운 걷는 면 위, 아이에게 잘 보이는 자리
        (Vector3 at, int surf) NearPoint(Vector3 p)
        {
            var surf = _graph.Nearest(p);
            return (Comfy(WalkGraph.Clamp(p, _graph.Surfaces[surf]), surf), surf);
        }

        // ---------------- 흔들 인형 ----------------

        IEnumerator BobbleNod(Transform root)
        {
            _propBusy.Add(root);
            PunchAll(root);
            Fx.Burst(root.position + Vector3.up * 0.12f, Fx.Spark, critterMaterial, 3, 0.04f, 0.04f);
            var c = Actor;
            if (c != null)
            {
                if (Speak("prop", "bobble", 3f) == null) Say("흔들흔들~ 친구도 따라 해요");
                for (var i = 0; i < 3 && c != null; i++)
                {
                    c.Brain.Hop(0.02f);
                    c.Cheer(0.8f);
                    yield return new WaitForSeconds(0.45f);
                }
                TellPlay(c, "bobble");
            }
            else yield return new WaitForSeconds(0.7f);
            _propBusy.Remove(root);
        }

        // ---------------- 장난감 자동차 ----------------

        readonly Dictionary<Transform, (Vector3 pos, Quaternion rot)> _carHome = new();

        IEnumerator DriveToyCar(Transform car)
        {
            _propBusy.Add(car);
            if (!_carHome.ContainsKey(car)) _carHome[car] = (car.position, car.rotation);
            var home = _carHome[car];
            // 아이 쪽에서 볼 때 가로로 달린다. 바닥 면 안에서만
            var right = Vector3.Cross(Vector3.up, Fwd).normalized;
            var floor = _graph.IndexOf("Walk_Floor");
            var dir = Vector3.Dot(home.pos - (floor >= 0 ? _graph.Surfaces[floor].center : home.pos), right) > 0 ? -right : right;
            var end = home.pos + dir * 0.55f;
            if (floor >= 0)
            {
                var clamped = WalkGraph.Clamp(end, _graph.Surfaces[floor]);
                end = new Vector3(clamped.x, home.pos.y, clamped.z);
            }
            var wheels = new List<Transform>();
            foreach (var t in car.GetComponentsInChildren<Transform>())
                if (t.name.StartsWith("ToyCarWheel")) wheels.Add(t);
            if (Speak("prop", "toycar", 3f) == null) Say("부릉부릉! 장난감 차가 달려요");
            var c = Actor;
            if (c != null)
            {
                var (at, surf) = NearPoint(end);
                c.Brain.Hold = true;
                c.Brain.MoveTo(at, surf);
                c.Cheer(3);
            }
            yield return Drive(car, wheels, home.pos, end, 1.1f);
            Fx.Burst(end + Vector3.up * 0.05f, Fx.Spark, critterMaterial, 3, 0.04f, 0.05f);
            if (c != null)
            {
                c.Brain.Hop(0.06f);
                Fx.Burst(c.Top, Fx.Heart, critterMaterial, 3, 0.06f);
                TellPlay(c, "toycar");
            }
            yield return new WaitForSeconds(0.8f);
            yield return Drive(car, wheels, end, home.pos, 1.4f); // 후진으로 제자리
            car.rotation = home.rot;
            if (c != null) c.Brain.Hold = false;
            _propBusy.Remove(car);
        }

        /// 차는 cabin.py 에서 길이가 차 안 가로 방향이라 돌리지 않고 앞뒤로만 달린다. 바퀴는 굴러간 만큼 돈다
        static IEnumerator Drive(Transform car, List<Transform> wheels, Vector3 from, Vector3 to, float seconds)
        {
            var axle = Vector3.Cross(Vector3.up, (to - from).normalized);
            var last = from;
            for (var t = 0f; t < seconds; t += Time.deltaTime)
            {
                var k = Mathf.SmoothStep(0, 1, t / seconds);
                var p = Vector3.Lerp(from, to, k);
                car.position = p + Vector3.up * (Mathf.Abs(Mathf.Sin(t * 25)) * 0.004f);
                var roll = (p - last).magnitude / 0.018f * Mathf.Rad2Deg;
                foreach (var w in wheels)
                {
                    var r = w.GetComponent<Renderer>();
                    w.RotateAround(r != null ? r.bounds.center : w.position, axle, roll);
                }
                last = p;
                yield return null;
            }
            car.position = to;
        }

        // ---------------- 오르골 ----------------

        IEnumerator PlayMusicBox(Transform box)
        {
            _propBusy.Add(box);
            var lid = Child(box, "MusicBoxLid");
            var (pivot, axis) = Hinge(lid, box, true);
            yield return Swing(lid, pivot, axis, -100, 0.4f);
            if (HasEgg || Speak("prop", "music", 3f) == null) Say(HasEgg ? "오르골 소리에 알이 살랑살랑" : "띵띵띵~ 오르골이 노래해요");
            if (HasEgg) SingToEgg(true);
            var c = Actor;
            for (var beat = 0; beat < 8; beat++)
            {
                Fx.Burst(box.position + Vector3.up * 0.1f, Fx.Note, critterMaterial, 1, 0.05f, 0.06f);
                box.localScale = Vector3.one * (beat % 2 == 0 ? 1.06f : 1f);
                if (beat % 2 == 0)
                    foreach (var v in _views.Values)
                        if (v.Brain.State != CritterState.Sleep) { v.Brain.Hop(0.03f); v.Cheer(0.8f); }
                yield return new WaitForSeconds(0.55f);
            }
            box.localScale = Vector3.one;
            TellPlay(c, "music");
            yield return Swing(lid, pivot, axis, 100, 0.4f);
            _propBusy.Remove(box);
        }

        // ---------------- 그림책 ----------------

        IEnumerator ReadBook(Transform book)
        {
            _propBusy.Add(book);
            var cover = Child(book, "BookCover");
            var (pivot, axis) = Hinge(cover, book, false);
            yield return Swing(cover, pivot, axis, -165, 0.6f);
            if (Speak("prop", "book", 3f) == null) Say("그림책을 펼쳤어요. 같이 봐요!");
            var c = Actor;
            if (c != null && !_busy)
            {
                _busy = true;
                var (at, surf) = NearPoint(book.position);
                yield return Approach(c, at, surf, 0.06f);
                if (c != null)
                {
                    c.Brain.Peek(4);
                    c.Cheer(4);
                    for (var i = 0; i < 4 && c != null; i++)
                    {
                        Fx.Burst(book.position + Vector3.up * 0.06f, Fx.Spark, critterMaterial, 2, 0.04f, 0.06f);
                        yield return new WaitForSeconds(0.9f);
                    }
                    if (c != null)
                    {
                        Fx.Burst(c.Top, Fx.Heart, critterMaterial, 3, 0.06f);
                        TellPlay(c, "book");
                        c.Brain.Hold = false;
                    }
                }
                _busy = false;
            }
            else yield return new WaitForSeconds(3f);
            yield return Swing(cover, pivot, axis, 165, 0.5f);
            _propBusy.Remove(book);
        }

        static Transform Child(Transform root, string name)
        {
            foreach (var t in root.GetComponentsInChildren<Transform>())
                if (t.name == name) return t;
            return null;
        }

        /// 뚜껑·표지가 열리는 경첩: 아이에게서 먼 쪽 모서리. 열면 가까운 쪽이 들려 아이 쪽으로 속이 보인다
        (Vector3 pivot, Vector3 axis) Hinge(Transform part, Transform root, bool lid)
        {
            if (part == null) return (root.position, Vector3.right);
            var r = part.GetComponent<Renderer>();
            var b = r != null ? r.bounds : new Bounds(part.position, Vector3.one * 0.1f);
            var toChild = Flat(Eye - b.center).normalized;
            var half = Mathf.Abs(toChild.x) * b.extents.x + Mathf.Abs(toChild.z) * b.extents.z;
            var pivot = b.center - toChild * half + Vector3.down * (lid ? b.extents.y : 0);
            return (pivot, Vector3.Cross(Vector3.up, toChild));
        }

        static IEnumerator Swing(Transform part, Vector3 pivot, Vector3 axis, float angle, float seconds)
        {
            if (part == null) yield break;
            var done = 0f;
            for (var t = 0f; t < seconds; t += Time.deltaTime)
            {
                var want = angle * Mathf.SmoothStep(0, 1, t / seconds);
                part.RotateAround(pivot, axis, want - done);
                done = want;
                yield return null;
            }
            part.RotateAround(pivot, axis, angle - done);
        }

        // ---------------- 비눗방울 ----------------

        IEnumerator BlowBubbles(Transform jar)
        {
            _propBusy.Add(jar);
            PunchAll(jar);
            if (Speak("prop", "bubble", 3f) == null) Say("후~ 비눗방울! 톡 쳐서 터뜨려 봐요");
            var from = jar.position + Vector3.up * 0.14f;
            var inward = Flat(Eye - from).normalized;
            for (var i = 0; i < 8; i++)
            {
                var go = Fx.Sprite(Fx.Bubble, critterMaterial, 0.05f + (float)_play.NextDouble() * 0.04f);
                go.name = "Bubble";
                go.transform.position = from;
                var b = go.AddComponent<Bubble>();
                var col = go.AddComponent<SphereCollider>();
                col.radius = 0.6f;
                var side = Vector3.Cross(Vector3.up, inward) * ((float)_play.NextDouble() - 0.5f) * 0.25f;
                b.velocity = inward * (0.12f + (float)_play.NextDouble() * 0.1f) + side + Vector3.up * (0.04f + (float)_play.NextDouble() * 0.05f);
                b.director = this;
                _bubbles.Add(b);
                yield return new WaitForSeconds(0.22f);
            }
            yield return new WaitForSeconds(1.5f);
            _propBusy.Remove(jar);
        }

        void PopBubble(Bubble b)
        {
            if (b == null) return;
            Fx.Burst(b.transform.position, Fx.Spark, critterMaterial, 3, 0.04f, 0.03f);
            _bubbles.Remove(b);
            Destroy(b.gameObject);
            var c = Actor;
            if (c != null && Time.time - _bubbleSent > 4f)
            {
                _bubbleSent = Time.time;
                c.Cheer(1.2f);
                TellPlay(c, "bubble");
            }
        }

        /// 비눗방울이 캐릭터 머리 위로 지나가면 잡으려고 뛴다
        internal void BubbleNear(Bubble b)
        {
            foreach (var v in _views.Values)
            {
                if (v.Brain.State is CritterState.Sleep or CritterState.Jump or CritterState.Tumble) continue;
                var d = b.transform.position - v.Top;
                if (Flat(d).sqrMagnitude < 0.12f * 0.12f && d.y > -0.05f && d.y < 0.3f && !b.chased)
                {
                    b.chased = true;
                    v.Brain.Hop(0.1f);
                    v.Cheer(1);
                }
            }
        }

        internal void BubbleGone(Bubble b) => _bubbles.Remove(b);

        // ---------------- 휴지 ----------------

        IEnumerator PullTissue(Transform box)
        {
            _propBusy.Add(box);
            PunchAll(box);
            var tissue = Toys.Make(Toys.Kind.Tissue);
            var top = box.position + Vector3.up * 0.1f;
            tissue.position = top;
            var c = Actor;
            var land = c != null ? c.Top + Vector3.down * 0.02f : top + Flat(Eye - top).normalized * 0.3f + Vector3.down * 0.1f;
            if (Speak("prop", "tissue", 3f) == null) Say("휴지가 폴폴~");
            // 위로 쏙 → 팔랑팔랑 내려앉는다
            for (var t = 0f; t < 0.35f; t += Time.deltaTime)
            {
                tissue.position = top + Vector3.up * (0.18f * t / 0.35f);
                yield return null;
            }
            var high = tissue.position;
            for (var t = 0f; t < 1.6f; t += Time.deltaTime)
            {
                var k = t / 1.6f;
                var target = c != null ? c.Top + Vector3.down * 0.02f : land;
                tissue.position = Vector3.Lerp(high, target, k) + Vector3.Cross(Vector3.up, Fwd).normalized * (Mathf.Sin(t * 6) * 0.05f * (1 - k));
                tissue.rotation = Quaternion.Euler(Mathf.Sin(t * 5) * 25, t * 90, Mathf.Cos(t * 4) * 25);
                yield return null;
            }
            if (c != null)
            {
                // 얼굴에 내려앉은 휴지에 에취!
                yield return new WaitForSeconds(0.3f);
                c.Brain.Hop(0.08f);
                c.Cheer(1.5f);
                Fx.Burst(c.Top, Fx.Spark, critterMaterial, 5, 0.05f, 0.06f);
                Say("에취!");
                TellPlay(c, "tissue");
                var from = tissue.position;
                for (var t = 0f; t < 0.5f; t += Time.deltaTime)
                {
                    tissue.position = from + (Vector3.up * 0.15f + Fwd * 0.1f) * (t / 0.5f);
                    yield return null;
                }
            }
            yield return Shrink(tissue, 1f);
            _propBusy.Remove(box);
        }
    }

    /// 떠다니는 비눗방울 하나. 카메라를 향하고, 몇 초 뒤 저절로 터진다
    public sealed class Bubble : MonoBehaviour
    {
        public Vector3 velocity;
        public CritterDirector director;
        public bool chased;
        float _age, _life = 6.5f, _phase;

        void Start() => _phase = Random.value * 10;

        void Update()
        {
            _age += Time.deltaTime;
            velocity = Vector3.Lerp(velocity, new Vector3(0, 0.03f, 0), Time.deltaTime * 0.5f);
            transform.position += (velocity + new Vector3(Mathf.Sin(_age * 2 + _phase), 0, Mathf.Cos(_age * 1.7f + _phase)) * 0.02f) * Time.deltaTime;
            var cam = Camera.main;
            if (cam != null) transform.rotation = Quaternion.LookRotation(transform.position - cam.transform.position);
            if (director != null) director.BubbleNear(this);
            if (_age > _life)
            {
                Fx.Burst(transform.position, Fx.Spark, director != null ? director.critterMaterial : null, 2, 0.03f, 0.02f);
                if (director != null) director.BubbleGone(this);
                Destroy(gameObject);
            }
        }
    }
}
