using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        bool _campDetail, _speechDrawer, _zoneDrawer;
        RectTransform _villageLayer, _villageContent, _villageFriend;
        ScrollRect _villageScroll;
        Vector2 _villageViewportSize;
        bool _villageSized;
        string _villageFriendId;
        readonly Dictionary<string, RectTransform> _facilityNodes = new Dictionary<string, RectTransform>();
        readonly Dictionary<string, Sprite> _villageArt = new Dictionary<string, Sprite>();
        readonly Dictionary<string, Sprite> _lineIcons = new Dictionary<string, Sprite>();

        void OpenVillageFacility(string id)
        {
            if (!CanAct || _confirmAction != null) return;
            if (_facility != id || !_campDetail) _scrollPositions.Remove("camp:view:0");
            _facility = id;
            var facility = Items(_state.facilities).FirstOrDefault(f => f.id == id);
            _campTab = facility != null && facility.level == 0 ? "builder" : id == "kitchen" ? "cook" : id == "training" ? "trainer" : "builder";
            _campDetail = true;
            if (View == "camp") _dirty = true;
            else Send("navigate", new AppAction { view = "camp" });
        }

        void BuildVillageMap(float unused, bool home)
        {
            EnsureVillageWorld();
            _villageLayer.gameObject.SetActive(true);
            UpdateVillageGeometry();
            var interaction = _villageLayer.GetComponent<CanvasGroup>();
            interaction.interactable = interaction.blocksRaycasts = _confirmAction == null;
            _villageScroll.enabled = _confirmAction == null;
            if (_confirmAction != null) _villageScroll.StopMovement();
            foreach (var entry in _facilityNodes) UpdateFacilityNode(entry.Value, entry.Key);
            UpdateVillageFriend();
        }

        void EnsureVillageWorld()
        {
            if (_villageLayer != null) return;
            // Art spans the canvas; all controls remain inside the safe-area overlay.
            _villageLayer = Rect("Village map", _safe.parent); Stretch(_villageLayer); _villageLayer.SetAsFirstSibling();
            var hit = _villageLayer.gameObject.AddComponent<Image>(); hit.color = Color.clear;
            _villageLayer.gameObject.AddComponent<RectMask2D>();
            _villageLayer.gameObject.AddComponent<CanvasGroup>();
            _villageContent = Rect("Village content", _villageLayer);
            _villageContent.anchorMin = _villageContent.anchorMax = _villageContent.pivot = new Vector2(.5f, .5f);
            var landscape = Rect("Natural village landscape", _villageContent); Stretch(landscape);
            var image = landscape.gameObject.AddComponent<RawImage>(); image.texture = Resources.Load<Texture2D>("VillageArt/background"); image.raycastTarget = false;
            image.color = image.texture != null ? Color.white : Hex("7D8C67");
            _villageScroll = _villageLayer.gameObject.AddComponent<ScrollRect>();
            _villageScroll.viewport = _villageLayer; _villageScroll.content = _villageContent;
            _villageScroll.horizontal = _villageScroll.vertical = _villageScroll.inertia = true;
            _villageScroll.movementType = ScrollRect.MovementType.Clamped; _villageScroll.decelerationRate = .10f; _villageScroll.scrollSensitivity = 32;
            CreateFacilityNode("workshop", new Vector2(.20f, .46f));
            CreateFacilityNode("kitchen", new Vector2(.505f, .43f));
            CreateFacilityNode("training", new Vector2(.81f, .47f));
        }

        void UpdateVillageGeometry()
        {
            if (_villageLayer == null || _villageContent == null || !_villageLayer.gameObject.activeSelf) return;
            var size = _villageLayer.rect.size;
            if (size.x <= 0 || size.y <= 0 || (_villageSized && Vector2.Distance(size, _villageViewportSize) < .1f)) return;
            Canvas.ForceUpdateCanvases(); size = _villageLayer.rect.size;
            var pan = _villageSized ? _villageScroll.normalizedPosition : new Vector2(.5f, .5f);
            var texture = Resources.Load<Texture2D>("VillageArt/background");
            var aspect = texture != null ? (float)texture.width / texture.height : 16f / 9f;
            var width = Mathf.Max(size.x * 1.25f, (size.y + 300) * aspect);
            _villageContent.sizeDelta = new Vector2(width, width / aspect);
            _villageViewportSize = size; _villageSized = true;
            Canvas.ForceUpdateCanvases(); _villageScroll.normalizedPosition = pan;
        }

        void CreateFacilityNode(string id, Vector2 position)
        {
            var node = Rect("Facility node " + id, _villageContent);
            node.anchorMin = node.anchorMax = position; node.pivot = new Vector2(.5f, 0); node.sizeDelta = new Vector2(230, 215);
            var hit = node.gameObject.AddComponent<Image>(); hit.color = Color.clear;
            var button = node.gameObject.AddComponent<Button>(); button.onClick.AddListener(() => OpenVillageFacility(id));
            var art = Rect("Building illustration", node); Stretch(art);
            var image = art.gameObject.AddComponent<Image>(); image.sprite = VillageSprite(id); image.preserveAspect = true; image.raycastTarget = false; image.color = Color.white;
            var label = Surface("Facility name and level", node, new Color(.949f, .933f, .898f, .93f), false);
            Stretch(label, 18, -47, -18, -3, Vector2.zero, new Vector2(1, 0)); button.targetGraphic = label.GetComponent<Image>();
            var title = Label(label, "", 20, TextAnchor.MiddleLeft); title.gameObject.name = "Name"; Stretch(title.rectTransform, 9, 17, -50, 0);
            var level = Label(label, "", 17, TextAnchor.MiddleRight); level.gameObject.name = "Level"; Stretch(level.rectTransform, -58, 17, -9, 0, new Vector2(1, 0), Vector2.one);
            var state = Label(label, "", 15, TextAnchor.MiddleLeft); state.gameObject.name = "State"; Stretch(state.rectTransform, 9, 1, -9, -24);
            for (var i = 0; i < 2; i++)
            {
                var bubble = Surface("Work " + i, node, new Color(.08f, .14f, .11f, .82f), false);
                Stretch(bubble, 14, -90 - i * 42, -14, -52 - i * 42, Vector2.zero, new Vector2(1, 0));
                var text = Label(bubble, "", 16, TextAnchor.MiddleCenter); text.color = Cream; Stretch(text.rectTransform, 5, 6, -5, 0);
                var track = Surface("Progress", bubble, new Color(1, 1, 1, .18f), false); Stretch(track, 8, 4, -8, 7, Vector2.zero, new Vector2(1, 0));
                var fill = Surface("Fill", track, Yellow, false); Stretch(fill);
                bubble.gameObject.SetActive(false);
            }
            _facilityNodes[id] = node;
        }

        void UpdateFacilityNode(RectTransform node, string id)
        {
            var facility = Items(_state.facilities).FirstOrDefault(f => f.id == id);
            node.GetComponent<Button>().interactable = CanAct && facility != null;
            var label = node.Find("Facility name and level");
            label.Find("Name").GetComponent<Text>().text = facility?.label ?? (id == "workshop" ? "작업장" : id == "kitchen" ? "주방" : "훈련장");
            label.Find("Level").GetComponent<Text>().text = facility == null ? "Lv.?" : "Lv." + facility.level;
            var role = id == "kitchen" ? "cook" : id == "training" ? "trainer" : "builder";
            var worker = Assignment(role);
            label.Find("State").GetComponent<Text>().text = facility == null ? "정보 확인 중" : facility.level == 0 ? "미건설 · 시설 미리보기" : string.IsNullOrEmpty(worker) ? "담당 친구 미배정" : "담당 · " + CreatureName(worker);
            var jobs = Items(_state.jobs).Where(j => (j.role == role && (role != "builder" || j.targetId == id)) || (j.role == "builder" && j.targetId == id)).Take(2).ToArray();
            for (var i = 0; i < 2; i++)
            {
                var bubble = node.Find("Work " + i); bubble.gameObject.SetActive(i < jobs.Length);
                if (i >= jobs.Length) continue;
                bubble.GetComponentInChildren<Text>().text = CreatureName(jobs[i].workerId) + " · " + TimeLabel(jobs[i].remainingSec);
                Stretch((RectTransform)bubble.Find("Progress/Fill"), 0, 0, 0, 0, Vector2.zero, new Vector2(Mathf.Clamp01(jobs[i].progress), 1));
            }
        }

        void UpdateVillageFriend()
        {
            var friend = Items(_state.creatures).FirstOrDefault();
            if (friend == null) { if (_villageFriend != null) _villageFriend.gameObject.SetActive(false); return; }
            if (_villageFriend != null && _villageFriendId == friend.id) { _villageFriend.gameObject.SetActive(true); return; }
            if (_villageFriend != null) { _villageFriend.gameObject.SetActive(false); Destroy(_villageFriend.gameObject); }
            _villageFriendId = friend.id;
            _villageFriend = Rect("Village friend " + friend.id, _villageContent);
            _villageFriend.anchorMin = _villageFriend.anchorMax = new Vector2(.37f, .30f); _villageFriend.sizeDelta = new Vector2(90, 98);
            var portrait = Rect("Friend avatar", _villageFriend); Stretch(portrait, 10, 24, -10, 0); Art(portrait, friend.sprite, 72);
            var badge = Surface("Friend name", _villageFriend, new Color(.08f, .14f, .11f, .80f), false); Stretch(badge, -15, 0, 15, 24, Vector2.zero, new Vector2(1, 0));
            var name = Label(badge, friend.name, 17, TextAnchor.MiddleCenter); name.color = Cream; Stretch(name.rectTransform, 4, 0, -4, 0);
            var hit = _villageFriend.gameObject.AddComponent<Image>(); hit.color = Color.clear;
            _villageFriend.gameObject.AddComponent<Button>().onClick.AddListener(() => { _selectedDex = friend.speciesId; _selectedCreature = friend.id; Navigate("dex"); });
        }

        Sprite VillageSprite(string kind)
        {
            if (_villageArt.TryGetValue(kind, out var cached)) return cached;
            var texture = Resources.Load<Texture2D>("VillageArt/" + kind);
            if (texture == null) return null;
            return _villageArt[kind] = Sprite.Create(texture, new UnityEngine.Rect(0, 0, texture.width, texture.height), new Vector2(.5f, .5f), 100, 0, SpriteMeshType.FullRect);
        }

        Sprite ActionCircleSprite()
        {
            const string key = "action-circle";
            if (_lineIcons.TryGetValue(key, out var cached)) return cached;
            const int n = 72; var pixels = new Color[n * n];
            for (var y = 0; y < n; y++) for (var x = 0; x < n; x++)
                pixels[y * n + x] = new Color(1, 1, 1, Mathf.Clamp01(35 - Vector2.Distance(new Vector2(x + .5f, y + .5f), new Vector2(36, 36))));
            var texture = new Texture2D(n, n, TextureFormat.RGBA32, false) { name = "ALLO action circle", filterMode = FilterMode.Bilinear }; texture.SetPixels(pixels); texture.Apply();
            return _lineIcons[key] = Sprite.Create(texture, new UnityEngine.Rect(0, 0, n, n), new Vector2(.5f, .5f), 100);
        }

        Sprite NavigationIcon(string name)
        {
            if (_lineIcons.TryGetValue(name, out var cached)) return cached;
            const int n = 64;
            var pixels = new Color[n * n];
            void Dot(float x, float y, float radius)
            {
                for (var py = Mathf.Max(0, (int)(y - radius - 1)); py < Mathf.Min(n, y + radius + 1); py++)
                for (var px = Mathf.Max(0, (int)(x - radius - 1)); px < Mathf.Min(n, x + radius + 1); px++)
                { var alpha = Mathf.Clamp01(radius + .5f - Vector2.Distance(new Vector2(x, y), new Vector2(px, py))); if (alpha > pixels[py * n + px].a) pixels[py * n + px] = new Color(1, 1, 1, alpha); }
            }
            void Line(float ax, float ay, float bx, float by)
            { var distance = Vector2.Distance(new Vector2(ax, ay), new Vector2(bx, by)); for (var i = 0; i <= distance; i++) Dot(Mathf.Lerp(ax, bx, distance == 0 ? 0 : i / distance), Mathf.Lerp(ay, by, distance == 0 ? 0 : i / distance), 2.5f); }
            void Circle(float x, float y, float radius)
            { for (var i = 0; i < 72; i++) { var a = i * Mathf.PI / 36; Dot(x + Mathf.Cos(a) * radius, y + Mathf.Sin(a) * radius, 2.4f); } }
            if (name == "home") { Line(8, 30, 32, 53); Line(32, 53, 56, 30); Line(14, 31, 14, 10); Line(14, 10, 50, 10); Line(50, 10, 50, 31); Line(27, 10, 27, 29); Line(27, 29, 38, 29); Line(38, 29, 38, 10); }
            else if (name == "cabin") { Line(10, 18, 10, 39); Line(10, 39, 19, 49); Line(19, 49, 45, 49); Line(45, 49, 54, 39); Line(54, 39, 54, 18); Line(10, 18, 54, 18); Line(13, 34, 51, 34); Circle(20, 14, 5); Circle(45, 14, 5); }
            else if (name == "camp") { Line(10, 12, 10, 42); Line(10, 42, 32, 54); Line(32, 54, 54, 42); Line(54, 42, 54, 12); Line(10, 12, 54, 12); Line(24, 12, 24, 31); Line(24, 31, 40, 31); Line(40, 31, 40, 12); }
            else if (name == "dex") { Circle(32, 38, 13); Line(12, 10, 15, 20); Line(15, 20, 23, 27); Line(23, 27, 41, 27); Line(41, 27, 49, 20); Line(49, 20, 52, 10); Line(12, 10, 52, 10); }
            else if (name == "inventory") { Line(15, 9, 10, 36); Line(10, 36, 54, 36); Line(54, 36, 49, 9); Line(49, 9, 15, 9); Line(22, 36, 25, 53); Line(25, 53, 39, 53); Line(39, 53, 42, 36); Line(22, 23, 42, 23); }
            else { Circle(32, 32, 16); Circle(32, 32, 6); for (var i = 0; i < 8; i++) { var a = i * Mathf.PI / 4; Line(32 + Mathf.Cos(a) * 17, 32 + Mathf.Sin(a) * 17, 32 + Mathf.Cos(a) * 25, 32 + Mathf.Sin(a) * 25); } }
            var texture = new Texture2D(n, n, TextureFormat.RGBA32, false) { name = "ALLO line icon " + name, filterMode = FilterMode.Bilinear }; texture.SetPixels(pixels); texture.Apply();
            return _lineIcons[name] = Sprite.Create(texture, new UnityEngine.Rect(0, 0, n, n), new Vector2(.5f, .5f), 100);
        }
    }
}
