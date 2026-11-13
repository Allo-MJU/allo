using System.Collections.Generic;
using Allo.Bridge;
using UnityEngine;

namespace Allo.Critters
{
    /// 캐릭터가 말풍선으로 말한다 (대사는 phone/assets/data/cabin_dialogue.json, 규칙은 docs/dialogue-style.md).
    /// - 태어날 때 첫마디, 장면이 바뀔 때(바다·산·도시·터널·밤·비), 놀 때(간식·공·쓰다듬기·담요·물건), 창밖 구경
    /// - 가만히 있을 때 35~65초마다 혼잣말. 그중 1/3 은 부탁("공 던져 줄래?")
    /// - 영어는 한 문장에 단어 하나 + 한글 뜻. 아이에게 되묻지 않는다
    public sealed partial class CritterDirector
    {
        readonly Dictionary<string, SpeechBubble> _speech = new();
        float _chatTimer = 28f;
        float _lastSceneTalk = -99f;
        string _lastSceneKey;

        /// 지금 장면을 대사 문맥 키로: 터널 > 밤 > 비 > 장면 종류
        string SceneContext
        {
            get
            {
                if (_mood.tunnel) return "tunnel";
                if (_mood.night) return "night";
                if (_mood.rain) return "rain";
                return string.IsNullOrEmpty(_scene) ? "road" : _scene;
            }
        }

        static string AttrOf(CritterView v)
        {
            var cast = FlutterBridge.LastCast;
            if (cast == null || v == null) return "normal";
            if (cast.companion != null && cast.companion.id == v.Id) return cast.companion.attribute ?? "normal";
            if (cast.friends != null)
                foreach (var f in cast.friends)
                    if (f != null && f.id == v.Id) return f.attribute ?? "normal";
            return "normal";
        }

        SpeechBubble BubbleOf(CritterView v)
        {
            if (_speech.TryGetValue(v.Id, out var b) && b != null) return b;
            b = SpeechBubble.Make(transform, v.transform, CritterView.Height * 1.15f, Cam);
            _speech[v.Id] = b;
            return b;
        }

        /// 상황(evt)에 맞는 대사를 골라 말풍선에 띄운다. 동행이 없으면 말하지 않는다. 골라진 문장을 돌려준다
        public string Speak(string evt, string context = null, float seconds = 3.4f, CritterView who = null)
        {
            if (Allo.App.AppSession.StoryActive && evt != "hatch") return null;
            who ??= Companion;
            if (who == null || !Dialogue.Ready) return null;
            var line = Dialogue.Pick(evt, who.Id, AttrOf(who), context ?? SceneContext, _play);
            if (line == null) return null;
            BubbleOf(who).Show(line, seconds);
            Debug.Log($"[Talk] {evt}/{context ?? SceneContext}: {line}");
            return line;
        }

#if UNITY_EDITOR
        /// 에디터 캡처용: 말풍선을 캐릭터 위로 옮긴다 (LateUpdate 가 돌지 않으므로)
        public void EditorBubbleTick()
        {
            foreach (var b in _speech.Values) if (b != null) b.Place();
        }
#endif

        public bool Talking => Companion != null && _speech.TryGetValue(Companion.Id, out var b) && b != null && b.Showing;

        void OnSceneTalk()
        {
            if (Allo.App.AppSession.StoryActive) { _lastSceneKey = SceneContext; return; }
            var key = SceneContext;
            if (key == _lastSceneKey) return;
            _lastSceneKey = key;
            if (Companion == null || _hatching || Time.time - _lastSceneTalk < 8f) return;
            if (Companion.Brain.State == CritterState.Sleep) return;
            _lastSceneTalk = Time.time;
            Speak("scene", key, 3.8f);
            _chatTimer = Mathf.Max(_chatTimer, 20f);
        }

        void TalkTick(float dt)
        {
            if (Allo.App.AppSession.StoryActive)
            {
                foreach (var bubble in _speech.Values) if (bubble != null) bubble.Hide();
                _chatTimer = 28f;
                return;
            }
            var c = Companion;
            if (c == null || _hatching) return;
            _chatTimer -= dt;
            if (_chatTimer > 0) return;
            _chatTimer = 35f + (float)_play.NextDouble() * 30f;
            if (Talking || _busy || Holding) return;
            if (c.Brain.State == CritterState.Sleep) { Speak("sleep_talk", "*", 2.2f); return; }
            if (_play.NextDouble() < 0.34) Speak("request", "*", 3.6f);
            else Speak("idle", null, 3.4f);
        }
    }
}
