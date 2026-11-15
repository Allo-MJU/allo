using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        string _villageCreatureId;
        sealed class VillageWalk
        {
            public uint seed;
            public Vector2 target;
            public float pause;
            public bool moving, facingLeft = true;
            public VillageCharacterArt art;
        }
        readonly Dictionary<string, VillageWalk> _villageWalking = new Dictionary<string, VillageWalk>();
        VillageCharacterArt _villageDetailArt;
        float _villagePreviewElapsed;

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
            _villagePreviewElapsed = 0;
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

        VillageWalk CreateVillageWalk(string id, VillageCharacterArt art)
        {
            uint seed = 2166136261;
            foreach (var c in id) seed = unchecked((seed ^ c) * 16777619);
            var walk = new VillageWalk { seed = seed, art = art };
            walk.pause = .2f + WalkRandom(walk) * .8f;
            return walk;
        }

        static float WalkRandom(VillageWalk walk)
        {
            walk.seed = unchecked(walk.seed * 1664525 + 1013904223);
            return (walk.seed >> 8) / 16777216f;
        }

        void ChooseVillageDestination(RectTransform marker, VillageWalk walk)
        {
            var size = _villageContent.rect.size;
            var minX = Mathf.Max(-140, (.10f - marker.anchorMin.x) * size.x);
            var maxX = Mathf.Min(140, (.78f - marker.anchorMin.x) * size.x);
            var minY = Mathf.Max(-55, (.12f - marker.anchorMin.y) * size.y);
            var maxY = Mathf.Min(55, (.34f - marker.anchorMin.y) * size.y);
            for (var attempt = 0; attempt < 6; attempt++)
            {
                walk.target = new Vector2(Mathf.Lerp(minX, maxX, WalkRandom(walk)), Mathf.Lerp(minY, maxY, WalkRandom(walk)));
                if (Vector2.Distance(marker.anchoredPosition, walk.target) >= 55) break;
            }
            walk.moving = true;
        }

        void TickVillageFriends(float deltaTime)
        {
            if (_state == null) return;
            var dt = Mathf.Max(0, deltaTime);
            var village = View == "home" || View == "camp";
            var protectedInput = !CanAct || !village || _state.reducedMotion || _confirmAction != null ||
                (View == "camp" && _campDetail) || !string.IsNullOrEmpty(_villageCreatureId) ||
                Input.GetMouseButton(0) || Input.touchCount > 0 ||
                (_villageScroll != null && _villageScroll.velocity.sqrMagnitude > 4);
            if (_villageDetailArt != null && village && _confirmAction == null)
            {
                _villageDetailArt.SetMotion(CanAct, true, _state.reducedMotion);
                if (CanAct && !_state.reducedMotion) _villagePreviewElapsed += dt;
            }
            foreach (var entry in _villageFriends)
            {
                if (!_villageWalking.TryGetValue(entry.Key, out var walk)) continue;
                if (protectedInput)
                {
                    walk.art?.SetMotion(false, walk.facingLeft, _state.reducedMotion); continue;
                }
                var step = Mathf.Min(dt, .1f);
                if (!walk.moving)
                {
                    walk.pause -= step;
                    if (walk.pause <= 0) ChooseVillageDestination(entry.Value, walk);
                }
                if (walk.moving)
                {
                    var direction = walk.target - entry.Value.anchoredPosition;
                    if (Mathf.Abs(direction.x) > .1f) walk.facingLeft = direction.x < 0;
                    entry.Value.anchoredPosition = Vector2.MoveTowards(entry.Value.anchoredPosition, walk.target, 42 * step);
                    if (Vector2.Distance(entry.Value.anchoredPosition, walk.target) < .1f)
                    {
                        walk.moving = false; walk.pause = 1.2f + WalkRandom(walk) * 2;
                    }
                }
                walk.art?.SetMotion(walk.moving, walk.facingLeft, false);
            }
        }

        void BuildVillageCharacterDetail()
        {
            if (string.IsNullOrEmpty(_villageCreatureId)) return;
            var creature = Items(_state.creatures).FirstOrDefault(c => c.id == _villageCreatureId);
            if (creature == null) { CloseVillageCharacterDetail(); return; }
            var detail = Rect("Village character detail", _content); Stretch(detail);
            detail.gameObject.AddComponent<Image>().color = new Color(.04f, .09f, .06f, .35f);
            var inspector = Rect("Character inspector", detail);
            Stretch(inspector, 0, 0, 0, 0, new Vector2(.58f, 0), Vector2.one);
            var panel = Sheet(inspector);
            var scroll = panel.GetComponentInParent<ScrollRect>();
            var sharedKey = _scrolls.First(entry => entry.Value == scroll).Key;
            _scrolls.Remove(sharedKey);
            _scrolls[View + ":character:" + creature.id] = scroll;

            var indicator = Rect("Character scroll indicator", scroll.transform);
            Stretch(indicator, -7, 8, -2, -8, new Vector2(1, 0), Vector2.one);
            var track = indicator.gameObject.AddComponent<Image>(); track.color = new Color(.25f, .37f, .26f, .10f); track.raycastTarget = false;
            var thumb = Surface("Character scroll thumb", indicator, Hex("8A9B80"), false); Stretch(thumb);
            thumb.GetComponent<Image>().raycastTarget = false;
            var bar = indicator.gameObject.AddComponent<Scrollbar>(); bar.direction = Scrollbar.Direction.BottomToTop;
            bar.handleRect = thumb; bar.targetGraphic = thumb.GetComponent<Image>();
            bar.interactable = false; bar.transition = Selectable.Transition.None;
            scroll.verticalScrollbar = bar; scroll.verticalScrollbarVisibility = ScrollRect.ScrollbarVisibility.AutoHide;
            scroll.viewport.offsetMax += new Vector2(-8, 0);

            var header = NewRow(panel, 48);
            header.GetComponent<HorizontalLayoutGroup>().childForceExpandWidth = false;
            var title = Copy(header, creature.name, 31); title.GetComponent<LayoutElement>().flexibleWidth = 1;
            var close = Button(header, "상세 닫기", () => CloseVillageCharacterDetail(), Cream, 44, true, 19);
            var closeSize = close.GetComponent<LayoutElement>(); closeSize.flexibleWidth = 0; closeSize.minWidth = closeSize.preferredWidth = 110;
            CharacterDetailTags(panel, new[] { RoleLabel(creature.role) }, true);
            var species = Items(_state.dex).FirstOrDefault(d => d.id == creature.speciesId);
            if (!string.IsNullOrEmpty(creature.personaSummary))
            {
                var intro = Copy(panel, creature.personaSummary, 22); intro.gameObject.name = "Persona summary";
                CharacterDetailTags(panel, Items(creature.personaTraits).Where(t => !string.IsNullOrWhiteSpace(t)).Take(3).ToArray());
            }
            else if (!string.IsNullOrEmpty(species?.description)) Note(panel, species.description);

            var stage = Rect("Character animation stage", detail);
            Stretch(stage, 16, 28, -24, -20, Vector2.zero, new Vector2(.56f, 1));
            var shadow = Rect("Character ground shadow", stage);
            shadow.anchorMin = shadow.anchorMax = new Vector2(.5f, .10f); shadow.anchoredPosition = Vector2.zero; shadow.sizeDelta = new Vector2(260, 24);
            var shadowImage = shadow.gameObject.AddComponent<Image>(); shadowImage.sprite = ActionCircleSprite(); shadowImage.color = new Color(.15f, .24f, .16f, .16f); shadowImage.raycastTarget = false;
            var preview = Rect("Enlarged character", stage); Stretch(preview, 8, 0, -8, 0);
            _villageDetailArt = VillageFriendPortrait(preview, creature.speciesId, creature.sprite, true);
            _villageDetailArt.SetMotion(CanAct, true, _state.reducedMotion);
            _villageDetailArt.Advance(_villagePreviewElapsed);

            CharacterDetailSection(panel, "지금은");
            var job = Items(_state.jobs).FirstOrDefault(j => j.workerId == creature.id || j.targetId == creature.id);
            var assigned = Items(_state.assignments).FirstOrDefault(a => a.creatureId == creature.id);
            Copy(panel, job != null ? job.label + " 작업 중" : assigned != null ? RoleLabel(assigned.role) + " 담당 · 대기 중" : "자유 시간을 보내고 있어요", 21);
            if (job != null) Progress(panel, job.progress, TimeLabel(job.remainingSec));
            if (creature.foodBoostUntilMs > System.DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()) Note(panel, "든든한 요리의 힘을 받고 있어요.");

            CharacterDetailSection(panel, "할 수 있는 행동");
            var actions = Items(creature.actions);
            if (actions.Length == 0)
            {
                Note(panel, "아직 배운 행동이 없어요. 훈련장에서 새로운 행동을 배울 수 있어요.");
                Button(panel, "훈련장 살펴보기", () => OpenVillageFacility("training"), Cream, 48, CanAct, 21);
            }
            foreach (var action in actions)
            {
                var actionId = action;
                Button(panel, ActionLabel(actionId) + " 보여 주기", () => Send("performAction", new AppAction { creatureId = creature.id, actionId = actionId }), Mint, 52, CanAct && !CreatureBusy(creature.id), 21);
            }
            if (CreatureBusy(creature.id)) Note(panel, "작업이 끝나면 배운 행동을 보여 줄 수 있어요.");

            CharacterDetailSection(panel, "요리로 힘을 보태요");
            var foods = Items(_state.foods).Where(f => f.count > 0).ToArray();
            if (foods.Length == 0)
            {
                Note(panel, "아직 준비된 요리가 없어요. 주방에서 친구에게 줄 요리를 만들 수 있어요.");
                Button(panel, "주방 살펴보기", () => OpenVillageFacility("kitchen"), Cream, 48, CanAct, 21);
            }
            foreach (var food in foods)
            {
                var selectedFood = food;
                Button(panel, food.label + " · " + food.count + "개 · 1개 주기", () => ConfirmIntent(creature.name + "에게 요리를 줄까요?",
                    selectedFood.label + " 1개를 사용해 친구에게 힘을 보태요.", "feedFood", new AppAction { recipeId = selectedFood.id, creatureId = creature.id }), Cream, 52, CanAct, 21);
            }
            if (!string.IsNullOrEmpty(creature.personaSummary) && !string.IsNullOrEmpty(species?.description))
            {
                Space(panel, 6); Note(panel, "만나는 힌트 · " + species.description);
            }
        }

        void CharacterDetailSection(Transform parent, string title)
        {
            Space(parent, 7);
            var rule = Rect("Detail section rule", parent);
            rule.gameObject.AddComponent<LayoutElement>().preferredHeight = 1;
            var image = rule.gameObject.AddComponent<Image>(); image.color = new Color(.20f, .30f, .22f, .15f); image.raycastTarget = false;
            Space(parent, 2); Copy(parent, title, 23);
        }

        void CharacterDetailTags(RectTransform parent, string[] labels, bool role = false)
        {
            if (labels.Length == 0) return;
            var row = NewRow(parent, 32);
            var layout = row.GetComponent<HorizontalLayoutGroup>(); layout.childForceExpandWidth = false; layout.spacing = 7;
            var available = Mathf.Max(240, parent.rect.width - 32);
            var maxWidth = (available - (labels.Length - 1) * 7) / labels.Length;
            foreach (var text in labels)
            {
                var badge = Surface("Profile tag " + text, row, role ? Hex("3F6049") : Mint, false);
                var label = Label(badge, text, role ? 18 : 17, TextAnchor.MiddleCenter);
                label.color = role ? Cream : Hex("3C513F"); Stretch(label.rectTransform, 9, 0, -9, 0);
                var size = badge.gameObject.AddComponent<LayoutElement>();
                size.minWidth = size.preferredWidth = Mathf.Min(maxWidth, label.preferredWidth + 22);
                size.minHeight = size.preferredHeight = 32;
            }
        }
    }
}
