using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        string _villageCreatureId;
        readonly Dictionary<string, float> _villageFriendTime = new Dictionary<string, float>();

        void SyncVillageCharacter(AppState state)
        {
            if (string.IsNullOrEmpty(_villageCreatureId)) return;
            if (state == null || !state.ready || (state.view != "home" && state.view != "camp") ||
                (_state != null && _state.view != state.view) ||
                !Items(state.creatures).Any(c => c.id == _villageCreatureId))
            {
                _villageCreatureId = null;
                _confirmAction = null;
                _confirmTitle = null;
            }
        }

        void OpenVillageFriend(string creatureId)
        {
            if (!CanAct || _confirmAction != null || (View != "home" && View != "camp") ||
                !Items(_state.creatures).Any(c => c.id == creatureId)) return;
            _villageCreatureId = creatureId;
            _selectedCreature = creatureId;
            _campDetail = false;
            _villageScroll.StopMovement();
            _scrollPositions.Remove(View + ":character:" + creatureId);
            _dirty = true;
        }

        public bool CloseVillageCharacterDetail()
        {
            if (string.IsNullOrEmpty(_villageCreatureId)) return false;
            if (_confirmAction != null) { _confirmAction = null; _confirmTitle = null; }
            else _villageCreatureId = null;
            _dirty = true;
            return true;
        }

        void TickVillageFriends(float deltaTime)
        {
            if (!CanAct || _state.reducedMotion || (View != "home" && View != "camp") ||
                _confirmAction != null || (View == "camp" && _campDetail) || !string.IsNullOrEmpty(_villageCreatureId) ||
                Input.GetMouseButton(0) || Input.touchCount > 0 ||
                (_villageScroll != null && _villageScroll.velocity.sqrMagnitude > 4)) return;
            foreach (var entry in _villageFriends)
            {
                var time = _villageFriendTime[entry.Key] + Mathf.Max(0, deltaTime);
                _villageFriendTime[entry.Key] = time;
                uint seed = 2166136261;
                foreach (var c in entry.Key) seed = unchecked((seed ^ c) * 16777619);
                var phase = seed % 628 * .01f;
                entry.Value.anchoredPosition = new Vector2(
                    26 * (Mathf.Sin(phase + time * .35f) - Mathf.Sin(phase)),
                    10 * (Mathf.Sin(phase * .7f + time * .27f) - Mathf.Sin(phase * .7f)));
            }
        }

        void BuildVillageCharacterDetail()
        {
            if (string.IsNullOrEmpty(_villageCreatureId)) return;
            var creature = Items(_state.creatures).FirstOrDefault(c => c.id == _villageCreatureId);
            if (creature == null) { CloseVillageCharacterDetail(); return; }
            var detail = Rect("Village character detail", _content);
            Stretch(detail);
            var shade = detail.gameObject.AddComponent<Image>(); shade.color = new Color(.07f, .12f, .10f, .35f);
            var preview = Rect("Enlarged character", detail);
            Stretch(preview, 24, 42, -24, -32, Vector2.zero, new Vector2(.55f, 1));
            VillageFriendPortrait(preview, creature.sprite);
            var panel = Sheet(detail, .56f, 1);
            var scroll = panel.GetComponentInParent<ScrollRect>();
            var sharedKey = _scrolls.First(entry => entry.Value == scroll).Key;
            _scrolls.Remove(sharedKey);
            _scrolls[View + ":character:" + creature.id] = scroll;
            Button(panel, "상세 닫기", () => CloseVillageCharacterDetail(), Cream, 48, true, 20);
            Heading(panel, creature.name);
            Copy(panel, RoleLabel(creature.role), 23);
            var species = Items(_state.dex).FirstOrDefault(d => d.id == creature.speciesId);
            if (!string.IsNullOrEmpty(species?.description)) Note(panel, species.description);
            CreatureActions(panel, creature);
            Space(panel);
            Copy(panel, "친구에게 요리 주기", 27);
            FeedOptions(panel, creature.id);
        }
    }
}
