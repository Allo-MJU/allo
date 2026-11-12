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
        readonly Dictionary<string, Sprite> _villageArt = new Dictionary<string, Sprite>();
        readonly Dictionary<string, Sprite> _lineIcons = new Dictionary<string, Sprite>();

        void OpenVillageFacility(string id)
        {
            if (!CanAct) return;
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
            var map = Rect("Village map", _content); Stretch(map);
            map.gameObject.AddComponent<RectMask2D>();
            var background = Resources.Load<Texture2D>("VillageArt/background");
            var canvas = Rect("Natural village landscape", map); Stretch(canvas);
            var image = canvas.gameObject.AddComponent<RawImage>(); image.texture = background; image.raycastTarget = false;
            image.color = background != null ? Color.white : Hex("7D8C67");
            if (background != null)
            {
                var fit = canvas.gameObject.AddComponent<AspectRatioFitter>(); fit.aspectMode = AspectRatioFitter.AspectMode.EnvelopeParent; fit.aspectRatio = (float)background.width / background.height;
            }
            string[] ids = { "workshop", "kitchen", "training" };
            for (var i = 0; i < ids.Length; i++) BuildFacilityNode(map, ids[i], .20f + .305f * i);
            var hint = Surface("Village hint", map, new Color(.949f, .933f, .898f, .92f), false);
            Stretch(hint, 14, -46, 430, -10, new Vector2(0, 1), new Vector2(0, 1));
            var hintText = Label(hint, Items(_state.jobs).Length > 0 ? "친구들이 마을을 돌보고 있어요" : "시설을 눌러 함께할 일을 골라 주세요", 20, TextAnchor.MiddleCenter); Stretch(hintText.rectTransform, 8, 0, -8, 0);
            AddOwnedFriendChip(map);
            if (home)
            {
                var action = Button(map, "차 안으로 가기", () => Navigate("cabin"), Yellow, 54, CanAct, 22);
                Stretch((RectTransform)action.transform, -224, 14, -14, 68, new Vector2(1, 0), new Vector2(1, 0));
            }
        }

        void BuildFacilityNode(RectTransform map, string id, float x)
        {
            var facility = Items(_state.facilities).FirstOrDefault(f => f.id == id);
            var role = id == "kitchen" ? "cook" : id == "training" ? "trainer" : "builder";
            var node = Rect("Facility node " + id, map);
            node.anchorMin = node.anchorMax = new Vector2(x, .41f); node.pivot = new Vector2(.5f, 0); node.sizeDelta = new Vector2(300, 280);
            var hit = node.gameObject.AddComponent<Image>(); hit.color = Color.clear;
            var button = node.gameObject.AddComponent<Button>(); button.interactable = CanAct && facility != null;
            button.onClick.AddListener(() => OpenVillageFacility(id));
            var art = Rect("Building illustration", node); Stretch(art);
            var image = art.gameObject.AddComponent<Image>(); image.sprite = VillageSprite(id); image.preserveAspect = true; image.raycastTarget = false;
            image.color = new Color(1, 1, 1, facility != null && facility.level > 0 ? 1 : .45f);
            var label = Surface("Facility name and level", node, Cream);
            Stretch(label, 30, -58, -30, -6, Vector2.zero, new Vector2(1, 0)); label.GetComponent<Image>().raycastTarget = true;
            button.targetGraphic = label.GetComponent<Image>();
            var name = facility?.label ?? (id == "workshop" ? "작업장" : id == "kitchen" ? "주방" : "훈련장");
            var title = Label(label, name + "  Lv." + (facility != null ? facility.level.ToString() : "?"), 22, TextAnchor.MiddleCenter); Stretch(title.rectTransform, 4, 15, -4, 0);
            var subtitle = Label(label, facility == null ? "정보 확인 중" : facility.level == 0 ? "미건설 · 눌러서 짓기" : "시설 살펴보기", 17, TextAnchor.MiddleCenter); Stretch(subtitle.rectTransform, 4, 0, -4, -29);
            var jobs = Items(_state.jobs).Where(j => (j.role == role && (role != "builder" || j.targetId == id)) || (j.role == "builder" && j.targetId == id)).ToArray();
            for (var jobIndex = 0; jobIndex < jobs.Length; jobIndex++)
            {
                var job = jobs[jobIndex];
                var bubble = Surface("Facility working bubble", node, Cream);
                Stretch(bubble, 26, -112 - jobIndex * 52, -26, -64 - jobIndex * 52, Vector2.zero, new Vector2(1, 0)); bubble.GetComponent<Image>().raycastTarget = false;
                var text = Label(bubble, CreatureName(job.workerId) + " · " + TimeLabel(job.remainingSec), 18, TextAnchor.MiddleCenter); Stretch(text.rectTransform, 6, 9, -6, 0);
                var track = Surface("Facility work progress", bubble, Disabled, false); Stretch(track, 10, 5, -10, 9, Vector2.zero, new Vector2(1, 0)); track.GetComponent<Image>().raycastTarget = false;
                var fill = Surface("Confirmed job progress", track, Hex("53765B"), false); Stretch(fill, 0, 0, 0, 0, Vector2.zero, new Vector2(Mathf.Clamp01(job.progress), 1)); fill.GetComponent<Image>().raycastTarget = false;
            }
        }

        void AddOwnedFriendChip(RectTransform parent)
        {
            var friend = Items(_state.creatures).FirstOrDefault();
            var chip = Surface("Owned friend chip", parent, Cream);
            Stretch(chip, 14, 14, 330, 94, Vector2.zero, Vector2.zero);
            if (friend != null)
            {
                var portrait = Rect("Friend avatar", chip); Stretch(portrait, 4, 4, 76, -4, Vector2.zero, new Vector2(0, 1)); Art(portrait, friend.sprite, 72);
                var title = Label(chip, friend.name, 22, TextAnchor.MiddleLeft); Stretch(title.rectTransform, 88, 32, -10, -8);
                var copy = Label(chip, "함께하는 친구 " + Items(_state.creatures).Length + "명", 18, TextAnchor.MiddleLeft); Stretch(copy.rectTransform, 88, 7, -10, -42);
                chip.gameObject.AddComponent<Button>().onClick.AddListener(() => { _selectedDex = friend.speciesId; _selectedCreature = friend.id; Navigate("dex"); });
            }
            else
            {
                var text = Label(chip, "차 안에서 첫 친구를 만나 보세요", 21, TextAnchor.MiddleCenter); Stretch(text.rectTransform, 10, 0, -10, 0);
            }
        }

        Sprite VillageSprite(string kind)
        {
            if (_villageArt.TryGetValue(kind, out var cached)) return cached;
            var texture = Resources.Load<Texture2D>("VillageArt/" + kind);
            if (texture == null) return null;
            return _villageArt[kind] = Sprite.Create(texture, new UnityEngine.Rect(0, 0, texture.width, texture.height), new Vector2(.5f, .5f), 100, 0, SpriteMeshType.FullRect);
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
