using System.Collections;
using System.Collections.Generic;
using Allo.Bridge;
using UnityEngine;

namespace Allo.Critters
{
    /// 뒷좌석 둥지와 품는 알. 판정은 하지 않는다. egg 메시지대로 알을 두고, 아이의 돌보기를 care 로 알린다.
    ///
    /// - 둥지는 늘 있다. 알이 없을 때는 동행이 와서 쉬는 자리다 (둥지 탭)
    /// - 알은 진행도에 따라 더 자주 흔들리고 금이 간다 (50%·80%·95%)
    /// - 알 톡톡(탭)·문지르기·노래(버튼·오르골)·담요 → care. 품기 화면의 감싸기·노래와 같은 돌봄이다
    /// - 같은 알이 hatched 로 바뀌면: 흔들림 → 금 → 빛 → 윗껍데기가 날아가고 둥지에서 동행이 나온다
    public sealed partial class CritterDirector
    {
        readonly EggTracker _eggTracker = new();
        Transform _nest, _egg, _eggBlanket, _eggShell;
        Vector3 _nestAt;
        int _nestSurf = -1;
        float _eggProgress, _eggJiggle, _eggSwayAmp, _singUntil, _eggRubFx;
        int _eggCracks;
        bool _eggBig, _hatching;
        float _bornAt = -99;
        readonly Dictionary<string, float> _careSent = new();

        public bool HasEgg => _egg != null && !_hatching;

        /// 둥지가 앞좌석 사이(약 1.3m)에 있어 실제 장난감 알보다 조금 크게 그린다. 중간·큰 알은 더 크게
        float EggScale => _eggBig ? 1.6f : 1.3f;
        public bool Hatching => _hatching;
        public bool EggCovered => _eggBlanket != null;

        /// 동행이 없으면(아직 알만 있을 때) 함께 노는 친구. 판정은 Flutter 가 하므로 표시만 다르다
        CritterView Actor
        {
            get
            {
                var c = Companion;
                if (c != null) return c;
                foreach (var v in _views.Values) return v;
                return null;
            }
        }

        bool ReducedMotion => FlutterBridge.LastSettings != null && FlutterBridge.LastSettings.reducedMotion;

        void EggEnable() => FlutterBridge.EggChanged += OnEgg;
        void EggDisable() => FlutterBridge.EggChanged -= OnEgg;

        void EggStart()
        {
            PlaceNest();
            if (FlutterBridge.LastEgg != null) OnEgg(FlutterBridge.LastEgg);
#if UNITY_EDITOR
            if (FlutterBridge.LastEgg == null && FlutterBridge.LastCast == null)
                OnEgg(new EggState { state = "incubating", progress = 0.82f, eggId = "editor" });
#endif
        }

#if UNITY_EDITOR
        /// 에디터 캡처용: Play 없이 둥지와 알을 놓는다 (AlloBuild.CaptureEgg)
        public void EditorPreview(WalkGraph g, float progress)
        {
            _graph = g;
            PlaceNest();
            OnEgg(new EggState { state = "incubating", progress = progress, eggId = "preview" });
        }
#endif

        // ---------------- 둥지 자리 ----------------

        /// 아이가 정면을 볼 때 두 등받이 사이로 보이는 센터 콘솔 → 뒷좌석 옆자리 → 팔걸이 → 바닥 순으로, 편한 자리에 둥지를 둔다
        void PlaceNest()
        {
            if (_graph.Surfaces.Count == 0 || _nest != null) return;
            foreach (var name in new[] { "Walk_Console", "Walk_RearSeat_L", "Walk_RearSeat_R", "Walk_Armrest", "Walk_Floor" })
            {
                var i = _graph.IndexOf(name);
                if (i < 0) continue;
                var p = Comfy(_graph.Surfaces[i].center, i);
                if (_graph.Comfortable != null && !_graph.Comfortable(p)) continue;
                _nestSurf = i;
                _nestAt = p;
                break;
            }
            if (_nestSurf < 0)
            {
                _nestSurf = 0;
                _nestAt = _graph.Surfaces[0].center;
            }
            _nest = Toys.Make(Toys.Kind.Nest);
            _nest.name = "EggNest";
            _nest.position = _nestAt;
            _nest.localScale = Vector3.one * 1.3f;
            _nest.SetParent(transform, true);
            var col = _nest.gameObject.AddComponent<BoxCollider>();
            col.center = new Vector3(0, 0.03f, 0);
            col.size = new Vector3(0.2f, 0.08f, 0.2f);
            Debug.Log($"[Egg] nest on {_graph.Surfaces[_nestSurf].name} at {_nestAt}");
        }

        public bool IsNest(Collider c) => _nest != null && c != null && c.transform == _nest;
        public bool IsEgg(Collider c) => _egg != null && c != null && c.transform.IsChildOf(_egg);

