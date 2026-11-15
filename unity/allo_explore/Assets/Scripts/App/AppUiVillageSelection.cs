using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        bool _villageSelectionOpen;
        string _villageSelectionPending;
        readonly List<string> _villageSelectionDraft = new List<string>();

        void SyncVillageSelection(AppState next)
        {
            if (!_villageSelectionOpen) return;
            if (next == null || !next.ready || (next.view != "home" && next.view != "camp") ||
                (_state != null && next.view != _state.view)) { CloseVillageSelection(); return; }
            _villageSelectionDraft.RemoveAll(id => !Items(next.creatures).Any(c => c.id == id));
            if (string.IsNullOrEmpty(_villageSelectionPending)) return;
            if (next.villageSelectionRequestId == _villageSelectionPending) CloseVillageSelection();
            else if (!next.busy && !string.IsNullOrEmpty(next.error)) _villageSelectionPending = null;
        }

        void CloseVillageSelection()
        {
            _villageSelectionOpen = false; _villageSelectionPending = null;
            _villageSelectionDraft.Clear(); _dirty = true;
        }

        void OpenVillageSelection()
        {
            if (!CanAct || !_state.villageSelectionReady || _confirmAction != null ||
                (View != "home" && View != "camp") || StoryOverlay.OwnsInput(_state)) return;
            CloseQuestCard(true);
            CloseVillageCharacterDetail(); _campDetail = false;
            _villageSelectionDraft.Clear();
            _villageSelectionDraft.AddRange(_state.villageCreatureIds ?? Items(_state.creatures).Take(4).Select(c => c.id).ToArray());
            _villageSelectionOpen = true; _villageSelectionPending = null;
            _scrollPositions.Remove(View + ":village-selection");
            _villageScroll.StopMovement(); _dirty = true;
        }

        void BuildVillageSelectionEntry()
        {
            if (!string.IsNullOrEmpty(_villageCreatureId) || (View == "camp" && _campDetail)) return;
            var entry = Button(_content, "마을 친구 선택", OpenVillageSelection, Cream, 44,
                CanAct && _state.villageSelectionReady, 20);
            Stretch((RectTransform)entry.transform, 12, 12, 206, 56, Vector2.zero, Vector2.zero);
        }

        void BuildVillageSelection()
        {
            var panel = DockSheet(486); panel.parent.parent.name = "Village friend selector";
            var scroll = panel.GetComponentInParent<ScrollRect>();
            var sharedKey = _scrolls.First(entry => entry.Value == scroll).Key;
            _scrolls.Remove(sharedKey); _scrolls[View + ":village-selection"] = scroll;
            Heading(panel, "마을 친구 선택");
            Copy(panel, "선택 " + _villageSelectionDraft.Count + " / 4", 24);
            Note(panel, "마을에서 함께 지낼 친구를 골라 주세요. 아무도 고르지 않아도 괜찮아요.");
            var actions = NewRow(panel, 46);
            var canEdit = CanAct && string.IsNullOrEmpty(_villageSelectionPending);
            Button(actions, "취소", CloseVillageSelection, Cream, 46, canEdit, 21);
            Button(actions, "저장", () =>
            {
                if (!CanAct || !_villageSelectionOpen || !string.IsNullOrEmpty(_villageSelectionPending) || StoryOverlay.OwnsInput(_state)) return;
                _villageSelectionPending = AppSession.Request("setVillageFriends", new AppAction { creatureIds = _villageSelectionDraft.ToArray() });
                _dirty = true;
            }, Yellow, 46, canEdit && _state.villageSelectionReady, 21);
            if (!string.IsNullOrEmpty(_villageSelectionPending)) Note(panel, "선택을 저장하고 있어요.");
            else if (!string.IsNullOrEmpty(_state.error)) Note(panel, _state.error);
            if (Items(_state.creatures).Length == 0) Note(panel, "알에서 친구를 만나면 여기에서 고를 수 있어요.");
            foreach (var creature in Items(_state.creatures))
            {
                var id = creature.id; var chosen = _villageSelectionDraft.Contains(id);
                var row = Button(panel, (chosen ? "✓  " : "+  ") + creature.name + " · " + ShortId(id), () =>
                {
                    if (!CanAct || !_villageSelectionOpen || !string.IsNullOrEmpty(_villageSelectionPending) || StoryOverlay.OwnsInput(_state)) return;
                    if (!_villageSelectionDraft.Remove(id) && _villageSelectionDraft.Count < 4) _villageSelectionDraft.Add(id);
                    _dirty = true;
                }, chosen ? Mint : Cream, 66, canEdit && (chosen || _villageSelectionDraft.Count < 4), 22);
                row.name = "Village choice " + id;
            }
        }
    }
}
