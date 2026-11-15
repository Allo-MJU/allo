using System;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        string _facility = "workshop", _recipe, _lesson;

        void BuildHome() { BuildVillageMap(0, true); }

        void BuildCabin()
        {
            if (!_state.connected) return;
            if (StoryOverlay.OwnsInput(_state) && !StoryUiBlocked) return;
            BuildNotebookEntry();
            var buddy = HasSelectedCompanion(_state);
            var egg = _state.egg;
            if (buddy) BuildCompanionLearning();
            if (egg != null && egg.active)
            {
                BuildEggHud(egg);
                BuildEggDrawers(egg);
            }
            if (!HasCabinActionTarget(_state) || StoryUiBlocked) return;
            BuildCabinItemRail();
            var hint = Label(_content, "", 18, TextAnchor.MiddleCenter);
            hint.color = Cream;
            Stretch(hint.rectTransform, -340, 0, 340, 28, new Vector2(.5f, 0), new Vector2(.5f, 0));
            var shadow = hint.gameObject.AddComponent<Shadow>(); shadow.effectColor = new Color(0, 0, 0, .7f); shadow.effectDistance = new Vector2(0, -1);
            _liveChecks.Add(() =>
            {
                if (hint != null) hint.text = !string.IsNullOrEmpty(CabinInteraction.SelectedItem) ? "원하는 방향으로 밀어 던지기" :
                    CabinInteraction.MoveArmed ? "친구를 원하는 자리에 놓아 주세요" :
                    buddy ? "친구를 두 번 누르고 원하는 자리로 끌어 보세요" : "알을 부드럽게 문질러 주세요";
            });
        }

        void BuildNotebookEntry()
        {
            if (_state.story == null || StoryUiBlocked) return;
            var entry = Button(_content, "탐험 노트", () =>
            {
                if (!CanOpenNotebook) return;
                CloseCompanionInvitation();
                _storyOverlay.ToggleNotebook();
            }, Cream, 58, CanOpenNotebook, 22);
            Stretch((RectTransform)entry.transform, -180, 8, 0, 66, new Vector2(1, 0), new Vector2(1, 0));
            _liveChecks.Add(() => { if (entry != null) entry.interactable = CanOpenNotebook; });
        }

        bool CanOpenNotebook => CanAct && _state.connected && !_state.sessionEnded &&
            _state.story?.canOpen == true && !_nativeSpeechHidden && (!_nativeSpeechExpected || Time.realtimeSinceStartup > _nativeSpeechDeadline) &&
            _state.learning?.busy != true && _state.learning?.recording != true &&
            _state.egg?.photoRequired != true && _state.egg?.photoBusy != true && _state.egg?.speechBusy != true && !StoryUiBlocked;

        void BuildCabinItemRail()
        {
            var rail = Rect("Cabin item circles", _content);
            rail.anchorMin = rail.anchorMax = Vector2.zero;
            rail.pivot = Vector2.zero; rail.sizeDelta = new Vector2(196, 278);
            var ids = new[] { "snack", "water", "ball", "plush" };
            var names = new[] { "간식", "물", "공", "인형" };
            var positions = new[] { new Vector2(56, 222), new Vector2(140, 168), new Vector2(56, 110), new Vector2(140, 56) };
            for (var i = 0; i < ids.Length; i++)
            {
                var id = ids[i];
                var button = Button(rail, names[i], () =>
                {
                    if (CabinGesturesBlocked || !CanCommonCare(_state, id)) return;
                    CloseCompanionInvitation();
                    CabinInteraction.SelectItem(id);
                    _dirty = true;
                }, Color.white, 76, true, 18);
                var rect = (RectTransform)button.transform;
                rect.anchorMin = rect.anchorMax = Vector2.zero;
                rect.anchoredPosition = positions[i]; rect.sizeDelta = new Vector2(76, 76);
                var surface = button.GetComponent<Image>(); surface.sprite = CabinItemDisc(); surface.type = Image.Type.Simple;
                var ring = button.GetComponent<Outline>(); ring.effectColor = Yellow; ring.effectDistance = new Vector2(2, -2); ring.enabled = false;
                var text = button.GetComponentInChildren<Text>(); text.color = Cream;
                Stretch(text.rectTransform, -10, -26, 10, -3, Vector2.zero, new Vector2(1, 0));
                var textShadow = text.gameObject.AddComponent<Shadow>(); textShadow.effectColor = new Color(0, 0, 0, .75f); textShadow.effectDistance = new Vector2(0, -1);
                var art = Rect("Item artwork", rect);
                art.anchorMin = art.anchorMax = new Vector2(.5f, .5f); art.sizeDelta = new Vector2(54, 54);
                var image = art.gameObject.AddComponent<Image>(); image.sprite = CabinItemArtwork(id); image.raycastTarget = false;
                _liveChecks.Add(() =>
                {
                    if (button == null) return;
                    var enabled = CanCommonCare(_state, id) && !CabinGesturesBlocked;
                    button.interactable = enabled;
                    surface.color = enabled ? Color.white : new Color(.72f, .72f, .65f, .75f);
                    ring.enabled = enabled && CabinInteraction.SelectedItem == id;
                    rect.localScale = ring.enabled ? Vector3.one * 1.08f : Vector3.one;
                });
            }
        }

        void BuildEggHud(EggState egg)
        {
            var hud = Surface("Cabin affinity HUD", _content, new Color(.949f, .933f, .898f, .90f));
            Stretch(hud, 12, -112, 414, -10, new Vector2(0, 1), new Vector2(0, 1));
            var score = Label(hud, "친밀도  " + Mathf.FloorToInt(egg.score) + " / 100", 23, TextAnchor.MiddleLeft); Stretch(score.rectTransform, 14, -38, -14, -6, new Vector2(0, 1), Vector2.one);
            var track = Surface("Affinity track", hud, Disabled, false); Stretch(track, 14, 41, -14, 49, Vector2.zero, new Vector2(1, 0));
            var fill = Surface("Confirmed affinity", track, Hex("53765B"), false); Stretch(fill, 0, 0, 0, 0, Vector2.zero, new Vector2(Mathf.Clamp01(egg.score / 100), 1));
            var hint = Label(hud, egg.photoRequired ? "함께 사진을 찍으면 다시 가까워져요" : !string.IsNullOrEmpty(egg.remainingLabel) ? egg.remainingLabel : "알을 부드럽게 문질러 주세요", 19, TextAnchor.MiddleLeft); Stretch(hint.rectTransform, 14, 6, -14, 37, Vector2.zero, new Vector2(1, 0));
            var tools = Rect("Egg care tools", _content);
            Stretch(tools, 12, -155, 414, -120, new Vector2(0, 1), new Vector2(0, 1)); Row(tools, 6);
            var eggId = egg.id;
            Button(tools, "말 걸기", () => Send("speech", new AppAction { eggId = eggId }), Cream, 35,
                CanAct && _state.speechAvailable && !egg.photoRequired && !egg.speechBusy && egg.speechCooldown <= 0, 17);
            Button(tools, "글로 말하기", () => OpenEggDrawer(true), Cream, 35, CanAct, 17);
            Button(tools, "자리와 돌보기", () => OpenEggDrawer(false), Cream, 35, CanAct, 17);
            var feedback = EggFeedbackLabel(egg.feedback);
            if (egg.photoRequired)
            {
                var photos = Rect("Photo quest tools", _content);
                Stretch(photos, 12, -201, 414, -163, new Vector2(0, 1), new Vector2(0, 1)); Row(photos, 6);
                Button(photos, egg.photoBusy ? "사진 보내는 중" : "함께 사진 찍기", () => Send("photo", new AppAction { eggId = eggId }), Yellow, 38,
                    CanAct && _state.photoAvailable && !egg.photoBusy, 18);
                Button(photos, "보류한 사진 확인", () => Send("recoverPhoto", new AppAction { eggId = eggId }), Cream, 38, CanAct && !egg.photoBusy, 17);
            }
            else if (!string.IsNullOrEmpty(feedback))
            {
                var bubble = Surface("Egg feedback", _content, Cream, false); Stretch(bubble, 12, -198, 414, -163, new Vector2(0, 1), new Vector2(0, 1));
                var text = Label(bubble, feedback, 18, TextAnchor.MiddleCenter); Stretch(text.rectTransform, 8, 0, -8, 0);
            }
        }

        void OpenEggDrawer(bool speech)
        {
            if (StoryOverlay.OwnsInput(_state)) return;
            CloseCompanionInvitation();
            _speechDrawer = speech; _zoneDrawer = !speech; _dirty = true;
        }

        void BuildEggDrawers(EggState egg)
        {
            var openedEggId = egg.id;
            if (_zoneDrawer)
            {
                var zones = DockSheet(260);
                Button(zones, "자리 메뉴 닫기", () => { _zoneDrawer = false; _dirty = true; }, Cream, 44, true, 20);
                string[] names = { "대시보드", "왼쪽 창턱", "오른쪽 창턱", "앞 바닥" };
                for (var i = 0; i < names.Length; i++)
                {
                    var zone = i;
                    Button(zones, (egg.zone == i ? "현재 · " : "") + names[i], () => Send("placeEgg", new AppAction { zone = zone }), egg.zone == i ? Mint : Cream, 46, CanAct && !egg.photoRequired && egg.moveCooldown <= 0 && egg.zone != i, 20);
                }
                if (egg.preferredZone >= 0 && egg.preferredZone < names.Length) Note(zones, "좋아하는 자리 · " + names[egg.preferredZone]);
                if (egg.moveCooldown > 0) Note(zones, egg.moveCooldown + "초 뒤에 옮길 수 있어요.");
                Note(zones, "알을 끌거나 차 안의 자리를 눌러 옮길 수도 있어요.");
                Button(zones, "돌보기 그만두기", () => ConfirmIntent("이 알 돌보기를 그만둘까요?", "현재 알의 돌보기가 종료돼요. 이미 만난 친구는 그대로예요.", "discardEgg", new AppAction { eggId = openedEggId }), Cream, 46, CanAct && !egg.photoBusy && !egg.speechBusy, 19);
            }
            if (_speechDrawer)
            {
                var drawer = DockSheet(390);
                Button(drawer, "대화 닫기", () => { _speechDrawer = false; _dirty = true; }, Cream, 46, true, 20);
                Heading(drawer, "알에게 해 줄 말");
                if (!_state.speechAvailable) Note(drawer, "지금은 대화를 연결할 수 없어요. 잠시 후 다시 시도해 주세요.");
                Field(drawer, _speech, "따뜻한 말을 적어 주세요", text => _speech = text, 240);
                LiveEnable(Button(drawer, "적은 말 전하기", () => { Send("submitSpeech", new AppAction { text = _speech.Trim() }); _speech = ""; }, Yellow, 54, false, 22), () => CanAct && _state.speechAvailable && _state.egg != null && !_state.egg.photoRequired && !_state.egg.speechBusy && _state.egg.speechCooldown <= 0 && !string.IsNullOrWhiteSpace(_speech), Yellow);
            }
        }

        static bool HasCabinActionTarget(AppState state) => state != null && state.ready && state.connected &&
            state.view == "cabin" && !state.sessionEnded &&
            (HasSelectedCompanion(state) || (state.egg != null && state.egg.active && !string.IsNullOrEmpty(state.egg.id)));

        void BuildCamp()
        {
            BuildVillageMap(0, false);
            if (!_campDetail) return;
            var panel = DockSheet(430);
            var facility = Items(_state.facilities).FirstOrDefault(f => f.id == _facility);
            var header = NewRow(panel, 46);
            Button(header, (facility?.label ?? "시설") + " · 지도로 돌아가기", () => { _campDetail = false; _dirty = true; }, Cream, 46, true, 20);
            var tabs = NewRow(panel, 44);
            foreach (var role in new[] { "builder", "cook", "trainer" })
            {
                var selected = role;
                Button(tabs, RoleLabel(role), () => { _campTab = selected; if (selected == "cook") _facility = "kitchen"; else if (selected == "trainer") _facility = "training"; _dirty = true; }, _campTab == role ? Mint : Cream, 44, CanAct, 19);
            }
            var running = Job(_campTab);
            var assigned = Assignment(_campTab);
            var eligible = Items(_state.creatures).Where(c => c.role == _campTab).ToArray();
            if (!_workers.TryGetValue(_campTab, out var picked) || !eligible.Any(c => c.id == picked)) picked = assigned;
            if (string.IsNullOrEmpty(picked) && eligible.Length > 0) picked = eligible[0].id;
            _workers[_campTab] = picked;
            if (running != null)
            {
                var cancelRole = running.role;
                Progress(panel, running.progress, running.label + " · " + TimeLabel(running.remainingSec));
                Note(panel, CreatureName(running.workerId) + "와 함께하고 있어요. 앱을 닫아도 작업이 계속 진행돼요.");
                Button(panel, "이 작업 취소하기", () => ConfirmIntent("진행 중인 작업을 취소할까요?", "취소하면 사용한 재료가 돌아와요.", "cancel", new AppAction { role = cancelRole }), Cream, 54, CanAct, 22);
                return;
            }
            if (eligible.Length == 0) Note(panel, "아직 " + RoleLabel(_campTab) + " 친구가 없어요. 알에서 해당 역할의 친구를 만나면 함께할 수 있어요.");
            else
            {
                Note(panel, "현재 담당 · " + (string.IsNullOrEmpty(assigned) ? "아직 없어요" : CreatureName(assigned)));
                var workers = NewRow(panel, 44);
                Button(workers, CreatureName(picked), null, Mint, 44, false, 21);
                if (eligible.Length > 1) Button(workers, "다른 친구", () => { var index = Array.FindIndex(eligible, c => c.id == picked); _workers[_campTab] = eligible[(index + 1) % eligible.Length].id; _dirty = true; }, Cream, 44, CanAct, 19);
                Button(panel, picked == assigned ? "담당 쉬게 하기" : "이 친구를 담당으로", () => Send("assign", new AppAction { role = _campTab, creatureId = picked == assigned ? "" : picked }), Cream, 44, CanAct && !CreatureBusy(picked), 20);
            }
            if (_campTab == "builder") BuildConstruction(panel);
            else
            {
                var selectedFacility = _campTab == "cook" ? "kitchen" : "training";
                var ownFacility = Items(_state.facilities).FirstOrDefault(f => f.id == selectedFacility);
                if (ownFacility != null && ownFacility.level < 3) Button(panel, ownFacility.level == 0 ? "이 시설 짓기" : "시설 레벨 올리기", () => { _facility = selectedFacility; _campTab = "builder"; _dirty = true; }, Cream, 46, CanAct, 19);
                if (_campTab == "cook") BuildCooking(panel); else BuildTraining(panel);
            }
        }

        void BuildConstruction(Transform panel)
        {
            var facilities = Items(_state.facilities);
            if (!facilities.Any(f => f.id == _facility)) _facility = facilities.FirstOrDefault()?.id;
            var selected = facilities.FirstOrDefault(f => f.id == _facility);
            if (selected == null) { Copy(panel, "시설 정보를 아직 받지 못했어요."); return; }
            Space(panel); Copy(panel, selected.label + (selected.level >= 3 ? " · 최고 레벨" : " → Lv." + (selected.level + 1)), 28);
            var cost = Cost(selected.woodCost, selected.stoneCost, 0);
            Copy(panel, "필요 재료  " + cost);
            var reason = selected.level >= 3 ? "이미 최고 레벨이에요." : selected.id != "workshop" && !Items(_state.facilities).Any(f => f.id == "workshop" && f.level >= 1) ? "먼저 작업장을 Lv.1로 지어 주세요." : WorkReason("builder", selected.woodCost, selected.stoneCost, 0);
            if (reason == null && !selected.canUpgrade) reason = "지금은 이 시설을 건설할 수 없어요. 상태를 다시 확인해 주세요.";
            if (reason != null) Note(panel, reason);
            Button(panel, selected.level == 0 ? "이 시설 짓기" : "이 시설 업그레이드", () => Confirm(selected.label + " 작업을 시작할까요?", cost + "를 사용해요. 담당 친구가 작업을 시작하면 다른 친구의 역할은 계속 진행할 수 있어요.", () => Send("build", new AppAction { facility = selected.id })), Yellow, 72, CanAct && reason == null);
        }

        void BuildCooking(Transform panel)
        {
            var foods = Items(_state.foods);
            if (!foods.Any(f => f.id == _recipe)) _recipe = foods.FirstOrDefault()?.id;
            var recipes = NewRow(panel, 48);
            foreach (var food in foods)
            {
                var choice = food;
                Button(recipes, food.label, () => { _recipe = choice.id; _dirty = true; }, _recipe == food.id ? Mint : Cream, 48, CanAct, 18);
            }
            var selected = foods.FirstOrDefault(f => f.id == _recipe);
            if (selected == null) { Note(panel, "아직 요리 정보가 없어요."); return; }
            Note(panel, "보유 " + selected.count + "개 · 주방 Lv." + selected.requiredLevel);
            Copy(panel, "필요 재료  " + Cost(0, 0, selected.costIngredient), 22);
            var reason = !selected.unlocked ? "주방 Lv." + selected.requiredLevel + "에서 열려요." : WorkReason("cook", 0, 0, selected.costIngredient);
            if (reason != null) Note(panel, reason);
            Button(panel, "이 요리 만들기", () => Confirm(selected.label + " 요리를 시작할까요?", Cost(0, 0, selected.costIngredient) + "를 사용해요. 완성한 요리는 보급품에 모여요.", () => Send("cook", new AppAction { recipeId = selected.id })), Yellow, 54, CanAct && reason == null, 22);
        }

        void BuildTraining(Transform panel)
        {
            var training = Items(_state.training);
            if (!training.Any(t => t.id == _lesson)) _lesson = training.FirstOrDefault()?.id;
            var tabs = NewRow(panel, 48);
            foreach (var lesson in training)
            {
                var choice = lesson;
                Button(tabs, lesson.label, () => { _lesson = choice.id; _dirty = true; }, _lesson == lesson.id ? Mint : Cream, 48, CanAct, 19);
            }
            var selected = training.FirstOrDefault(t => t.id == _lesson);
            if (selected == null) { Note(panel, "아직 훈련 정보가 없어요."); return; }
            var trainer = Assignment("trainer");
            var targets = Items(_state.creatures).Where(c => c.id != trainer).ToArray();
            if (!targets.Any(c => c.id == _selectedTarget)) _selectedTarget = targets.FirstOrDefault(c => !CreatureBusy(c.id))?.id;
            Copy(panel, "배울 친구", 21);
            if (targets.Length > 0)
            {
                var row = NewRow(panel, 44);
                Button(row, CreatureName(_selectedTarget), null, Mint, 44, false, 20);
                if (targets.Length > 1) Button(row, "다른 친구", () => { var index = Array.FindIndex(targets, c => c.id == _selectedTarget); _selectedTarget = targets[(index + 1) % targets.Length].id; _dirty = true; }, Cream, 44, CanAct, 19);
            }
            else Note(panel, "훈련가와 다른 친구가 한 명 더 필요해요.");
            var cost = Cost(selected.woodCost, selected.stoneCost, selected.ingredientCost);
            Copy(panel, "필요 재료  " + cost, 22);
            var target = targets.FirstOrDefault(c => c.id == _selectedTarget);
            var reason = !selected.unlocked ? "훈련장 Lv." + selected.requiredLevel + "에서 열려요." : WorkReason("trainer", selected.woodCost, selected.stoneCost, selected.ingredientCost);
            if (reason == null && target == null) reason = "배울 친구를 골라 주세요.";
            if (reason == null && CreatureBusy(target.id)) reason = "이 친구는 다른 작업을 하고 있어요.";
            if (reason == null && Items(target.actions).Contains(selected.id)) reason = "이 친구는 이미 이 행동을 배웠어요.";
            if (reason != null) Note(panel, reason);
            Button(panel, "이 친구와 훈련하기", () => ConfirmIntent(selected.label + " 훈련을 시작할까요?", CreatureName(_selectedTarget) + "와 훈련하며 " + cost + "를 사용해요.", "train", new AppAction { actionId = selected.id, targetId = _selectedTarget }), Yellow, 54, CanAct && reason == null, 22);
        }

        void BuildDex()
        {
            var entries = Items(_state.dex);
            if (!entries.Any(d => d.id == _selectedDex)) _selectedDex = entries.FirstOrDefault(d => d.collected)?.id ?? entries.FirstOrDefault()?.id;
            var detail = entries.FirstOrDefault(d => d.id == _selectedDex);
            CollectionBook(detail == null ? "우리 친구 도감" : detail.collected ? detail.name : "아직 만나지 못한 친구",
                "만난 친구 " + entries.Count(d => d.collected) + " / " + entries.Length, out var left, out var right);
            if (detail == null)
            {
                BookCopy(left, "도감 정보를 불러오는 중이에요. 설정에서 다시 확인할 수 있어요.");
                BookCopy(right, "여행에서 만난 친구들이 이곳에 모여요.", 22, true); return;
            }
            var grid = BookGrid(right, "Dex grid", entries.Length, out var cellSize);
            foreach (var entry in entries)
            {
                var selected = entry;
                var portrait = BookSlot(grid, entry.name, entry.collected ? entry.name : "???", _selectedDex == entry.id,
                    () => { _selectedDex = selected.id; _selectedCreature = null; _dirty = true; });
                if (entry.collected) BookPortrait(portrait, entry.sprite, entry.id, cellSize, true);
                else
                {
                    var mystery = Label(portrait, "?", 48, TextAnchor.MiddleCenter); mystery.color = BookMuted; Stretch(mystery.rectTransform);
                }
            }
            if (!detail.collected)
            {
                var mystery = Copy(left, "?", 84); mystery.alignment = TextAnchor.MiddleCenter; mystery.color = BookMuted;
                BookCopy(left, "아직 이 친구를 만나지 못했어요.", 23);
                BookCopy(left, string.IsNullOrEmpty(detail.description) ? "여행하며 알을 키워 보세요. 이 친구를 만나면 이야기와 모습이 도감에 남아요." : detail.description);
                BookButton(left, "차 안에서 알 키우기", () => Navigate("cabin"), true, CanAct); return;
            }
            BookPortrait(left, detail.sprite, detail.id, 170);
            BookCopy(left, BookAttributeLabel(detail.attribute) + " · " + RoleLabel(detail.role), 22, true);
            BookCopy(left, detail.description);
            BookCopy(left, "함께한 친구 " + detail.count + "마리", 19, true);
            var owned = Items(_state.creatures).Where(c => c.speciesId == detail.id).ToArray();
            if (owned.Length == 0) { BookCopy(left, "도감에는 기록되어 있지만 지금 함께하는 개체 정보는 없어요.", 21, true); return; }
            if (!owned.Any(c => c.id == _selectedCreature)) _selectedCreature = owned[0].id;
            if (owned.Length > 1) foreach (var creature in owned)
            {
                var selected = creature;
                BookButton(left, creature.name + " · " + ShortId(creature.id), () => { _selectedCreature = selected.id; _dirty = true; }, _selectedCreature == creature.id, CanAct);
            }
            var friend = owned.First(c => c.id == _selectedCreature);
            var companionId = friend.id;
            BookButton(left, "차 안으로 데리고 오기", () =>
            {
                if (_state.connected && !_state.sessionEnded) Send("selectCarCompanion", new AppAction { creatureId = companionId });
            }, true, CanAct && _state.connected && !_state.sessionEnded);
            if (_state.sessionEnded) BookCopy(left, "여행이 끝났어요. 차량과 다시 연결한 뒤 친구를 선택해 주세요.", 19, true);
            else if (!_state.connected) BookCopy(left, "차량과 연결한 뒤 함께할 친구를 선택할 수 있어요.", 19, true);
            BookCopy(left, "차량 친구의 관찰 기록 " + _state.fishingRecords + "건", 21);
            if (!string.IsNullOrEmpty(_state.fishingError))
            {
                BookCopy(left, _state.fishingError, 19, true);
                BookButton(left, "낚시 저장 다시 확인", () => Send("retryFishingSave"), false, CanAct);
            }
            CreatureActions(left, friend);
            Space(left); BookCopy(left, "친구에게 요리 주기", 26);
            FeedOptions(left, friend.id);
        }

        void CreatureActions(Transform parent, CreatureState creature)
        {
            Copy(parent, creature.name + "의 배운 행동", 27);
            var actions = Items(creature.actions);
            if (actions.Length == 0) Note(parent, "아직 배운 행동이 없어요. 캠프 훈련장에서 새 행동을 배울 수 있어요.");
            foreach (var action in actions)
            {
                var selected = action;
                Button(parent, ActionLabel(action) + " 보여 주기", () => Send("performAction", new AppAction { creatureId = creature.id, actionId = selected }), Mint, 64, CanAct && !CreatureBusy(creature.id), 24);
            }
            if (CreatureBusy(creature.id)) Note(parent, "작업 중인 친구예요. 일이 끝나면 배운 행동을 보여 줄 수 있어요.");
            if (creature.foodBoostUntilMs > DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()) Note(parent, "든든한 요리의 힘을 받고 있어요.");
        }

        void BuildInventory()
        {
            var foodsTab = _supplyTab == "foods";
            var materials = Items(_state.materials);
            var foods = Items(_state.foods);
            if (foodsTab && !foods.Any(f => f.id == _selectedSupply)) _selectedSupply = foods.FirstOrDefault(f => f.count > 0)?.id ?? foods.FirstOrDefault()?.id;
            if (!foodsTab && !materials.Any(m => m.id == _selectedSupply)) _selectedSupply = materials.FirstOrDefault()?.id;
            var food = foodsTab ? foods.FirstOrDefault(f => f.id == _selectedSupply) : null;
            var material = foodsTab ? null : materials.FirstOrDefault(m => m.id == _selectedSupply);
            CollectionBook(food?.label ?? material?.label ?? "여행 가방", "여행에서 모은 보급품", out var left, out var right);
            var tabs = NewRow(right, 48);
            BookButton(tabs, "재료", () => { _supplyTab = "materials"; _selectedSupply = null; _dirty = true; }, !foodsTab);
            BookButton(tabs, "요리", () => { _supplyTab = "foods"; _selectedSupply = null; _dirty = true; }, foodsTab);
            var grid = BookGrid(right, "Supply grid", foodsTab ? foods.Length : materials.Length, out var cellSize);
            if (foodsTab) foreach (var entry in foods)
            {
                var selected = entry;
                var art = BookSlot(grid, "Supply slot " + entry.id, entry.label, entry.id == _selectedSupply,
                    () => { _selectedSupply = selected.id; _dirty = true; }, entry.count + "개");
                BookItemArt(art, entry.id, cellSize);
            }
            else foreach (var entry in materials)
            {
                var selected = entry;
                var art = BookSlot(grid, "Supply slot " + entry.id, entry.label, entry.id == _selectedSupply,
                    () => { _selectedSupply = selected.id; _dirty = true; }, entry.count + "개");
                BookItemArt(art, entry.id, cellSize);
            }
            if (food == null && material == null)
            {
                BookCopy(left, foodsTab ? "완성한 요리가 없어요. 캠프 주방에서 재료로 요리를 만들어 주세요." : "아직 모은 재료가 없어요. 여행하며 창밖을 관찰해 보세요.");
            }
            else
            {
                BookItemArt(left, food?.id ?? material.id, 166);
                BookCopy(left, "보유 수량  " + (food?.count ?? material.count) + "개", 27);
                if (!foodsTab)
                {
                    BookCopy(left, MaterialUse(material.id));
                    BookCopy(left, "주행과 창밖 관찰로 모은 재료예요.", 20, true);
                }
                else
                {
                    BookCopy(left, "친구에게 주면 요리의 힘을 보태요.", 22);
                    var creatures = Items(_state.creatures);
                    if (!creatures.Any(c => c.id == _selectedCreature)) _selectedCreature = creatures.FirstOrDefault()?.id;
                    if (creatures.Length == 0) BookCopy(left, "함께하는 친구가 생기면 요리를 줄 수 있어요.", 21, true);
                    else
                    {
                        BookCopy(left, "요리 받을 친구 · " + CreatureName(_selectedCreature), 22);
                        if (creatures.Length > 1) BookButton(left, "다른 친구 고르기", () =>
                        {
                            var index = Array.FindIndex(creatures, c => c.id == _selectedCreature);
                            _selectedCreature = creatures[(index + 1) % creatures.Length].id; _dirty = true;
                        }, false, CanAct);
                    }
                    var recipient = _selectedCreature;
                    var selectedFood = food;
                    BookButton(left, "요리 1개 주기", () => ConfirmIntent(CreatureName(recipient) + "에게 요리를 줄까요?",
                        selectedFood.label + " 1개를 사용해 친구에게 힘을 보태요.", "feedFood",
                        new AppAction { recipeId = selectedFood.id, creatureId = recipient }), true, CanAct && food.count > 0 && !string.IsNullOrEmpty(recipient));
                    if (food.count <= 0) BookCopy(left, food.unlocked ? "보유한 요리가 없어요. 주방에서 만들 수 있어요." :
                        "주방 Lv." + food.requiredLevel + "에서 만들 수 있어요.", 19, true);
                }
            }
            Space(left);
            BookButton(left, "주방에서 요리하기", () => OpenVillageFacility("kitchen"), false, CanAct);
            BookCopy(right, foodsTab ? "요리를 골라 왼쪽에서 친구에게 주세요." : "재료를 골라 어디에 쓰는지 살펴보세요.", 19, true);
        }

        void FeedOptions(Transform parent, string creatureId)
        {
            var foods = Items(_state.foods);
            if (foods.Length == 0 || !foods.Any(f => f.count > 0)) Note(parent, "완성한 요리가 없어요. 캠프 주방에서 재료로 요리를 만들어 주세요.");
            foreach (var food in foods)
            {
                var selected = food;
                Button(parent, food.label + "  " + food.count + "개 · 1개 주기", () => Confirm(CreatureName(creatureId) + "에게 요리를 줄까요?", selected.label + " 1개를 사용해 친구에게 힘을 보태요.", () => Send("feedFood", new AppAction { recipeId = selected.id, creatureId = creatureId })), Cream, 64, CanAct && food.count > 0, 24);
            }
        }

        void BuildPairing()
        {
            var panel = DockSheet(520);
            BuildPairingForm(panel);
            Button(panel, "차 안으로 돌아가기", () => Navigate("cabin"), Cream, 54, CanAct, 22);
        }

        void BuildPairingForm(Transform panel)
        {
            Heading(panel, _state.connected ? "차량과 연결되어 있어요" : "차량과 함께 시작해요");
            Copy(panel, _state.sessionEnded ? "이전 여행이 끝났어요. 차량에서 새로운 연결 정보를 확인해 주세요." : "차량 QR을 스캔하거나 세션 ID와 코드를 입력해 주세요.");
            if (_state.isDemo)
            {
                Button(panel, "테스트 연결", () => Send("testPair"), Mint, 54, CanAct, 23);
                Note(panel, "실제 차량 없이 가상 주행으로 연결해요.");
            }
            Button(panel, "차량 QR 스캔", () => Send("scanPairingQr"), Yellow, 60, CanAct && _state.pairingScanAvailable, 23);
            if (!_state.pairingScanAvailable) Note(panel, "지금은 QR 스캔을 사용할 수 없어요. 아래에 직접 입력해 주세요.");
            Copy(panel, "세션 ID", 24); Field(panel, _sessionId, "차량에 표시된 세션 ID", text => _sessionId = text, 160);
            Copy(panel, "페어링 코드", 24); Field(panel, _pairCode, "차량에 표시된 코드", text => _pairCode = text, 32);
            LiveEnable(Button(panel, "차량과 연결하기", () => Send("pair", new AppAction { sessionId = _sessionId.Trim(), pairCode = _pairCode.Trim() }), Yellow, 60, false, 23), () => CanAct && !string.IsNullOrWhiteSpace(_sessionId) && !string.IsNullOrWhiteSpace(_pairCode), Yellow);
        }

        void BuildSettings()
        {
            var left = Sheet(_content, 0, .53f);
            var right = Sheet(_content, .53f, 1);
            BuildPairingForm(left);
            if (_state.connected) Button(left, "차량 연결 끊기", () => Confirm("차량 연결을 끊을까요?", "차량에서 오는 정보를 더 이상 받지 않아요. 함께한 친구와 보급품은 그대로예요.", () => Send("disconnect")), Cream, 66, CanAct);
            Heading(right, "편안하게 즐기기");
            Button(right, "기울여 둘러보기  ·  " + (_state.gyro ? "켜짐" : "꺼짐"), () => Send("settings", new AppAction { gyro = !_state.gyro, reducedMotion = _state.reducedMotion }), _state.gyro ? Mint : Cream, 72, CanAct, 25);
            Note(right, "기기의 움직임으로 차 안을 둘러봐요.");
            Button(right, "움직임 줄이기  ·  " + (_state.reducedMotion ? "켜짐" : "꺼짐"), () => Send("settings", new AppAction { gyro = _state.gyro, reducedMotion = !_state.reducedMotion }), _state.reducedMotion ? Mint : Cream, 72, CanAct, 25);
            Note(right, "자동으로 흔들리거나 움직이는 연출을 줄여요.");
            Space(right); Button(right, "다시 확인하기", () => Send("refresh"), Cream, 66, CanAct);
            if (_state.isDemo && _state.connected && !_state.sessionEnded) Button(right, "체험 여행 끝내기", () => Confirm("체험 여행을 끝낼까요?", "현재 체험 주행이 종료돼요. 다음 여행은 새로운 연결로 시작해 주세요.", () => Send("endTrip")), Cream, 66, CanAct);
        }

        string Assignment(string role) => Items(_state.assignments).FirstOrDefault(a => a.role == role)?.creatureId;
        JobState Job(string role) => Items(_state.jobs).FirstOrDefault(j => j.role == role);
        bool CreatureBusy(string id) => Items(_state.jobs).Any(j => j.workerId == id || j.targetId == id);
        string CreatureName(string id) => Items(_state.creatures).FirstOrDefault(c => c.id == id)?.name ?? "친구";
        int Balance(string id) => Items(_state.materials).FirstOrDefault(m => m.id == id)?.count ?? 0;
        string WorkReason(string role, int wood, int stone, int ingredient)
        {
            if (Job(role) != null) return "이 역할은 이미 작업 중이에요.";
            var assignment = Assignment(role);
            if (string.IsNullOrEmpty(assignment)) return "왼쪽에서 " + RoleLabel(role) + " 친구를 담당으로 정해 주세요.";
            if (CreatureBusy(assignment)) return "담당 친구가 다른 작업을 하고 있어요.";
            if (Balance("wood") < wood || Balance("stone") < stone || Balance("ingredient") < ingredient) return "재료가 부족해요. 왼쪽 보유량과 필요한 재료를 확인해 주세요.";
            return null;
        }
        static string RoleLabel(string role) => role == "builder" ? "건설가" : role == "cook" ? "요리사" : role == "trainer" ? "훈련가" : "역할 미정";
        static string AttributeLabel(string value) => value == "earth" ? "땅" : value == "water" ? "물" : value == "light" ? "빛" : value;
        static string ActionLabel(string value) => value == "greeting" ? "인사" : value == "cheer" ? "응원" : value == "look_around" ? "둘러보기" : value;
        static string ShortId(string id) => string.IsNullOrEmpty(id) ? "" : id.Substring(Math.Max(0, id.Length - 5));
        static string CooldownLabel(string text, int seconds) => seconds > 0 ? text + " · " + seconds + "초 뒤" : text;
        static string TimeLabel(int seconds) => seconds <= 0 ? "완료 확인 중" : seconds >= 60 ? (seconds / 60) + "분 " + (seconds % 60) + "초 남음" : seconds + "초 남음";
        static string Cost(int wood, int stone, int ingredient)
        {
            var parts = new System.Collections.Generic.List<string>();
            if (wood > 0) parts.Add("목재 " + wood); if (stone > 0) parts.Add("돌 " + stone); if (ingredient > 0) parts.Add("식재료 " + ingredient);
            return parts.Count == 0 ? "없음" : string.Join(" · ", parts);
        }
        static string EggFeedbackLabel(string feedback)
        {
            switch (feedback)
            {
                case "none": return "";
                case "positive": return "알이 기뻐하고 있어요.";
                case "negative": return "알이 조금 속상해해요.";
                case "neutral": return "...";
                case "vibration": return "알이 흔들림을 느꼈어요. 부드럽게 움직여 주세요.";
                case "photoRequired": return "함께 사진을 찍어 주세요.";
                case "hatched": return "새 친구가 깨어났어요!";
                case "fled": return "알이 떠났어요. 새로운 알과 다시 시작할 수 있어요.";
                default: return "";
            }
        }
        static string RewardLabel(string status) => status == "pendingPleos" || string.IsNullOrEmpty(status) ? "Pleos 활동 보상 연결 준비 중" : status;
    }
}