        // ---------------- egg 메시지 ----------------

        void OnEgg(EggState e)
        {
            if (_nest == null) PlaceNest();
            _eggProgress = e.progress;
            _eggBig = e.big;
            switch (_eggTracker.Apply(e))
            {
                case EggTracker.Change.Appear:
                    MakeEgg(false);
                    break;
                case EggTracker.Change.Replace:
                    MakeEgg(true);
                    break;
                case EggTracker.Change.Update:
                    UpdateCracks();
                    break;
                case EggTracker.Change.Hatch:
                    if (_egg != null && !_hatching) StartCoroutine(Hatch(e.bornText));
                    break;
                case EggTracker.Change.Vanish:
                    ClearEgg();
                    break;
            }
        }

        void MakeEgg(bool replace)
        {
            ClearEgg();
            _egg = Toys.Make(Toys.Kind.Egg);
            _egg.name = "Egg";
            _egg.SetParent(transform, false);
            _egg.position = _nestAt + Vector3.up * 0.012f;
            _egg.localScale = Vector3.one * EggScale;
            FaceChild(_egg);
            var col = _egg.gameObject.AddComponent<CapsuleCollider>();
            col.center = new Vector3(0, Toys.EggH / 2, 0);
            col.radius = Toys.EggW * 0.6f;
            col.height = Toys.EggH * 1.1f;
            _eggCracks = 0;
            UpdateCracks();
            if (!replace && Application.isPlaying) Fx.Burst(_egg.position + Vector3.up * 0.08f, Fx.Spark, critterMaterial, 4, 0.05f);
            Debug.Log($"[Egg] appear progress={_eggProgress:F2} big={_eggBig}");
        }

        void ClearEgg()
        {
            if (_egg != null) Destroy(_egg.gameObject);
            _egg = null;
            if (_eggBlanket != null) Destroy(_eggBlanket.gameObject);
            _eggBlanket = null;
        }

        void FaceChild(Transform t)
        {
            var to = Eye - t.position;
            to.y = 0;
            if (to.sqrMagnitude > 1e-4f) t.rotation = Quaternion.LookRotation(to.normalized);
        }

        void UpdateCracks()
        {
            if (_egg == null) return;
            var want = EggTracker.CrackStage(_eggProgress);
            while (_eggCracks < want) Toys.AddCrack(_egg, _eggCracks++);
        }

        // ---------------- 매 프레임: 알이 숨 쉬듯 흔들린다 ----------------

        void EggTick(float dt)
        {
            if (_egg == null || _hatching) return;
            // 진행될수록 자주, 크게 들썩인다. 노래하면 좌우로 살랑
            _eggJiggle -= dt;
            if (_eggJiggle <= 0)
            {
                _eggJiggle = Mathf.Lerp(7f, 2f, _eggProgress) + (float)_play.NextDouble() * 2;
                _eggSwayAmp = Mathf.Max(_eggSwayAmp, Mathf.Lerp(6, 16, _eggProgress));
                if (EggTracker.CrackStage(_eggProgress) >= 3)
                    Fx.Burst(_egg.position + Vector3.up * 0.1f, Fx.Spark, critterMaterial, 2, 0.04f, 0.05f);
            }
            var singing = Time.time < _singUntil;
            var calm = ReducedMotion ? 0.35f : 1f;
            _eggSwayAmp = Mathf.MoveTowards(_eggSwayAmp, 0, dt * 18);
            var sway = singing ? Mathf.Sin(Time.time * 5) * 9 : Mathf.Sin(Time.time * 22) * _eggSwayAmp;
            var breathe = 1 + Mathf.Sin(Time.time * 2.2f) * 0.015f;
            var baseRot = Quaternion.LookRotation(Flat(Eye - _egg.position).normalized);
            _egg.rotation = baseRot * Quaternion.Euler(0, 0, sway * calm);
            var s = EggScale;
            _egg.localScale = new Vector3(s, s * breathe, s);
        }

        // ---------------- 돌보기 ----------------

        /// care 를 보낸다. 같은 종류는 gap 초에 한 번만 (돌봄 횟수가 부화 결과에 쓰이므로 연타를 막는다)
        bool SendCare(string kind, float gap)
        {
            if (_careSent.TryGetValue(kind, out var at) && Time.time - at < gap) return false;
            _careSent[kind] = Time.time;
            FlutterBridge.Send("care", FlutterBridge.Field("kind", kind));
            Debug.Log($"[Egg] care {kind}");
            return true;
        }

        /// 알 톡톡: 통 하고 답한다
        public void TapEgg()
        {
            if (!HasEgg) return;
            _eggSwayAmp = 18;
            Fx.Burst(_egg.position + Vector3.up * 0.12f, Fx.Heart, critterMaterial, 2, 0.05f, 0.04f);
            if (SendCare("tap", 2f)) Say(_eggProgress >= 0.8f ? "톡톡! 안에서 대답해요. 곧 나올 것 같아요" : "톡톡! 알이 대답했어요");
        }

