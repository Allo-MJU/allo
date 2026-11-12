using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        bool _campDetail;
        readonly Dictionary<string, Sprite> _villageArt = new Dictionary<string, Sprite>();

        void OpenVillageFacility(string id)
        {
            if (!CanAct) return;
            _facility = id;
            var facility = Items(_state.facilities).FirstOrDefault(f => f.id == id);
            _campTab = facility != null && facility.level == 0 ? "builder" : id == "kitchen" ? "cook" : id == "training" ? "trainer" : "builder";
            _campDetail = true;
            if (View == "camp") _dirty = true;
            else Send("navigate", new AppAction { view = "camp" });
        }

        void BuildVillageMap(float minX, bool home)
        {
            var root = Rect("Village overview", _content);
            Stretch(root, minX > 0 ? 8 : 0, 0, 0, 0, new Vector2(minX, 0), Vector2.one);
            var resources = Rect("Village resources", root);
            Stretch(resources, 0, -58, 0, 0, new Vector2(0, 1), Vector2.one);
            Row(resources, 12);
            foreach (var material in Items(_state.materials))
            {
                var pill = Button(resources, material.label + "  " + material.count, () => Navigate("inventory"), Cream, 54, CanAct, 26);
                pill.gameObject.name = "Resource " + material.id;
            }
            if (Items(_state.materials).Length == 0)
            {
                var text = Label(resources, "보급품을 확인하고 있어요", 24, TextAnchor.MiddleCenter);
                text.gameObject.AddComponent<LayoutElement>().flexibleWidth = 1;
            }

            var map = Surface("Village map", root, Hex("B8D9A6"));
            Stretch(map, 0, 52, 0, -72);
            map.gameObject.AddComponent<RectMask2D>();
            var meadow = Surface("Village meadow", map, Hex("D0E6AD"), false);
            Stretch(meadow, 12, 14, -12, -12);
            var center = MapPart(map, "Village clearing", .5f, .35f, .86f, .53f, Hex("DCE9B8"));
            center.GetComponent<Image>().raycastTarget = false;
            // All scenery is UI illustration; no scene camera or 3D world is involved.
            MapPart(map, "Main village path", .5f, .22f, 1.08f, .115f, Hex("E8D3A3"));
            MapPart(map, "Workshop path", .19f, .38f, .065f, .36f, Hex("E8D3A3"));
            MapPart(map, "Kitchen path", .5f, .38f, .065f, .36f, Hex("E8D3A3"));
            MapPart(map, "Training path", .81f, .38f, .065f, .36f, Hex("E8D3A3"));
            MapPart(map, "Path center", .50f, .225f, .15f, .16f, Hex("F4E1B9"));
            AddTree(map, .035f, .81f, .11f); AddTree(map, .96f, .80f, .12f);
            AddTree(map, .045f, .30f, .095f); AddTree(map, .95f, .31f, .10f);
            AddTree(map, .355f, .83f, .075f); AddTree(map, .65f, .85f, .085f);
            for (var i = 0; i < 16; i++)
            {
                var x = .055f + (i * .137f) % .88f;
                var y = i % 2 == 0 ? .075f : .94f;
                MapPart(map, "Meadow flower", x, y, .006f, .013f, i % 3 == 0 ? Hex("F5BDA6") : Hex("FFF0BA"));
            }
            string[] ids = { "workshop", "kitchen", "training" };
            for (var i = 0; i < ids.Length; i++) BuildFacilityNode(map, ids[i], .19f + .31f * i, home);
            AddVillageFriends(map);

            var summary = Surface("Village activity summary", root, Cream, false);
            Stretch(summary, 0, 0, 0, 42, Vector2.zero, new Vector2(1, 0));
            var jobs = Items(_state.jobs);
            var line = jobs.Length == 0 ? "시설을 눌러 건설 · 요리 · 훈련을 시작해요." : string.Join("   /   ", jobs.Select(j => j.label + " · " + TimeLabel(j.remainingSec)));
            var caption = Label(summary, line, home ? 21 : 23, TextAnchor.MiddleCenter);
            Stretch(caption.rectTransform, 12, 0, -12, 0);
        }

        void BuildFacilityNode(RectTransform map, string id, float x, bool compact)
        {
            var facility = Items(_state.facilities).FirstOrDefault(f => f.id == id);
            var role = id == "kitchen" ? "cook" : id == "training" ? "trainer" : "builder";
            var node = Rect("Facility node " + id, map);
            Stretch(node, 0, 0, 0, 0, new Vector2(x - .14f, .14f), new Vector2(x + .14f, .87f));
            var hit = node.gameObject.AddComponent<Image>(); hit.color = Color.clear;
            var button = node.gameObject.AddComponent<Button>(); button.interactable = CanAct && facility != null;
            button.onClick.AddListener(() => OpenVillageFacility(id));
            var art = Rect("Building illustration", node);
            Stretch(art, 0, 70, 0, -8);
            var image = art.gameObject.AddComponent<Image>();
            image.sprite = VillageSprite(id, facility != null ? facility.level : 0); image.preserveAspect = true; image.raycastTarget = false;
            var label = Surface("Facility name and level", node, facility != null && facility.level > 0 ? Cream : Hex("F0E5CB"));
            Stretch(label, -4, 29, 4, 81, Vector2.zero, new Vector2(1, 0));
            label.GetComponent<Image>().raycastTarget = false;
            button.targetGraphic = label.GetComponent<Image>();
            var title = Label(label, (facility?.label ?? (id == "workshop" ? "작업장" : id == "kitchen" ? "주방" : "훈련장")) + "  Lv." + (facility != null ? facility.level.ToString() : "?"), compact ? 24 : 28, TextAnchor.MiddleCenter);
            Stretch(title.rectTransform, 4, 0, -4, 0);
            var assignment = Assignment(role);
            var worker = string.IsNullOrEmpty(assignment) ? RoleLabel(role) + " 미배정" : CreatureName(assignment);
            var workerText = Label(node, worker, compact ? 19 : 22, TextAnchor.MiddleCenter);
            Stretch(workerText.rectTransform, -15, -2, 15, 29, Vector2.zero, new Vector2(1, 0));
            var jobs = Items(_state.jobs).Where(j => (j.role == role && (role != "builder" || j.targetId == id)) || (j.role == "builder" && j.targetId == id)).ToArray();
            var status = facility == null ? "정보 확인 중" : jobs.Length > 0 ? string.Join(" · ", jobs.Select(j => j.role == "builder" ? "건설 중" : j.role == "cook" ? "요리 중" : "훈련 중")) + "  " + TimeLabel(jobs.Min(j => j.remainingSec)) : facility.level == 0 ? "미건설 · 눌러서 짓기" : string.IsNullOrEmpty(assignment) ? "친구를 정해 주세요" : "함께할 준비가 됐어요";
            var bubble = Surface("Facility work status", node, jobs.Length > 0 ? Mint : Cream, false);
            Stretch(bubble, -8, -20, 8, 28, new Vector2(0, 1), Vector2.one);
            bubble.GetComponent<Image>().raycastTarget = false;
            var statusText = Label(bubble, status, compact ? 18 : 21, TextAnchor.MiddleCenter);
            Stretch(statusText.rectTransform, 6, 0, -6, 0);
            if (jobs.Length > 0)
            {
                var track = Surface("Facility work progress", node, Hex("E8D3A3"), false);
                Stretch(track, 12, 79, -12, 86, Vector2.zero, new Vector2(1, 0));
                track.GetComponent<Image>().raycastTarget = false;
                var fill = Surface("Confirmed job progress", track, Ink, false);
                Stretch(fill, 0, 0, 0, 0, Vector2.zero, new Vector2(Mathf.Clamp01(jobs[0].progress), 1)); fill.GetComponent<Image>().raycastTarget = false;
            }
        }

        void AddVillageFriends(RectTransform map)
        {
            var friends = Items(_state.creatures).Take(3).ToArray();
            for (var i = 0; i < friends.Length; i++)
            {
                var friend = friends[i];
                var portrait = Rect("Village friend " + friend.id, map);
                Stretch(portrait, 0, 0, 0, 0, new Vector2(.28f + i * .19f, .005f), new Vector2(.36f + i * .19f, .135f));
                Art(portrait, friend.sprite, 60);
                var hit = portrait.gameObject.AddComponent<Image>(); hit.color = Color.clear;
                var button = portrait.gameObject.AddComponent<Button>(); button.interactable = CanAct;
                button.onClick.AddListener(() => { _selectedDex = friend.speciesId; _selectedCreature = friend.id; Navigate("dex"); });
            }
        }

        RectTransform MapPart(Transform parent, string name, float x, float y, float w, float h, Color color)
        {
            var rect = Surface(name, parent, color, false);
            Stretch(rect, 0, 0, 0, 0, new Vector2(x - w / 2, y - h / 2), new Vector2(x + w / 2, y + h / 2));
            rect.GetComponent<Image>().raycastTarget = false;
            return rect;
        }
        void AddTree(Transform parent, float x, float y, float width)
        {
            var rect = MapPart(parent, "Village tree", x, y, width, width * 1.8f, Color.white);
            var image = rect.GetComponent<Image>(); image.sprite = VillageSprite("tree", 0); image.type = Image.Type.Simple; image.preserveAspect = true;
        }
        Sprite VillageSprite(string kind, int level)
        {
            var key = kind + ":" + level;
            if (_villageArt.TryGetValue(key, out var cached)) return cached;
            var painter = new VillagePainter();
            if (kind == "tree") painter.Tree(); else painter.Building(kind, level);
            return _villageArt[key] = painter.Finish(key);
        }

        // Small authored raster illustrations, cached per building and confirmed level.
        sealed class VillagePainter
        {
            const int W = 384, H = 320;
            readonly Color[] _pixels = new Color[W * H];
            readonly Color _ink = Hex("70574F"), _wood = Hex("AD7C57"), _cream = Hex("FFF2CE");
            void Pixel(int x, int y, Color c) { if (x >= 0 && x < W && y >= 0 && y < H) _pixels[y * W + x] = c; }
            void Box(float x, float y, float w, float h, Color c)
            { for (var py = Mathf.Max(0, (int)y); py < Mathf.Min(H, y + h); py++) for (var px = Mathf.Max(0, (int)x); px < Mathf.Min(W, x + w); px++) Pixel(px, py, c); }
            void Oval(float x, float y, float rx, float ry, Color c)
            {
                for (var py = Mathf.Max(0, (int)(y - ry - 1)); py < Mathf.Min(H, y + ry + 1); py++)
                for (var px = Mathf.Max(0, (int)(x - rx - 1)); px < Mathf.Min(W, x + rx + 1); px++)
                {
                    var d = Mathf.Sqrt((px - x) * (px - x) / (rx * rx) + (py - y) * (py - y) / (ry * ry));
                    if (d <= 1) Pixel(px, py, c);
                }
            }
            void Line(float ax, float ay, float bx, float by, float width, Color c)
            {
                var distance = Vector2.Distance(new Vector2(ax, ay), new Vector2(bx, by));
                for (var i = 0; i <= Mathf.CeilToInt(distance); i++)
                { var t = distance == 0 ? 0 : i / distance; Oval(Mathf.Lerp(ax, bx, t), Mathf.Lerp(ay, by, t), width / 2, width / 2, c); }
            }
            void Poly(Color c, params Vector2[] points)
            {
                var minX = Mathf.Max(0, Mathf.FloorToInt(points.Min(p => p.x))); var maxX = Mathf.Min(W - 1, Mathf.CeilToInt(points.Max(p => p.x)));
                var minY = Mathf.Max(0, Mathf.FloorToInt(points.Min(p => p.y))); var maxY = Mathf.Min(H - 1, Mathf.CeilToInt(points.Max(p => p.y)));
                for (var y = minY; y <= maxY; y++) for (var x = minX; x <= maxX; x++)
                {
                    var inside = false;
                    for (int i = 0, j = points.Length - 1; i < points.Length; j = i++)
                        if ((points[i].y > y) != (points[j].y > y) && x < (points[j].x - points[i].x) * (y - points[i].y) / (points[j].y - points[i].y) + points[i].x) inside = !inside;
                    if (inside) Pixel(x, y, c);
                }
                for (var i = 0; i < points.Length; i++) Line(points[i].x, points[i].y, points[(i + 1) % points.Length].x, points[(i + 1) % points.Length].y, 5, _ink);
            }
            void FramedBox(float x, float y, float w, float h, Color c)
            { Box(x - 3, y - 3, w + 6, h + 6, _ink); Box(x, y, w, h, c); }
            void Window(float x, float y)
            {
                FramedBox(x, y, 40, 42, Hex("BFE5DC"));
                Line(x + 20, y, x + 20, y + 42, 4, _wood); Line(x, y + 20, x + 40, y + 20, 4, _wood);
                Box(x - 5, y - 7, 50, 7, _wood);
            }
            public void Tree()
            {
                Oval(192, 35, 102, 20, Hex("8BB78C"));
                Line(192, 44, 192, 191, 25, _ink); Line(192, 46, 192, 189, 17, _wood);
                Oval(192, 205, 111, 93, _ink); Oval(192, 208, 106, 88, Hex("76B98D"));
                Oval(132, 210, 62, 59, Hex("8ACC9C")); Oval(223, 249, 62, 54, Hex("A4D5A0"));
                Line(187, 104, 153, 140, 10, _wood); Line(196, 128, 228, 160, 10, _wood);
            }
            public void Building(string kind, int level)
            {
                var accent = kind == "kitchen" ? Hex("DE9980") : kind == "training" ? Hex("91BCCD") : Hex("8BC6AC");
                Oval(192, 30, 157, 23, Hex("92B88F"));
                if (level <= 0)
                {
                    Poly(Hex("D5C6A4"), new Vector2(55, 34), new Vector2(281, 34), new Vector2(331, 67), new Vector2(106, 67));
                    for (var i = 0; i < 4; i++)
                    { var x = 65 + i * 72; Box(x, 45, 12, 60, _wood); Box(x - 4, 96, 20, 8, _cream); }
                    Line(71, 80, 287, 80, 8, _wood);
                    FramedBox(111, 108, 160, 111, _cream); Box(184, 51, 14, 57, _wood);
                    Poly(accent, new Vector2(137, 156), new Vector2(190, 199), new Vector2(244, 156));
                    FramedBox(149, 123, 85, 34, Hex("E0D8BB")); Box(182, 123, 18, 28, _wood);
                    Box(54, 108, 43, 10, _wood); Box(49, 120, 45, 10, Hex("C7A67A"));
                    return;
                }
                if (level >= 2)
                {
                    FramedBox(272, 49, 65, 100, Hex("E5D7AE"));
                    Poly(accent, new Vector2(258, 144), new Vector2(298, 191), new Vector2(349, 144));
                    FramedBox(293, 77, 23, 35, Hex("BFE5DC"));
                }
                FramedBox(87, 50, 195, 151, _cream);
                Box(92, 54, 185, 15, Hex("DCC69B"));
                Box(253, 57, 24, 139, Hex("E9D6AD"));
                if (kind == "kitchen")
                {
                    FramedBox(240, 211, 27, 59, Hex("B68B74"));
                    Oval(257, 285, 17, 12, Hex("F4F2D9")); Oval(276, 305, 24, 14, Hex("F4F2D9"));
                }
                Poly(accent, new Vector2(65, 190), new Vector2(184, 278), new Vector2(303, 190));
                Line(80, 188, 292, 188, 11, _wood);
                Line(96, 212, 270, 212, 3, new Color(1, 1, 1, .7f));
                Line(128, 235, 240, 235, 3, new Color(1, 1, 1, .7f));
                FramedBox(163, 50, 48, 80, _wood); Oval(199, 89, 4, 4, Hex("FFE19A"));
                Window(103, 108); Window(226, 108);
                FramedBox(150, 143, 74, 27, Hex("F5D99A"));
                if (kind == "workshop")
                {
                    Line(174, 148, 197, 165, 8, _wood); Line(178, 164, 188, 151, 6, _ink);
                    Box(45, 50, 32, 14, _wood); Box(39, 68, 43, 12, Hex("CDA97D"));
                }
                else if (kind == "kitchen")
                {
                    Oval(187, 155, 17, 9, Hex("C68A6D")); Line(170, 153, 204, 153, 4, _ink);
                    for (var i = 0; i < 5; i++) Box(93 + i * 37, 99, 18, 19, Hex("E9AD97"));
                }
                else
                {
                    Line(316, 50, 316, 245, 8, _wood);
                    Poly(Hex("94C7DA"), new Vector2(318, 237), new Vector2(368, 219), new Vector2(318, 196));
                    Oval(187, 156, 10, 10, accent); Line(181, 150, 195, 165, 4, _ink);
                }
                if (level >= 3)
                {
                    FramedBox(165, 212, 39, 39, Hex("F6E2AD")); Oval(185, 233, 13, 13, Hex("BFE5DC"));
                    Line(185, 220, 185, 246, 3, _wood);
                    for (var i = 0; i < 4; i++) { Line(68 + i * 80, 41, 68 + i * 80, 68, 4, Hex("76A975")); Oval(68 + i * 80, 69, 7, 7, Hex("E6A195")); }
                }
            }
            public Sprite Finish(string name)
            {
                var texture = new Texture2D(W, H, TextureFormat.RGBA32, false) { name = "ALLO village " + name, filterMode = FilterMode.Bilinear, wrapMode = TextureWrapMode.Clamp };
                texture.SetPixels(_pixels); texture.Apply();
                return Sprite.Create(texture, new UnityEngine.Rect(0, 0, W, H), new Vector2(.5f, .5f), 100);
            }
        }
    }
}
