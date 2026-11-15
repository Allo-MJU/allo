using System;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        string _questCreatureId, _questId, _questPlaceId;

        QuestState QuestFor(string creatureId) => Items(_state?.quests).FirstOrDefault(q => q != null &&
            q.creatureId == creatureId && q.available && !string.IsNullOrEmpty(q.questId) &&
            Items(_state?.creatures).Any(c => c.id == creatureId));

        bool CloseQuestCard(bool notifyHost = false)
        {
            if (string.IsNullOrEmpty(_questId)) return false;
            var quest = QuestFor(_questCreatureId);
            if (notifyHost && quest != null && quest.questId == _questId)
                AppSession.Request("laterQuest", new AppAction { creatureId = _questCreatureId, questId = _questId });
            _questCreatureId = _questId = _questPlaceId = null;
            _dirty = true;
            return true;
        }

        void SyncQuestCard(AppState state)
        {
            if (string.IsNullOrEmpty(_questId)) return;
            if (state == null || !state.ready || state.view != _state?.view ||
                !Items(state.creatures).Any(c => c.id == _questCreatureId) ||
                !Items(state.quests).Any(q => q != null && q.available && q.creatureId == _questCreatureId && q.questId == _questId))
                CloseQuestCard();
        }

        void UpdateQuestMarker(RectTransform marker, string creatureId)
        {
            var quest = QuestFor(creatureId);
            var visible = quest != null && quest.status != "completed";
            var badge = marker.Find("Quest marker " + creatureId) as RectTransform;
            if (badge == null && visible)
            {
                badge = Rect("Quest marker " + creatureId, marker);
                badge.anchorMin = badge.anchorMax = new Vector2(1, .82f);
                badge.anchoredPosition = new Vector2(-8, 0); badge.sizeDelta = new Vector2(40, 40);
                var image = badge.gameObject.AddComponent<Image>(); image.sprite = ActionCircleSprite();
                image.color = Yellow; image.raycastTarget = false;
                var outline = badge.gameObject.AddComponent<Outline>(); outline.effectColor = Ink; outline.effectDistance = new Vector2(1, -1);
                var question = Label(badge, "?", 29, TextAnchor.MiddleCenter); Stretch(question.rectTransform);
                question.color = Ink; question.raycastTarget = false;
            }
            if (badge != null) badge.gameObject.SetActive(visible);
        }

        void OpenQuest(string creatureId, string questId)
        {
            var quest = QuestFor(creatureId);
            if (!CanAct || quest == null || quest.questId != questId || quest.busy ||
                _villageSelectionOpen || _confirmAction != null || StoryOverlay.OwnsInput(_state) ||
                (View != "home" && View != "camp" && View != "dex")) return;
            _questCreatureId = creatureId; _questId = questId; _questPlaceId = quest.targetPlaceId;
            Send("openQuest", new AppAction { creatureId = creatureId, questId = questId });
            _dirty = true;
        }

        void QuestIntent(string action, string creatureId, string questId, string placeId = null)
        {
            var quest = QuestFor(creatureId);
            if (!CanAct || quest == null || quest.busy || quest.questId != questId ||
                _villageSelectionOpen || StoryOverlay.OwnsInput(_state) ||
                _questCreatureId != creatureId || _questId != questId || !quest.opened) return;
            if (action == "acceptQuest" && quest.status != "offered") return;
            if ((action == "observeQuest" || action == "requestQuestTravel") && quest.status != "accepted") return;
            if (action == "observeQuest" && quest.kind != "story") return;
            if (action == "requestQuestTravel" && (quest.kind != "travel" || string.IsNullOrEmpty(placeId))) return;
            if (action == "acceptQuest" && quest.kind == "travel" &&
                !Items(quest.candidates).Any(p => p != null && p.placeId == placeId)) return;
            if (action == "requestQuestTravel" && !string.IsNullOrEmpty(quest.targetPlaceId) && quest.targetPlaceId != placeId) return;
            Send(action, new AppAction { creatureId = creatureId, questId = questId, placeId = placeId });
            if (action == "laterQuest") CloseQuestCard();
        }

        static string QuestRegionLabel(string region) => region == "coast" ? "바다" :
            region == "mountain" ? "산" : region == "city" ? "도심" : "여행지";

        void BuildQuestSection(Transform parent, string creatureId, bool book = false)
        {
            var quest = QuestFor(creatureId);
            if (quest == null) return;
            var opened = _questCreatureId == creatureId && _questId == quest.questId;
            var row = NewRow(parent, 48);
            row.GetComponent<HorizontalLayoutGroup>().childForceExpandWidth = false;
            var invitation = Button(row, "?", () => OpenQuest(creatureId, quest.questId), Yellow, 48, CanAct && !quest.busy, 28);
            invitation.name = "Quest invitation " + creatureId;
            var size = invitation.GetComponent<LayoutElement>(); size.minWidth = size.preferredWidth = 48; size.flexibleWidth = 0;
            invitation.GetComponent<Image>().sprite = ActionCircleSprite();
            invitation.GetComponent<Image>().type = Image.Type.Simple;
            var heading = Copy(row, opened ? "친구의 부탁" : "할 이야기가 있어요", 23);
            heading.color = book ? BookInk : Ink; heading.GetComponent<LayoutElement>().flexibleWidth = 1;
            if (!opened) return;
            var card = Rect("Quest body " + creatureId, parent); Column(card, 8);
            var contentSize = card.gameObject.AddComponent<ContentSizeFitter>(); contentSize.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            var layout = card.gameObject.AddComponent<LayoutElement>(); layout.flexibleWidth = 1;
            Action<string, int> copy = (value, fontSize) =>
            {
                if (string.IsNullOrEmpty(value)) return;
                if (book) BookCopy(card, value, fontSize); else Copy(card, value, fontSize);
            };
            Func<string, Action, bool, bool, Button> button = (label, action, primary, enabled) =>
                book ? BookButton(card, label, action, primary, enabled) : Button(card, label, action, primary ? Yellow : Cream, 48, enabled, 21);
            if (quest.busy || !quest.opened) copy("부탁을 확인하고 있어요.", 20);
            if (!string.IsNullOrEmpty(quest.error))
            {
                copy(quest.error, 20);
                button("부탁 다시 확인", () => OpenQuest(creatureId, quest.questId), false, CanAct && !quest.busy);
            }
            if (!quest.opened) return;
            copy(quest.title, 25); copy(quest.text, 22); copy(quest.requirement, 20);
            var canAct = CanAct && !quest.busy;
            if (quest.status == "completed")
            {
                copy("함께해 줘서 고마워!", 22);
                button("부탁 접기", () => CloseQuestCard(true), false, true);
                return;
            }
            if (quest.kind == "travel")
            {
                if (quest.status == "offered")
                {
                    foreach (var candidate in Items(quest.candidates).Where(p => p != null && !string.IsNullOrEmpty(p.placeId)))
                    {
                        var selected = candidate;
                        button(candidate.name + " · " + QuestRegionLabel(candidate.region), () =>
                        {
                            if (!CanAct || _villageSelectionOpen || StoryOverlay.OwnsInput(_state) ||
                                _questCreatureId != creatureId || _questId != quest.questId ||
                                QuestFor(creatureId)?.questId != quest.questId) return;
                            _questPlaceId = selected.placeId; _dirty = true;
                        }, _questPlaceId == candidate.placeId, canAct);
                    }
                    if (!Items(quest.candidates).Any(p => p != null && !string.IsNullOrEmpty(p.placeId))) copy("여행할 장소를 준비하고 있어요.", 20);
                }
                else if (quest.status == "accepted")
                {
                    var targetId = quest.targetPlaceId;
                    var target = Items(quest.candidates).FirstOrDefault(p => p != null && p.placeId == targetId);
                    if (target != null) copy("함께 갈 곳 · " + target.name, 21);
                    copy("보호자가 차량에서 확인한 뒤 길 안내를 시작해요.", 20);
                    button("보호자에게 여행 제안", () => QuestIntent("requestQuestTravel", creatureId, quest.questId, targetId), true,
                        canAct && !string.IsNullOrEmpty(targetId));
                }
            }
            if (quest.status == "offered")
                button("함께하기", () => QuestIntent("acceptQuest", creatureId, quest.questId, _questPlaceId), true,
                    canAct && (quest.kind != "travel" || Items(quest.candidates).Any(p => p != null && p.placeId == _questPlaceId)));
            else if (quest.status == "accepted" && quest.kind == "story")
                button("찾아봤어", () => QuestIntent("observeQuest", creatureId, quest.questId), true, canAct);
            else if (quest.status == "accepted" && quest.kind == "food")
            {
                copy("아래 요리 주기에서 음식을 나눠 주세요.", 20);
                if (!Items(_state.foods).Any(f => f.count > 0))
                    button("요리 확인하기", () =>
                    {
                        _supplyTab = "foods"; Navigate("inventory");
                    }, false, canAct);
            }
            button("나중에", () => QuestIntent("laterQuest", creatureId, quest.questId), false, canAct);
        }
    }
}