        /// 알 문지르기: 따뜻해진다
        public void RubEgg()
        {
            if (!HasEgg) return;
            _eggSwayAmp = Mathf.Max(_eggSwayAmp, 6);
            if (Time.time - _eggRubFx > 0.25f)
            {
                _eggRubFx = Time.time;
                Fx.Burst(_egg.position + Vector3.up * 0.1f, Fx.Spark, critterMaterial, 1, 0.04f, 0.05f);
            }
            if (SendCare("rub", 3f)) Say("알이 따뜻해졌어요");
        }

        /// 노래 (버튼·오르골): 알이 살랑이고 친구들이 둥지로 모인다
        public void SingToEgg(bool fromMusicBox = false)
        {
            if (!HasEgg) return;
            _singUntil = Time.time + 4.5f;
            StartCoroutine(Notes(_egg, 4.5f));
            foreach (var v in _views.Values)
            {
                if (v.Brain.State == CritterState.Sleep) continue;
                var at = Comfy(WalkGraph.Clamp(_nestAt + Flat(v.Brain.Position - _nestAt).normalized * 0.16f, _graph.Surfaces[_nestSurf]), _nestSurf);
                v.Brain.MoveTo(at, _nestSurf);
                v.Cheer(4);
            }
            if (SendCare("sing", 5f)) Say(fromMusicBox ? "오르골 소리에 알이 살랑살랑" : "알에게 노래를 불러 줘요 ♪");
        }

        IEnumerator Notes(Transform at, float seconds)
        {
            for (var t = 0f; t < seconds && at != null; t += 0.5f)
            {
                Fx.Burst(at.position + Vector3.up * 0.12f, Fx.Note, critterMaterial, 1, 0.05f, 0.08f);
                yield return new WaitForSeconds(0.5f);
            }
        }

        /// 담요: 알을 덮어 준다. 다시 누르면 걷는다
        public void ToggleEggBlanket()
        {
            if (!HasEgg) return;
            if (_eggBlanket != null)
            {
                Destroy(_eggBlanket.gameObject);
                _eggBlanket = null;
                Say("담요를 걷었어요");
                return;
            }
            _eggBlanket = Toys.Make(Toys.Kind.EggWrap);
            _eggBlanket.SetParent(_egg, false); // 알을 감싸 같이 흔들린다
            Fx.Burst(_egg.position + Vector3.up * 0.12f, Fx.Heart, critterMaterial, 3, 0.05f);
            if (SendCare("blanket", 5f)) Say("알에게 담요를 덮어 줬어요. 포근해요");
        }

        // ---------------- 깨어나기 ----------------

