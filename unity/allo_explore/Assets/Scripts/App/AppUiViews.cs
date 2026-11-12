using System;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        string _facility = "workshop", _recipe, _lesson;

        void BuildHome()
        {
            var panel = Sheet(_content, 0, .29f, true);
            Heading(panel, "오늘도 함께해요");
            Copy(panel, "친구 " + Items(_state.creatures).Length + "명과 함께하는 작은 광장이에요.");
            Space(panel);
            Button(panel, "차 안으로 가기", () => Navigate("cabin"), Yellow, 72, CanAct);
            Button(panel, "캠프 돌보기", () => Navigate("camp"), Mint, 68, CanAct);
            Button(panel, "친구 만나기", () => Navigate("dex"), Cream, 68, CanAct);
            Space(panel);
            Copy(panel, "여행에서 모은 보급품", 25);
            foreach (var material in Items(_state.materials)) Note(panel, material.label + "  " + material.count);
            if (Items(_state.creatures).Length == 0) Note(panel, "아직 함께하는 친구가 없어요. 차 안에서 알을 키워 첫 친구를 만나 보세요.");
            var jobs = Items(_state.jobs);
            if (jobs.Length > 0)
            {
                Space(panel); Copy(panel, "지금 캠프에서는", 25);
                foreach (var job in jobs) Note(panel, job.label + " · " + TimeLabel(job.remainingSec));
            }
        }

        void BuildCabin()
        {
            var egg = _state.egg;
            var left = Sheet(_content, 0, .28f, true);
            var right = Sheet(_content, .70f, 1, true);
            if (egg == null || !egg.active)
            {
                Heading(left, egg != null && egg.phase == "hatched" ? "새 친구를 만났어요" : egg != null && egg.phase == "failed" ? "알이 떠났어요" : egg != null && egg.phase == "discarded" ? "다시 시작할까요?" : "함께할 알 고르기");
                Copy(left, egg != null && egg.phase == "hatched" ? "부화한 친구는 광장과 도감에서 다시 만날 수 있어요." : "차 안에서 알을 쓰다듬고 말을 걸며 천천히 가까워져요.");
                if (egg != null && !string.IsNullOrEmpty(egg.feedback)) Note(left, EggFeedbackLabel(egg.feedback));
                if (egg != null && egg.phase == "hatched") Button(left, "새 친구 보러 가기", () => Navigate("dex"), Mint);
                Heading(right, "새로운 만남");
                var row = NewRow(right);
                string[] tiers = { "small", "mid", "large" };
                string[] names = { "작은 알", "중간 알", "큰 알" };
                for (var i = 0; i < tiers.Length; i++)
                {
                    var tier = tiers[i];
                    Button(row, names[i], () => { _tier = tier; _dirty = true; }, _tier == tier ? Mint : Cream, 68, CanAct, 22);
                }
                Copy(right, "알을 고른 뒤 함께할 시간을 시작해 주세요. 친밀도가 100이 되면 새 친구가 깨어나요.");
                Button(right, egg != null && (egg.phase == "failed" || egg.phase == "discarded") ? "이 알로 다시 시작" : "이 알과 시작하기", () => Send("startEgg", new AppAction { tier = _tier }), Yellow, 72, CanAct && _state.canStart);
                if (!_state.canStart) Note(right, _state.sessionEnded ? "여행이 끝났어요. 설정에서 다음 연결을 준비해 주세요." : "지금은 알을 시작할 수 없어요. 설정에서 차량 연결 상태를 확인해 주세요.");
                Button(right, "연결 상태 보기", () => Navigate("settings"), Cream);
                return;
            }
            Heading(left, egg.photoRequired ? "함께 사진을 남겨요" : "조금씩 가까워져요");
            Progress(left, egg.score / 100f, "친밀도  " + Mathf.FloorToInt(egg.score) + " / 100");
            if (!string.IsNullOrEmpty(egg.remainingLabel)) Copy(left, egg.remainingLabel, 26);
            if (!string.IsNullOrEmpty(egg.feedback)) Note(left, EggFeedbackLabel(egg.feedback));
            Note(left, egg.photoRequired ? "50에서 잠시 멈췄어요. 함께 사진을 찍고 보내면 친밀도가 65가 돼요." : "친밀도가 100이 되면 새 친구가 깨어나요.");
            Note(left, "화면 속 알을 문지르면 쓰다듬을 수 있어요. 알을 끌거나 자리를 눌러 옮겨 보세요.");
            Copy(left, "알이 있는 자리", 25);
            string[] zones = { "대시보드", "왼쪽 창턱", "오른쪽 창턱", "앞 바닥" };
            if (egg.preferredZone >= 0 && egg.preferredZone < zones.Length) Note(left, "좋아하는 자리 · " + zones[egg.preferredZone]);
            for (var i = 0; i < 4; i += 2)
            {
                var row = NewRow(left, 62);
                for (var j = i; j < i + 2; j++)
                {
                    var zone = j;
                    Button(row, (egg.zone == zone ? "현재 · " : "") + zones[j], () => Send("placeEgg", new AppAction { zone = zone }), egg.zone == zone ? Mint : Cream, 62, CanAct && egg.moveCooldown <= 0 && !egg.photoRequired && egg.zone != zone, 21);
                }
            }
            if (egg.moveCooldown > 0) Note(left, "자리 이동은 " + egg.moveCooldown + "초 뒤에 가능해요.");
            Heading(right, "알과 시간 보내기");
            Button(right, CooldownLabel("쓰다듬기", egg.petCooldown), () => Send("petEgg"), egg.photoRequired ? Cream : Yellow, 72, CanAct && !egg.photoRequired && egg.petCooldown <= 0);
            Button(right, egg.speechBusy ? "말을 듣고 있어요" : CooldownLabel("말 걸기", egg.speechCooldown), () => Send("speech"), Mint, 68, CanAct && !egg.photoRequired && !egg.speechBusy && egg.speechCooldown <= 0 && _state.speechAvailable);
            if (!_state.speechAvailable) Note(right, "지금은 대화를 연결할 수 없어요. 잠시 후 다시 시도해 주세요.");
            Field(right, _speech, "알에게 해 줄 말", text => _speech = text, 240);
            LiveEnable(Button(right, "적은 말 전하기", () => { Send("submitSpeech", new AppAction { text = _speech.Trim() }); _speech = ""; }, Cream, 62, CanAct && _state.speechAvailable && !egg.photoRequired && !egg.speechBusy && egg.speechCooldown <= 0 && !string.IsNullOrWhiteSpace(_speech), 24), () => CanAct && _state.speechAvailable && _state.egg != null && !_state.egg.photoRequired && !_state.egg.speechBusy && _state.egg.speechCooldown <= 0 && !string.IsNullOrWhiteSpace(_speech), Cream);
            if (egg.photoRequired)
            {
                Button(right, egg.photoBusy ? "사진 업로드 확인 중" : "카메라로 함께 찍기", () => Send("photo"), Yellow, 72, CanAct && _state.photoAvailable && !egg.photoBusy);
                if (!_state.photoAvailable) Note(right, "지금은 사진을 연결할 수 없어요. 잠시 후 다시 시도해 주세요.");
                Button(right, "보류한 사진 다시 확인", () => Send("recoverPhoto"), Cream, 62, CanAct && !egg.photoBusy, 22);
            }
            Space(right);
            Button(right, "이 알 돌보기 그만두기", () => Confirm("이 알 돌보기를 그만둘까요?", "현재 알의 돌보기가 종료돼요. 이미 만난 친구는 그대로이며, 새 알로 다시 시작할 수 있어요.", () => Send("discardEgg")), Cream, 60, CanAct && !egg.photoBusy && !egg.speechBusy, 22);
        }

        void BuildCamp()
        {
            var left = Sheet(_content, 0, .34f);
            var right = Sheet(_content, .34f, 1);
            Heading(left, "누구와 일할까요?");
            var tabs = NewRow(left, 64);
            foreach (var role in new[] { "builder", "cook", "trainer" })
            {
                var selected = role;
                Button(tabs, RoleLabel(role), () => { _campTab = selected; _dirty = true; }, _campTab == role ? Mint : Cream, 64, CanAct, 22);
            }
            var assigned = Assignment(_campTab);
            var eligible = Items(_state.creatures).Where(c => c.role == _campTab).ToArray();
            if (!_workers.TryGetValue(_campTab, out var picked) || !eligible.Any(c => c.id == picked)) picked = assigned;
            if (string.IsNullOrEmpty(picked) && eligible.Length > 0) picked = eligible[0].id;
            _workers[_campTab] = picked;
            var running = Job(_campTab);
            if (eligible.Length == 0) Copy(left, "아직 " + RoleLabel(_campTab) + " 친구가 없어요. 알에서 해당 역할의 친구를 만나면 담당으로 정할 수 있어요.");
            foreach (var creature in eligible)
            {
                var selected = creature;
                var busy = CreatureBusy(creature.id);
                Button(left, creature.name + (assigned == creature.id ? " · 담당" : busy ? " · 작업 중" : ""), () => { _workers[_campTab] = selected.id; _dirty = true; }, picked == creature.id ? Mint : Cream, 68, CanAct && running == null && !busy, 24);
            }
            if (eligible.Length > 0)
            {
                Button(left, picked == assigned ? "담당으로 함께하고 있어요" : "이 친구를 담당으로 정하기", () => Send("assign", new AppAction { role = _campTab, creatureId = picked }), Cream, 68, CanAct && running == null && picked != assigned && !string.IsNullOrEmpty(picked), 23);
                if (!string.IsNullOrEmpty(assigned) && running == null) Button(left, "담당 쉬게 하기", () => Send("assign", new AppAction { role = _campTab, creatureId = "" }), Cream, 60, CanAct, 22);
            }
            Space(left); Copy(left, "보유 재료", 26);
            foreach (var material in Items(_state.materials)) Note(left, material.label + "  " + material.count);
            foreach (var job in Items(_state.jobs))
            {
                Space(left); Progress(left, job.progress, RoleLabel(job.role) + " · " + job.label + " · " + TimeLabel(job.remainingSec));
                Note(left, CreatureName(job.workerId) + (string.IsNullOrEmpty(job.targetId) ? "" : " → " + CreatureName(job.targetId)));
            }
            Heading(right, _campTab == "builder" ? "캠프를 넓혀요" : _campTab == "cook" ? "든든한 요리 시간" : "새로운 행동을 배워요");
            if (running != null)
            {
                Progress(right, running.progress, running.label + " · " + TimeLabel(running.remainingSec));
                Note(right, "앱을 닫아도 작업이 계속 진행돼요. 다른 역할의 작업은 함께 진행할 수 있어요.");
                Button(right, "이 작업 취소하기", () => Confirm("진행 중인 작업을 취소할까요?", "취소하면 사용한 재료가 돌아와요.", () => Send("cancel", new AppAction { role = _campTab })), Cream, 66, CanAct);
                return;
            }
            if (_campTab == "builder") BuildConstruction(right);
            else if (_campTab == "cook") BuildCooking(right);
            else BuildTraining(right);
        }

        void BuildConstruction(Transform panel)
        {
            var facilities = Items(_state.facilities);
            if (!facilities.Any(f => f.id == _facility)) _facility = facilities.FirstOrDefault()?.id;
            foreach (var facility in facilities)
            {
                var choice = facility;
                Button(panel, facility.label + "  Lv." + facility.level + (facility.level > 0 ? "" : " · 미건설"), () => { _facility = choice.id; _dirty = true; }, _facility == facility.id ? Mint : Cream, 66, CanAct);
            }
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
            foreach (var food in foods)
            {
                var choice = food;
                Button(panel, food.label + " · 주방 Lv." + food.requiredLevel + (food.unlocked ? "" : " · 잠김"), () => { _recipe = choice.id; _dirty = true; }, _recipe == food.id ? Mint : Cream, 66, CanAct);
            }
            var selected = foods.FirstOrDefault(f => f.id == _recipe);
            if (selected == null) { Copy(panel, "아직 요리 정보가 없어요."); return; }
            Space(panel); Copy(panel, selected.label + " · 보유 " + selected.count + "개", 28);
            Copy(panel, "필요 재료  " + Cost(0, 0, selected.costIngredient));
            Note(panel, "완성한 요리는 도감이나 보급품에서 친구에게 줄 수 있어요.");
            var reason = !selected.unlocked ? "주방 Lv." + selected.requiredLevel + "에서 열려요." : WorkReason("cook", 0, 0, selected.costIngredient);
            if (reason != null) Note(panel, reason);
            Button(panel, "이 요리 만들기", () => Confirm(selected.label + " 요리를 시작할까요?", Cost(0, 0, selected.costIngredient) + "를 사용해요. 완성한 요리는 보급품에 모여요.", () => Send("cook", new AppAction { recipeId = selected.id })), Yellow, 72, CanAct && reason == null);
        }

        void BuildTraining(Transform panel)
        {
            var training = Items(_state.training);
            if (!training.Any(t => t.id == _lesson)) _lesson = training.FirstOrDefault()?.id;
            var tabs = NewRow(panel, 66);
            foreach (var lesson in training)
            {
                var choice = lesson;
                Button(tabs, lesson.label, () => { _lesson = choice.id; _dirty = true; }, _lesson == lesson.id ? Mint : Cream, 66, CanAct, 24);
            }
            var selected = training.FirstOrDefault(t => t.id == _lesson);
            if (selected == null) { Copy(panel, "아직 훈련 정보가 없어요."); return; }
            Copy(panel, "배울 친구를 골라 주세요", 27);
            var trainer = Assignment("trainer");
            var targets = Items(_state.creatures).Where(c => c.id != trainer).ToArray();
            if (!targets.Any(c => c.id == _selectedTarget)) _selectedTarget = targets.FirstOrDefault(c => !CreatureBusy(c.id))?.id;
            foreach (var creature in targets)
            {
                var choice = creature;
                var learned = Items(creature.actions).Contains(selected.id);
                Button(panel, creature.name + (learned ? " · 이미 배웠어요" : CreatureBusy(creature.id) ? " · 작업 중" : ""), () => { _selectedTarget = choice.id; _dirty = true; }, _selectedTarget == creature.id ? Mint : Cream, 62, CanAct && !CreatureBusy(creature.id) && !learned, 24);
            }
            if (targets.Length == 0) Note(panel, "담당 훈련가와 다른 친구가 한 명 더 필요해요.");
            var cost = Cost(selected.woodCost, selected.stoneCost, selected.ingredientCost);
            Copy(panel, "필요 재료  " + cost);
            var target = targets.FirstOrDefault(c => c.id == _selectedTarget);
            var reason = !selected.unlocked ? "훈련장 Lv." + selected.requiredLevel + "에서 열려요." : WorkReason("trainer", selected.woodCost, selected.stoneCost, selected.ingredientCost);
            if (reason == null && target == null) reason = "배울 친구를 골라 주세요.";
            if (reason == null && CreatureBusy(target.id)) reason = "이 친구는 다른 작업을 하고 있어요.";
            if (reason == null && Items(target.actions).Contains(selected.id)) reason = "이 친구는 이미 이 행동을 배웠어요.";
            if (reason != null) Note(panel, reason);
            Button(panel, "이 친구와 훈련하기", () => Confirm(selected.label + " 훈련을 시작할까요?", CreatureName(_selectedTarget) + "와 훈련하며 " + cost + "를 사용해요.", () => Send("train", new AppAction { actionId = selected.id, targetId = _selectedTarget })), Yellow, 72, CanAct && reason == null);
        }

        void BuildDex()
        {
            var left = Sheet(_content, 0, .47f);
            var right = Sheet(_content, .47f, 1);
            var entries = Items(_state.dex);
            Heading(left, "만난 친구 " + entries.Count(d => d.collected) + " / " + entries.Length);
            Note(left, "친구를 누르면 이야기와 배운 행동을 볼 수 있어요.");
            if (entries.Length == 0) { Copy(left, "도감 정보를 불러오는 중이에요. 설정에서 다시 확인할 수 있어요."); return; }
            if (!entries.Any(d => d.id == _selectedDex)) _selectedDex = entries.FirstOrDefault(d => d.collected)?.id ?? entries[0].id;
            var grid = Rect("Dex grid", left);
            var layout = grid.gameObject.AddComponent<GridLayoutGroup>();
            var gridWidth = Mathf.Max(180, _content.rect.width * .47f - 68);
            var columns = gridWidth < 440 ? 2 : 3;
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
                Copy(right, "여행하며 알을 키워 보세요. 이 친구를 만나면 이야기와 모습이 도감에 남아요.");
                Button(right, "차 안에서 알 키우기", () => Navigate("cabin"), Yellow, 72, CanAct); return;
            }
            Art(right, detail.sprite, 150);
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
            var left = Sheet(_content, 0, .43f);
            var right = Sheet(_content, .43f, 1);
            Heading(left, "차곡차곡 모은 재료");
            var materials = Items(_state.materials);
            if (materials.Length == 0) Copy(left, "아직 재료 정보가 없어요.");
            foreach (var material in materials)
            {
                Space(left); Copy(left, material.label + "  " + material.count + "개", 30);
            }
            Space(left, 20); Copy(left, "여행 활동 연결", 27);
            Copy(left, RewardLabel(_state.rewardStatus));
            Note(left, "낚시·벌목 보상은 아직 준비 중이에요. 활동을 해도 지금은 재료가 추가되지 않아요.");
            Note(left, "주행과 창밖 관찰로 모은 재료예요.");
            Heading(right, "완성한 요리");
            var creatures = Items(_state.creatures);
            if (creatures.Length == 0) { Copy(right, "함께하는 친구가 생기면 완성한 요리를 줄 수 있어요."); foreach (var f in Items(_state.foods)) Note(right, f.label + " · " + f.count + "개"); return; }
            if (!creatures.Any(c => c.id == _selectedCreature)) _selectedCreature = creatures[0].id;
            Copy(right, "요리를 받을 친구", 26);
            foreach (var creature in creatures)
            {
                var selected = creature;
                Button(right, creature.name + " · " + RoleLabel(creature.role), () => { _selectedCreature = selected.id; _dirty = true; }, _selectedCreature == creature.id ? Mint : Cream, 62, CanAct, 24);
            }
            Space(right); FeedOptions(right, _selectedCreature);
            Button(right, "캠프에서 요리하기", () => { _campTab = "cook"; Navigate("camp"); }, Cream, 66, CanAct);
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
