using System;
using System.Linq;
using UnityEngine;
using UnityEngine.EventSystems;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        static readonly string[] CareIds = { "snack", "water", "ball", "pet", "plush", "cushion", "blanket" };
        static readonly string[] CareNames = { "간식", "물", "공", "쓰다듬기", "인형", "쿠션", "담요" };
        string _companionText = "";
        bool _choosingCompanion;

        public static bool HasSelectedCompanion(AppState state)
        {
            var learning = state?.learning;
            return learning != null && !string.IsNullOrEmpty(learning.creatureId) &&
                Items(learning.creatures).Any(c => c.creatureId == learning.creatureId && c.speciesId == learning.speciesId);
        }

        public static bool CanCompanionTalk(AppState state) => state != null && state.ready && !state.busy &&
            state.view == "cabin" && !StoryOverlay.ShowsStory(state) && !state.sessionEnded && HasSelectedCompanion(state) &&
            state.learning.active && state.learning.available && !state.learning.busy && !state.learning.recording;

        public static bool CanCommonCare(AppState state, string actionId) => state != null && state.ready &&
            !state.busy && !state.sessionEnded && !StoryOverlay.ShowsStory(state) && state.view == "cabin" && (state.learning == null || state.learning.active) && Array.IndexOf(CareIds, actionId) >= 0 &&
            (!string.IsNullOrEmpty(state.learning?.creatureId) ? HasSelectedCompanion(state) :
                state.egg != null && state.egg.active && !string.IsNullOrEmpty(state.egg.id));

        public static AppAction CommonCareIntent(AppState state, string actionId) => !CanCommonCare(state, actionId) ? null :
            new AppAction { action = "commonCare", actionId = actionId, creatureId = state.learning?.creatureId ?? "", eggId = state.egg?.id };

        void OnLearningTargetChanged(AppState next)
        {
            if (_state?.learning?.creatureId == next?.learning?.creatureId && _state?.isDemo == next?.isDemo) return;
            _companionText = ""; _choosingCompanion = false;
            if (EventSystem.current != null) EventSystem.current.SetSelectedGameObject(null);
        }

        void BuildCommonCareDock()
        {
            var dock = Surface("Common care dock", _content, Cream);
            Stretch(dock, -430, 88, 430, 156, new Vector2(.5f, 0), new Vector2(.5f, 0));
            var row = Rect("Seven care actions", dock); Stretch(row, 8, 8, -8, -8); Row(row, 8);
            for (var i = 0; i < CareIds.Length; i++)
            {
                var id = CareIds[i];
                LiveEnable(Button(row, CareNames[i], () =>
                {
                    var intent = CommonCareIntent(_state, id);
                    if (intent != null) Send("commonCare", intent);
                }, id == "pet" ? Yellow : Cream, 52, false, 20), () => CanCommonCare(_state, id), id == "pet" ? Yellow : Cream);
            }
        }

        void BuildCompanionSelector()
        {
            var selector = Surface("Care target selector", _content, Cream);
            Stretch(selector, -430, -68, -8, -8, new Vector2(1, 1), new Vector2(1, 1));
            var row = Rect("Selected care target", selector); Stretch(row, 8, 6, -8, -6); Row(row, 8);
            var selected = HasSelectedCompanion(_state);
            var caption = selected ? _state.learning.name + "와 함께" : "알과 함께";
            Button(row, caption, null, selected ? Mint : Cream, 48, false, 20);
            Button(row, _choosingCompanion ? "선택 닫기" : "친구 고르기", () => { _choosingCompanion = !_choosingCompanion; _speechDrawer = _zoneDrawer = false; _dirty = true; }, Cream, 48, CanAct && Items(_state.learning?.creatures).Length > 0, 20);
            if (!_choosingCompanion) return;
            var panel = LearningSheet("Choose care target");
            Heading(panel, "함께할 친구");
            if (_state.egg != null && _state.egg.active)
                Button(panel, "알 돌보기", () => SelectLearningCompanion(""), Cream, 52, CanAct, 21);
            foreach (var creature in Items(_state.learning?.creatures))
            {
                var id = creature.creatureId;
                Button(panel, creature.name + (id == _state.learning.creatureId ? " · 함께하는 중" : ""),
                    () => SelectLearningCompanion(id), id == _state.learning.creatureId ? Mint : Cream, 52, CanAct, 21);
            }
        }

        void SelectLearningCompanion(string id)
        {
            _choosingCompanion = false; _speechDrawer = _zoneDrawer = false; _companionText = ""; _dirty = true;
            Send("selectCompanion", new AppAction { creatureId = id });
        }

        RectTransform LearningSheet(string name)
        {
            var host = Rect(name, _content);
            Stretch(host, -430, 164, -8, -78, new Vector2(1, 0), Vector2.one);
            return Sheet(host);
        }

        void BuildCompanionLearning()
        {
            if (_choosingCompanion) return;
            var learning = _state.learning;
            var target = learning.creatureId;
            var panel = LearningSheet("Companion story and chat");
            Heading(panel, string.IsNullOrEmpty(learning.title) ? learning.name + "의 이야기" : learning.title);
            if (!learning.available)
            {
                Copy(panel, "이 친구의 이야기를 준비하고 있어요. 함께 돌보며 놀 수 있어요.", 22);
                return;
            }
            Button(panel, learning.muted ? "목소리 켜기" : "목소리 끄기", () => Send("learningMute"), Cream, 48, CanAct, 20);
            if (!string.IsNullOrEmpty(learning.text)) Copy(panel, learning.text, 23);
            if (learning.source == "fallback" || learning.source == "authored") Note(panel, "미리 준비한 이야기예요.");
            if (!string.IsNullOrEmpty(learning.error)) Note(panel, learning.error);
            if (_state.sessionEnded || !learning.active) Note(panel, "다음 여행에서 이야기를 이어갈 수 있어요.");
            if (learning.busy || learning.recording) Note(panel, learning.recording ? "말을 듣고 있어요." : "친구가 답을 생각하고 있어요.");
            var story = NewRow(panel, 52);
            LiveEnable(Button(story, "이야기 다시 듣기", () => SendLearning("storyRepeat", target), Cream, 52, false, 19), () => CanCompanionTalk(_state), Cream);
            LiveEnable(Button(story, "다음 이야기", () => SendLearning("storyNext", target), Yellow, 52, false, 20), () => CanCompanionTalk(_state) && _state.learning.canNext, Yellow);
            Field(panel, _companionText, "궁금한 말을 적어 주세요", value => _companionText = value, 240);
            var chat = NewRow(panel, 52);
            LiveEnable(Button(chat, "적은 말 전하기", () =>
            {
                SendLearning("companionChat", target, _companionText.Trim()); _companionText = ""; _dirty = true;
            }, Yellow, 52, false, 19), () => CanCompanionTalk(_state) && !string.IsNullOrWhiteSpace(_companionText), Yellow);
            LiveEnable(Button(chat, "친구에게 말 걸기", () => SendLearning("companionSpeech", target), Cream, 52, false, 19), () => CanCompanionTalk(_state) && _state.learning.speechAvailable, Cream);
        }

        void SendLearning(string action, string target, string text = null)
        {
            if (!CanCompanionTalk(_state) || _state.learning.creatureId != target) return;
            Send(action, new AppAction { creatureId = target, text = text });
        }
    }
}