        IEnumerator Hatch(string bornText)
        {
            _hatching = true;
            Debug.Log("[Egg] hatch start");
            if (_eggBlanket != null) { Destroy(_eggBlanket.gameObject); _eggBlanket = null; }
            var egg = _egg;
            var calm = ReducedMotion ? 0.3f : 1f;
            var s = EggScale;
            var baseRot = Quaternion.LookRotation(Flat(Eye - egg.position).normalized);
            Say("앗, 알이 움직여요!", 2f);
            Allo.CameraRig.CameraRig.Glance(egg.position + Vector3.up * 0.08f); // 다른 곳을 보고 있었으면 둥지 쪽으로 고개를 돌린다
            // 친구들이 둥지 쪽을 보며 놀란다
            foreach (var v in _views.Values) { v.Brain.Peek(3); v.Cheer(3); }

            // 1) 점점 세게 흔들린다
            for (var t = 0f; t < 1.4f && egg != null; t += Time.deltaTime)
            {
                var k = t / 1.4f;
                egg.rotation = baseRot * Quaternion.Euler(0, 0, Mathf.Sin(t * (18 + k * 30)) * (6 + k * 18) * calm);
                if (k > 0.5f) egg.position = _nestAt + Vector3.up * (0.012f + Mathf.Abs(Mathf.Sin(t * 30)) * 0.01f * k * calm);
                yield return null;
            }
            // 2) 금이 쫙
            while (egg != null && _eggCracks < 5) Toys.AddCrack(egg, _eggCracks++);
            if (egg != null) Fx.Burst(egg.position + Vector3.up * 0.08f, Fx.Spark, critterMaterial, 6, 0.05f, 0.06f);
            for (var t = 0f; t < 0.5f && egg != null; t += Time.deltaTime)
            {
                egg.rotation = baseRot * Quaternion.Euler(0, 0, Mathf.Sin(t * 60) * 4 * calm);
                yield return null;
            }
            // 3) 빛이 새어 나오며 부풀었다가
            for (var t = 0f; t < 0.45f && egg != null; t += Time.deltaTime)
            {
                var k = t / 0.45f;
                egg.localScale = new Vector3(s * (1 + k * 0.12f), s * (1 - k * 0.06f), s * (1 + k * 0.12f));
                if (Mathf.Repeat(t, 0.12f) < Time.deltaTime) Fx.Burst(egg.position + Vector3.up * 0.1f, Fx.Spark, critterMaterial, 2, 0.06f, 0.05f);
                yield return null;
            }
            // 4) 퐁! 윗껍데기가 날아가고 둥지에서 나온다
            var at = egg != null ? egg.position : _nestAt;
            if (egg != null) Destroy(egg.gameObject);
            _egg = null;
            var bottom = Toys.Make(Toys.Kind.EggBottom);
            bottom.position = at + Vector3.up * 0.02f; // 둥지 짚 위로 깨진 테두리가 보이게
            bottom.localScale = Vector3.one * s;
            bottom.SetParent(transform, true);
            _eggShell = bottom;
            var top = Toys.Make(Toys.Kind.EggTop);
            top.localScale = Vector3.one * s;
            top.SetParent(transform, true);
            StartCoroutine(FlyCap(top, at + Vector3.up * (Toys.EggH * s * 0.75f)));
            Fx.Burst(at + Vector3.up * 0.1f, Fx.Spark, critterMaterial, 14, 0.07f, 0.12f);
            Fx.Burst(at + Vector3.up * 0.12f, Fx.Heart, critterMaterial, 6, 0.07f, 0.1f);
            _hatching = false;
            _bornAt = Time.time;
            SpawnFromEgg();
            HudOrNull?.ShowHold(string.IsNullOrEmpty(bornText) ? "알에서 친구가 태어났어요!" : bornText, 3.5f);
            foreach (var v in _views.Values) { v.Brain.Hop(0.1f); v.Cheer(3); }
            Debug.Log("[Egg] hatched");
            yield return Shrink(bottom, 9f);
        }

        IEnumerator FlyCap(Transform cap, Vector3 from)
        {
            var side = Vector3.Cross(Vector3.up, Flat(Eye - from).normalized);
            var to = from + side * 0.18f + Vector3.down * (from.y - _nestAt.y);
            for (var t = 0f; t < 0.75f && cap != null; t += Time.deltaTime)
            {
                var k = t / 0.75f;
                cap.position = Vector3.Lerp(from, to, k) + Vector3.up * (Mathf.Sin(k * Mathf.PI) * 0.22f);
                cap.rotation = Quaternion.AngleAxis(k * 540, side);
                yield return null;
            }
            if (cap == null) yield break;
            cap.position = to;
            cap.rotation = Quaternion.Euler(180, 0, 0); // 뒤집혀서 떨어진다
            yield return Shrink(cap, 8f);
        }

        /// 깨어난 동행을 둥지 자리에 세운다. 이미 친구로 다니던 같은 캐릭터면 둥지로 옮긴다
        void SpawnFromEgg()
        {
            if (CompanionId == null || FlutterBridge.LastCast == null) return;
            if (_views.TryGetValue(CompanionId, out var old))
            {
                Destroy(old.gameObject);
                _views.Remove(CompanionId);
            }
            OnCast(FlutterBridge.LastCast);
        }

        /// 막 깨어난 동행이면 둥지에서 시작한다 (OnCast 가 부른다)
        bool BornNow(string id) => id == CompanionId && Time.time - _bornAt < 5f;

        void StartAtNest(CritterView v)
        {
            v.Brain.Place(_nestAt, _nestSurf);
            v.Brain.AwakeFor = 8; // 막 깨어난 친구가 터널·밤이라고 바로 잠들면 어색하다
            v.Brain.Hop(0.15f);
            v.Cheer(4);
        }

        // ---------------- 알이 없을 때 둥지 ----------------

        /// 둥지 탭: 알이 있으면 알 톡톡, 없으면 동행이 들어가 쉰다
        public void TapNest()
        {
            if (HasEgg) { TapEgg(); return; }
            var c = Actor;
            if (c == null || _busy) return;
            StartCoroutine(RestInNest(c));
        }

        IEnumerator RestInNest(CritterView c)
        {
            _busy = true;
            yield return Approach(c, _nestAt, _nestSurf, 0f);
            if (c != null)
            {
                c.Brain.Place(_nestAt, _nestSurf);
                c.Brain.Nap(6);
                Fx.Burst(c.Top, Fx.Heart, critterMaterial, 3, 0.06f);
                if (c.Id == CompanionId) FlutterBridge.Send("tap", FlutterBridge.Field("kind", "nest"));
                c.Brain.Hold = false;
            }
            _busy = false;
        }
    }
}
