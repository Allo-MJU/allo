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
            var egg = _state.egg;
            var openedEggId = egg?.id;
            if (egg == null || !egg.active) { BuildCabinStart(egg); return; }
            var hud = Surface("Cabin affinity HUD", _content, new Color(.949f, .933f, .898f, .90f));
            Stretch(hud, 12, -112, 414, -10, new Vector2(0, 1), new Vector2(0, 1));
            var score = Label(hud, "친밀도  " + Mathf.FloorToInt(egg.score) + " / 100", 23, TextAnchor.MiddleLeft); Stretch(score.rectTransform, 14, -38, -14, -6, new Vector2(0, 1), Vector2.one);
            var track = Surface("Affinity track", hud, Disabled, false); Stretch(track, 14, 41, -14, 49, Vector2.zero, new Vector2(1, 0));
            var fill = Surface("Confirmed affinity", track, Hex("53765B"), false); Stretch(fill, 0, 0, 0, 0, Vector2.zero, new Vector2(Mathf.Clamp01(egg.score / 100), 1));
            var hint = Label(hud, egg.photoRequired ? "함께 사진을 찍으면 다시 가까워져요" : !string.IsNullOrEmpty(egg.remainingLabel) ? egg.remainingLabel : "알을 부드럽게 문질러 주세요", 19, TextAnchor.MiddleLeft); Stretch(hint.rectTransform, 14, 6, -14, 37, Vector2.zero, new Vector2(1, 0));
            var feedback = EggFeedbackLabel(egg.feedback);
            if (!string.IsNullOrEmpty(feedback))
            {
                var bubble = Surface("Egg feedback", _content, Cream, false); Stretch(bubble, 12, -157, 414, -120, new Vector2(0, 1), new Vector2(0, 1));
                var text = Label(bubble, feedback, 19, TextAnchor.MiddleCenter); Stretch(text.rectTransform, 8, 0, -8, 0);
            }
            var dock = Surface("Cabin action dock", _content, new Color(.949f, .933f, .898f, .96f));
            Stretch(dock, -430, 10, 430, 84, new Vector2(.5f, 0), new Vector2(.5f, 0));
            var actions = Rect("Cabin actions", dock); Stretch(actions, 9, 9, -9, -9); Row(actions, 8);
            Button(actions, CooldownLabel("쓰다듬기", egg.petCooldown), () => Send("petEgg"), egg.photoRequired ? Cream : Yellow, 54, CanAct && !egg.photoRequired && egg.petCooldown <= 0, 21);
            Button(actions, egg.speechBusy ? "듣고 있어요" : CooldownLabel("말 걸기", egg.speechCooldown), () => Send("speech"), Cream, 54, CanAct && _state.speechAvailable && !egg.photoRequired && !egg.speechBusy && egg.speechCooldown <= 0, 21);
            Button(actions, egg.photoBusy ? "사진 보내는 중" : "함께 사진 찍기", () => Send("photo"), egg.photoRequired ? Yellow : Cream, 54, CanAct && egg.photoRequired && _state.photoAvailable && !egg.photoBusy, 21);
            Button(actions, "글로 말하기", () => { _speechDrawer = !_speechDrawer; _zoneDrawer = false; _dirty = true; }, Cream, 54, CanAct, 21);
            Button(actions, "자리와 돌보기", () => { _zoneDrawer = !_zoneDrawer; _speechDrawer = false; _dirty = true; }, Cream, 54, CanAct, 21);
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
            if (egg.photoRequired && !_speechDrawer && !_zoneDrawer)
            {
                var photo = Surface("Photo quest hint", _content, Cream, false); Stretch(photo, -290, 100, 290, 142, new Vector2(.5f, 0), new Vector2(.5f, 0));
                var label = Label(photo, _state.photoAvailable ? "함께 찍은 사진을 보내면 친밀도가 65가 돼요" : "지금은 사진을 연결할 수 없어요. 잠시 후 다시 시도해 주세요.", 20, TextAnchor.MiddleCenter); Stretch(label.rectTransform, 8, 0, -8, 0);
                var recover = Button(_content, "보류한 사진 확인", () => Send("recoverPhoto"), Cream, 44, CanAct && !egg.photoBusy, 18);
                Stretch((RectTransform)recover.transform, -224, 10, -14, 54, new Vector2(1, 0), new Vector2(1, 0));
            }
        }

        void BuildCabinStart(EggState egg)
        {
            var host = Rect("Cabin start bottom sheet", _content);
            Stretch(host, -360, 10, 360, 302, new Vector2(.5f, 0), new Vector2(.5f, 0));
            var panel = Sheet(host);
            Heading(panel, egg != null && egg.phase == "hatched" ? "새 친구가 깨어났어요" : egg != null && (egg.phase == "failed" || egg.phase == "discarded") ? "새로운 만남을 시작할까요?" : "함께할 알을 골라 주세요");
            var row = NewRow(panel, 50);
            string[] tiers = { "small", "mid", "large" }; string[] names = { "작은 알", "중간 알", "큰 알" };
            for (var i = 0; i < tiers.Length; i++) { var tier = tiers[i]; Button(row, names[i], () => { _tier = tier; _dirty = true; }, _tier == tier ? Mint : Cream, 50, CanAct, 21); }
            var actions = NewRow(panel, 54);
            Button(actions, "이 알과 시작하기", () => Send("startEgg", new AppAction { tier = _tier }), Yellow, 54, CanAct && _state.canStart, 22);
            if (egg != null && egg.phase == "hatched") Button(actions, "새 친구 보러 가기", () => Navigate("dex"), Cream, 54, CanAct, 21);
            if (!_state.canStart) Note(panel, egg != null && egg.phase == "hatched" ? "새 친구와 함께하면서 다음 알을 기다려 주세요." : _state.sessionEnded ? "여행이 끝났어요. 설정에서 다음 연결을 준비해 주세요." : "지금은 알을 시작할 수 없어요. 설정에서 차량 연결 상태를 확인해 주세요.");
            else Note(panel, "알을 쓰다듬고 말을 걸어 주세요. 친밀도가 100이 되면 새 친구가 깨어나요.");
            if (egg != null && !string.IsNullOrEmpty(EggFeedbackLabel(egg.feedback))) Note(panel, EggFeedbackLabel(egg.feedback));
        }

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
            var left = Sheet(_content, 0, .64f);
            var right = Sheet(_content, .64f, 1);
            var entries = Items(_state.dex);
            Heading(left, "만난 친구 " + entries.Count(d => d.collected) + " / " + entries.Length);
            Note(left, "친구를 누르면 이야기와 배운 행동을 볼 수 있어요.");
            if (entries.Length == 0) { Copy(left, "도감 정보를 불러오는 중이에요. 설정에서 다시 확인할 수 있어요."); return; }
            if (!entries.Any(d => d.id == _selectedDex)) _selectedDex = entries.FirstOrDefault(d => d.collected)?.id ?? entries[0].id;
            var grid = Rect("Dex grid", left);
            var layout = grid.gameObject.AddComponent<GridLayoutGroup>();
            var gridWidth = Mathf.Max(180, _content.rect.width * .64f - 68);
            var columns = Mathf.Clamp(Mathf.FloorToInt((gridWidth + 12) / 166), 2, 6);
            layout.cellSize = new Vector2((gridWidth - (columns - 1) * 12) / columns, 176); layout.spacing = new Vector2(12, 16);
            layout.constraint = GridLayoutGroup.Constraint.FixedColumnCount; layout.constraintCount = columns;
            var gridSize = grid.gameObject.AddComponent<LayoutElement>(); gridSize.preferredHeight = Mathf.Ceil(entries.Length / (float)columns) * 192;
            foreach (var entry in entries)
            {
                var selected = entry;
                var tile = Surface(entry.name, grid, _selectedDex == entry.id ? Mint : Color.white);
                var button = tile.gameObject.AddComponent<Button>(); button.onClick.AddListener(() => { _selectedDex = selected.id; _selectedCreature = null; _dirty = true; });
                var artRoot = Rect("Portrait", tile); Stretch(artRoot, 10, 48, -10, -8);
                if (entry.collected) Art(artRoot, entry.sprite, 116);
                else
                {
                    var text = Label(artRoot, "아직\n만나지 못했어요", 23, TextAnchor.MiddleCenter); Stretch(text.rectTransform);
                }
                var name = Label(tile, entry.collected ? entry.name : "???", 23, TextAnchor.MiddleCenter);
                Stretch(name.rectTransform, 5, 6, -5, 48, Vector2.zero, new Vector2(1, 0));
            }
            var detail = entries.First(d => d.id == _selectedDex);
            Heading(right, detail.collected ? detail.name : "아직 만나지 못한 친구");
            if (!detail.collected)
            {
                Copy(right, string.IsNullOrEmpty(detail.description) ? "여행하며 알을 키워 보세요. 이 친구를 만나면 이야기와 모습이 도감에 남아요." : detail.description);
                Button(right, "차 안에서 알 키우기", () => Navigate("cabin"), Yellow, 72, CanAct); return;
            }
            Art(right, detail.sprite, 104);
            Copy(right, AttributeLabel(detail.attribute) + " · " + RoleLabel(detail.role), 24);
            Copy(right, detail.description);
            var owned = Items(_state.creatures).Where(c => c.speciesId == detail.id).ToArray();
            if (owned.Length == 0) { Note(right, "도감에는 기록되어 있지만 지금 함께하는 개체 정보는 없어요."); return; }
            if (!owned.Any(c => c.id == _selectedCreature)) _selectedCreature = owned[0].id;
            if (owned.Length > 1) foreach (var creature in owned)
            {
                var selected = creature;
                Button(right, creature.name + " · " + ShortId(creature.id), () => { _selectedCreature = selected.id; _dirty = true; }, _selectedCreature == creature.id ? Mint : Cream, 62, CanAct, 23);
            }
            var friend = owned.First(c => c.id == _selectedCreature);
            var companionId = friend.id;
            Button(right, "이 친구와 차량에서 함께하기", () =>
            {
                if (_state.connected && !_state.sessionEnded) Send("selectCarCompanion", new AppAction { creatureId = companionId });
            }, Mint, 54, CanAct && _state.connected && !_state.sessionEnded, 21);
            if (_state.sessionEnded) Note(right, "여행이 끝났어요. 차량과 다시 연결한 뒤 친구를 선택해 주세요.");
            else if (!_state.connected) Note(right, "차량과 연결한 뒤 함께할 친구를 선택할 수 있어요.");
            Copy(right, "차량 친구의 관찰 기록 " + _state.fishingRecords + "건", 21);
            if (!string.IsNullOrEmpty(_state.fishingError))
            {
                Note(right, _state.fishingError);
                Button(right, "낚시 저장 다시 확인", () => Send("retryFishingSave"), Cream, 48, CanAct, 20);
            }
            CreatureActions(right, friend);
            Space(right); Copy(right, "친구에게 요리 주기", 27);
            FeedOptions(right, friend.id);
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
            var host = Rect("Supply inventory", _content); Stretch(host, 0, 0, 0, 0, new Vector2(.14f, 0), new Vector2(.86f, 1));
            var panel = Sheet(host);
            Heading(panel, "여행에서 모은 보급품");
            var materials = NewRow(panel, 48);
            foreach (var material in Items(_state.materials)) Button(materials, material.label + "  " + material.count + "개", null, Cream, 48, false, 22);
            Note(panel, "주행과 창밖 관찰로 모은 재료예요. 저장된 재료와 거점 요약을 차량에도 전달해요.");
            var creatures = Items(_state.creatures);
            if (!creatures.Any(c => c.id == _selectedCreature)) _selectedCreature = creatures.FirstOrDefault()?.id;
            if (creatures.Length > 0)
            {
                var recipients = NewRow(panel, 48);
                Copy(recipients, "요리 받을 친구 · " + CreatureName(_selectedCreature), 22);
                if (creatures.Length > 1) Button(recipients, "다른 친구 고르기", () => { var index = Array.FindIndex(creatures, c => c.id == _selectedCreature); _selectedCreature = creatures[(index + 1) % creatures.Length].id; _dirty = true; }, Cream, 48, CanAct, 20);
                FeedOptions(panel, _selectedCreature);
            }
            else
            {
                Note(panel, "함께하는 친구가 생기면 요리를 줄 수 있어요.");
                foreach (var food in Items(_state.foods)) Copy(panel, food.label + " · " + food.count + "개", 22);
            }
            Button(panel, "주방에서 요리하기", () => OpenVillageFacility("kitchen"), Cream, 48, CanAct, 21);
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

        void BuildSettings()
        {
            var left = Sheet(_content, 0, .53f);
            var right = Sheet(_content, .53f, 1);
            Heading(left, _state.connected ? "차량과 연결되어 있어요" : "차량과 함께 시작해요");
            Copy(left, _state.sessionEnded ? "이전 여행이 끝났어요. 차량에서 새로운 연결 정보를 확인해 주세요." : "차량 화면의 세션 ID와 페어링 코드를 입력해 주세요.");
            Copy(left, "세션 ID", 24); Field(left, _sessionId, "차량에 표시된 세션 ID", text => _sessionId = text, 160);
            Copy(left, "페어링 코드", 24); Field(left, _pairCode, "차량에 표시된 코드", text => _pairCode = text, 32);
            LiveEnable(Button(left, "차량과 연결하기", () => Send("pair", new AppAction { sessionId = _sessionId.Trim(), pairCode = _pairCode.Trim() }), Yellow, 72, CanAct && !string.IsNullOrWhiteSpace(_sessionId) && !string.IsNullOrWhiteSpace(_pairCode)), () => CanAct && !string.IsNullOrWhiteSpace(_sessionId) && !string.IsNullOrWhiteSpace(_pairCode), Yellow);
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
