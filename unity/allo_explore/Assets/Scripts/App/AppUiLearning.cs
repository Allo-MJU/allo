using System;
using System.Linq;
using UnityEngine;
using UnityEngine.EventSystems;
using Allo.Critters;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        static readonly string[] CareIds = { "snack", "water", "ball", "pet", "plush", "cushion", "blanket" };
        static readonly string[] CareNames = { "간식", "물", "공", "쓰다듬기", "인형", "쿠션", "담요" };
        string _companionText = "";
        RectTransform _companionBubble;
        bool _invitationDismissed, _nativeSpeechExpected, _nativeSpeechObserved, _nativeSpeechHidden;
        float _nativeSpeechDeadline;

        public static bool HasSelectedCompanion(AppState state)
        {
            var learning = state?.learning;
            return learning != null && !string.IsNullOrEmpty(learning.creatureId) &&
                Items(learning.creatures).Any(c => c.creatureId == learning.creatureId && c.speciesId == learning.speciesId);
        }

        public static bool CanCompanionTalk(AppState state) => state != null && state.ready && !state.busy &&
            state.view == "cabin" && !StoryOverlay.CapturingInput && !StoryOverlay.ShowsStory(state) && !state.sessionEnded && HasSelectedCompanion(state) &&
            state.learning.active && state.learning.available && !state.learning.busy && !state.learning.recording;

        public static bool CanCommonCare(AppState state, string actionId) => state != null && state.ready &&
            !state.busy && !state.sessionEnded && !StoryOverlay.CapturingInput && !StoryOverlay.ShowsStory(state) && state.view == "cabin" && (state.learning == null || state.learning.active) && Array.IndexOf(CareIds, actionId) >= 0 &&
            (!string.IsNullOrEmpty(state.learning?.creatureId) ? HasSelectedCompanion(state) :
                state.egg != null && state.egg.active && !string.IsNullOrEmpty(state.egg.id));

        public static AppAction CommonCareIntent(AppState state, string actionId) => !CanCommonCare(state, actionId) ? null :
            new AppAction { action = "commonCare", actionId = actionId, creatureId = state.learning?.creatureId ?? "", eggId = state.egg?.id };

        void OnLearningTargetChanged(AppState next)
        {
            var targetChanged = _state?.learning?.creatureId != next?.learning?.creatureId ||
                _state?.learning?.speciesId != next?.learning?.speciesId || _state?.isDemo != next?.isDemo;
            var closing = next?.view != "cabin" || next?.learning == null || !next.learning.active ||
                next.sessionEnded || next.learning.conversationMode == "closed";
            if (!targetChanged && !closing) return;
            if (_companionBubble != null) _companionBubble.gameObject.SetActive(false);
            _companionBubble = null;
            _companionText = "";
            if (targetChanged || closing)
            {
                _nativeSpeechExpected = _nativeSpeechObserved = _nativeSpeechHidden = false;
                if (targetChanged) _invitationDismissed = false;
            }
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

        public static bool CanInviteCompanion(AppState state, string speciesId) =>
            state != null && state.ready && !state.busy && state.view == "cabin" && !state.sessionEnded &&
            !StoryOverlay.ShowsStory(state) && !StoryOverlay.CapturingInput && HasSelectedCompanion(state) &&
            state.learning.active && !state.learning.busy && !state.learning.recording && state.learning.speciesId == speciesId;

        public static bool CanChooseCompanionInvitation(AppState state) => CanCompanionTalk(state) &&
            state.learning.invitationOpen && state.learning.conversationMode == "menu" &&
            !string.IsNullOrWhiteSpace(state.learning.invitationText);

        void SyncNativeCompanionSpeech(AppState state)
        {
            if (state?.learning?.recording == true) _nativeSpeechObserved = true;
            else if (_nativeSpeechObserved) _nativeSpeechExpected = _nativeSpeechObserved = false;
        }

        void OnCompanionForegroundChanged(bool foreground)
        {
            if (foreground) { _nativeSpeechHidden = false; _dirty = true; return; }
            var learning = _state?.learning;
            var nativeModal = _state?.view == "cabin" && learning != null && learning.active &&
                learning.conversationMode == "chat" && (learning.recording ||
                    (_nativeSpeechExpected && Time.realtimeSinceStartup <= _nativeSpeechDeadline));
            if (!nativeModal) { CloseCompanionInvitation(); return; }
            // Our microphone Activity pauses Unity before its recording snapshot can arrive.
            _nativeSpeechHidden = true;
            if (_companionBubble != null) _companionBubble.gameObject.SetActive(false);
            if (EventSystem.current != null) EventSystem.current.SetSelectedGameObject(null);
        }

        public static AppAction CompanionInvitationIntent(AppState state, string speciesId) =>
            !CanInviteCompanion(state, speciesId) ? null : new AppAction
            { action = "companionTapped", creatureId = state.learning.creatureId, speciesId = speciesId };

        void OnCompanionTapped(string speciesId)
        {
            if (StoryUiBlocked || (_storyOverlay != null && _storyOverlay.ShowingNotebook)) return;
            var intent = CompanionInvitationIntent(_state, speciesId);
            if (intent == null) return;
            _invitationDismissed = false;
            Send("companionTapped", intent);
        }

        void CloseCompanionInvitation()
        {
            if (_companionBubble != null) _companionBubble.gameObject.SetActive(false);
            if (_invitationDismissed || string.IsNullOrEmpty(_state?.learning?.creatureId) ||
                string.IsNullOrEmpty(_state.learning.conversationMode) || _state.learning.conversationMode == "closed") return;
            _invitationDismissed = true;
            _nativeSpeechExpected = _nativeSpeechObserved = _nativeSpeechHidden = false;
            Send("closeCompanionInvitation", new AppAction { creatureId = _state.learning.creatureId, speciesId = _state.learning.speciesId });
        }

        void BuildCompanionLearning()
        {
            _companionBubble = null;
            var learning = _state.learning;
            if (_nativeSpeechHidden || _invitationDismissed || learning.conversationMode == "closed" || string.IsNullOrEmpty(learning.conversationMode)) return;
            if (!HasSelectedCompanion(_state) || !learning.active || _state.sessionEnded) return;
            var menu = learning.conversationMode == "menu" && learning.invitationOpen;
            _companionBubble = Rect("Companion head bubble", _content);
            _companionBubble.anchorMin = _companionBubble.anchorMax = new Vector2(.5f, .5f);
            _companionBubble.pivot = new Vector2(.5f, 0);
            _companionBubble.sizeDelta = new Vector2(440, menu ? (learning.available && string.IsNullOrEmpty(learning.error) ? 250 : 310) : learning.conversationMode == "chat" ? 370 : 310);
            var panel = Sheet(_companionBubble);
            var target = learning.creatureId;
            var top = NewRow(panel, 44);
            Copy(top, learning.name, 22);
            Button(top, "닫기", CloseCompanionInvitation, Cream, 44, true, 19);
            if (menu)
            {
                if (learning.busy) Copy(panel, "친구의 답을 기다리고 있어요.", 23);
                else if (!string.IsNullOrWhiteSpace(learning.invitationText)) Copy(panel, learning.invitationText, 23);
                else if (learning.available && string.IsNullOrEmpty(learning.error)) Note(panel, "친구를 다시 눌러 연결해 주세요.");
                if (!string.IsNullOrEmpty(learning.error)) Note(panel, learning.error);
                else if (!learning.available) Note(panel, "이 친구의 이야기는 준비 중이에요. 함께 놀 수 있어요.");
                var choices = NewRow(panel, 52);
                LiveEnable(Button(choices, "이야기 듣기", () => SendLearning("listenStory", target), Yellow, 52, false, 21), () => CanChooseCompanionInvitation(_state), Yellow);
                LiveEnable(Button(choices, "말 걸기", () => SendLearning("talkToCompanion", target), Cream, 52, false, 21), () => CanChooseCompanionInvitation(_state), Cream);
                return;
            }
            if (!string.IsNullOrEmpty(learning.text)) Copy(panel, learning.text, 23);
            if (!string.IsNullOrEmpty(learning.error)) Note(panel, learning.error);
            if (learning.busy || learning.recording) Note(panel, learning.recording ? "말을 듣고 있어요." : "친구가 답을 생각하고 있어요.");
            if (learning.conversationMode == "story")
            {
                var story = NewRow(panel, 52);
                LiveEnable(Button(story, "이야기 다시 듣기", () => SendLearning("storyRepeat", target), Cream, 52, false, 19), () => CanCompanionTalk(_state), Cream);
                LiveEnable(Button(story, "다음 이야기", () => SendLearning("storyNext", target), Yellow, 52, false, 20), () => CanCompanionTalk(_state) && _state.learning.canNext, Yellow);
            }
            else if (learning.conversationMode == "chat")
            {
                Field(panel, _companionText, "궁금한 말을 적어 주세요", value => _companionText = value, 240);
                var chat = NewRow(panel, 52);
                LiveEnable(Button(chat, "적은 말 전하기", () =>
                { SendLearning("companionChat", target, _companionText.Trim()); _companionText = ""; _dirty = true; }, Yellow, 52, false, 19), () => CanCompanionTalk(_state) && !string.IsNullOrWhiteSpace(_companionText), Yellow);
                LiveEnable(Button(chat, "친구에게 말 걸기", () => SendLearning("companionSpeech", target), Cream, 52, false, 19), () => CanCompanionTalk(_state) && _state.learning.speechAvailable, Cream);
            }
            Button(panel, learning.muted ? "목소리 켜기" : "목소리 끄기", () => Send("learningMute"), Cream, 44, CanAct, 19);
        }

        public static bool HeadAnchorVisible(Camera camera, Vector3 top)
        {
            if (camera == null) return false;
            var point = camera.WorldToViewportPoint(top);
            return point.z > 0 && point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1;
        }

        void PlaceCompanionBubble()
        {
            if (_companionBubble == null) return;
            if (_nativeSpeechHidden) { _companionBubble.gameObject.SetActive(false); return; }
            if (_state?.view != "cabin" || _state.sessionEnded || !_state.learning.active || StoryUiBlocked ||
                StoryOverlay.ShowsStory(_state) || (_storyOverlay != null && _storyOverlay.ShowingNotebook))
            { CloseCompanionInvitation(); return; }
            var director = FindFirstObjectByType<CritterDirector>();
            var companion = director != null ? director.Companion : null;
            var camera = Camera.main;
            if (companion == null || companion.Id != _state.learning.speciesId || !companion.gameObject.activeInHierarchy || !HeadAnchorVisible(camera, companion.Top))
            { CloseCompanionInvitation(); return; }
            RectTransformUtility.ScreenPointToLocalPointInRectangle(_content, camera.WorldToScreenPoint(companion.Top), null, out var point);
            var bounds = _content.rect;
            var halfWidth = Mathf.Min(220, bounds.width / 2 - 8);
            _companionBubble.sizeDelta = new Vector2(halfWidth * 2, Mathf.Min(_companionBubble.sizeDelta.y, bounds.height - 172));
            _companionBubble.localPosition = new Vector3(Mathf.Clamp(point.x, bounds.xMin + halfWidth + 8, bounds.xMax - halfWidth - 8),
                Mathf.Clamp(point.y + 12, bounds.yMin + 160, bounds.yMax - _companionBubble.sizeDelta.y - 8), 0);
        }

        void SendLearning(string action, string target, string text = null)
        {
            if (!CanCompanionTalk(_state) || StoryUiBlocked || _state.learning.creatureId != target || _invitationDismissed) return;
            if ((action == "listenStory" || action == "talkToCompanion") && !CanChooseCompanionInvitation(_state)) return;
            if (action == "companionSpeech")
            {
                _nativeSpeechExpected = true;
                _nativeSpeechObserved = false;
                _nativeSpeechDeadline = Time.realtimeSinceStartup + 10;
            }
            Send(action, new AppAction { creatureId = target, speciesId = _state.learning.speciesId, text = text });
        }
    }
}
