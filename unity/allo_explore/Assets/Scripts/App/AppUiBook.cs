using System;
using System.Collections.Generic;
using Allo.Critters;
using UnityEngine;
using UnityEngine.UI;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        static readonly Color BookInk = Hex("493D2D"), BookMuted = Hex("756244"), BookGold = Hex("C69137"), BookPaper = Hex("F5E4C4"), BookOutline = Hex("6D533B");
        static readonly Dictionary<string, Sprite> BookItemSprites = new Dictionary<string, Sprite>();
        string _supplyTab = "materials", _selectedSupply;

        void CollectionBook(string leftTitle, string rightTitle, out RectTransform left, out RectTransform right)
        {
            var shade = Surface("Reading backdrop", _content, new Color(.10f, .14f, .11f, .88f), false);
            Stretch(shade);
            var book = Rect("Collection book", _content); Stretch(book, 34, 0, 0, 0);
            var artwork = Rect("Book art", book); Stretch(artwork);
            var image = artwork.gameObject.AddComponent<RawImage>();
            image.texture = Resources.Load<Texture2D>("Book/OpenBook"); image.raycastTarget = false;
            if (image.texture == null) image.color = BookPaper;
            BookBookmark(book, "도감", "dex", 0);
            BookBookmark(book, "가방", "inventory", 1);
            left = BookPage(book, "Left book page", leftTitle, .055f, .414f);
            right = BookPage(book, "Right book page", rightTitle, .49f, .95f);

        }

        void BookBookmark(RectTransform book, string title, string view, int index)
        {
            var active = View == view;
            var ribbon = Button(book, title, () => Navigate(view), active ? Hex("A95A35") : Hex("66734F"), 54, true, 22);
            ribbon.name = "Book bookmark " + view;
            ribbon.GetComponent<Outline>().enabled = false;
            ribbon.GetComponentInChildren<Text>().color = Hex("FFF2D5");
            var top = -48 - index * 66;
            Stretch((RectTransform)ribbon.transform, -29, top - 54, 42, top, new Vector2(0, 1), new Vector2(0, 1));
        }

        RectTransform BookPage(Transform book, string name, string title, float minX, float maxX)
        {
            var page = Rect(name, book);
            Stretch(page, 0, 0, 0, 0, new Vector2(minX, .095f), new Vector2(maxX, .91f));
            var heading = Label(page, title, 29, TextAnchor.MiddleLeft); heading.color = BookInk;
            Stretch(heading.rectTransform, 0, -43, 0, 0, new Vector2(0, 1), Vector2.one);
            var rule = Rect("Page heading rule", page); Stretch(rule, 0, -49, 0, -47, new Vector2(0, 1), Vector2.one);
            rule.gameObject.AddComponent<Image>().color = new Color(.49f, .36f, .19f, .24f);
            var viewport = Rect("Page viewport", page); Stretch(viewport, 0, 0, -12, -61);
            viewport.gameObject.AddComponent<RectMask2D>();
            // A transparent graphic lets swipes beginning on blank paper scroll the page too.
            viewport.gameObject.AddComponent<Image>().color = Color.clear;
            var content = Rect("Page content", viewport);
            content.anchorMin = new Vector2(0, 1); content.anchorMax = Vector2.one; content.pivot = new Vector2(.5f, 1);
            content.offsetMin = content.offsetMax = Vector2.zero;
            var column = Column(content, 10); column.padding = new RectOffset(4, 4, 0, 16);
            content.gameObject.AddComponent<ContentSizeFitter>().verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            var scroll = page.gameObject.AddComponent<ScrollRect>();
            scroll.viewport = viewport; scroll.content = content; scroll.horizontal = false;
            scroll.movementType = ScrollRect.MovementType.Clamped; scroll.scrollSensitivity = 30;
            var track = Rect("Page scroll indicator", page);
            Stretch(track, -7, 0, -1, -61, new Vector2(1, 0), Vector2.one);
            var trackImage = track.gameObject.AddComponent<Image>(); trackImage.color = new Color(.45f, .32f, .16f, .10f); trackImage.raycastTarget = false;
            var handle = Surface("Page scroll thumb", track, Hex("B08B51"), false); Stretch(handle);
            handle.GetComponent<Image>().raycastTarget = false;
            var scrollbar = track.gameObject.AddComponent<Scrollbar>(); scrollbar.direction = Scrollbar.Direction.BottomToTop;
            scrollbar.handleRect = handle; scrollbar.targetGraphic = handle.GetComponent<Image>();
            scrollbar.interactable = false; scrollbar.transition = Selectable.Transition.None;
            scroll.verticalScrollbar = scrollbar; scroll.verticalScrollbarVisibility = ScrollRect.ScrollbarVisibility.AutoHide;
            // Each tab owns its offset: a fitting material page reports 0, which would bottom-scroll a new food page.
            _scrolls[View + ":book:" + (View == "inventory" ? _supplyTab + ":" : "") + name] = scroll;
            return content;
        }

        Text BookCopy(Transform parent, string text, int size = 22, bool muted = false)
        {
            var label = Copy(parent, text, size); label.color = muted ? BookMuted : BookInk; return label;
        }

        Button BookButton(Transform parent, string text, Action action, bool primary = false, bool enabled = true)
        {
            var button = Button(parent, text, action, primary ? Hex("E5BC65") : Hex("EDDBB7"), 52, enabled, 21);
            button.GetComponent<Outline>().effectColor = Hex("C4AA7A");
            button.GetComponentInChildren<Text>().color = enabled ? BookInk : BookMuted;
            return button;
        }

        RectTransform BookGrid(Transform page, string name, int count, out float cellSize)
        {
            Canvas.ForceUpdateCanvases();
            var width = Mathf.Max(200, ((RectTransform)page).rect.width - 8);
            var columns = width >= 430 ? 4 : width >= 310 ? 3 : 2;
            cellSize = (width - (columns - 1) * 12) / columns;
            var grid = Rect(name, page);
            var layout = grid.gameObject.AddComponent<GridLayoutGroup>();
            var rowHeight = Mathf.Clamp(cellSize * .65f + 30, 106, 132);
            layout.cellSize = new Vector2(cellSize, rowHeight); layout.spacing = new Vector2(12, 12);
            layout.constraint = GridLayoutGroup.Constraint.FixedColumnCount; layout.constraintCount = columns;
            var rows = Mathf.CeilToInt(count / (float)columns);
            grid.gameObject.AddComponent<LayoutElement>().preferredHeight = rows * (rowHeight + 12) - (rows > 0 ? 12 : 0);
            return grid;
        }

        RectTransform BookSlot(Transform grid, string name, string caption, bool selected, Action select, string quantity = null)
        {
            var slot = Surface(name, grid, selected ? Hex("E8CD8D") : new Color(.76f, .65f, .46f, .14f), false);
            var border = slot.gameObject.AddComponent<Outline>();
            border.effectColor = selected ? BookGold : new Color(.56f, .43f, .25f, .35f);
            border.effectDistance = selected ? new Vector2(2, -2) : new Vector2(1, -1);
            var button = slot.gameObject.AddComponent<Button>(); button.onClick.AddListener(() => select());
            var colors = button.colors; colors.highlightedColor = Hex("F7E5B9"); colors.pressedColor = Hex("D9BB7D"); button.colors = colors;
            var label = Label(slot, caption, 21, TextAnchor.MiddleCenter); label.color = BookInk;
            Stretch(label.rectTransform, 2, 0, -2, 32, Vector2.zero, new Vector2(1, 0));
            if (selected)
            {
                var mark = Rect("Selected slot marker", slot); Stretch(mark, -20, -20, -8, -8, Vector2.one, Vector2.one);
                mark.gameObject.AddComponent<Image>().color = BookGold;
            }
            if (quantity != null)
            {
                var count = Label(slot, quantity, 18, TextAnchor.MiddleRight); count.color = BookInk;
                count.resizeTextForBestFit = true; count.resizeTextMinSize = 14; count.resizeTextMaxSize = 18;
                Stretch(count.rectTransform, 5, -27, -5, -3, new Vector2(0, 1), Vector2.one);
            }
            var portrait = Rect("Slot artwork", slot); Stretch(portrait, 7, 36, -7, quantity == null ? -7 : -28); return portrait;
        }

        void BookPortrait(Transform parent, string sprite, string speciesId, float height, bool faceOnly = false)
        {
            var root = Rect("Book portrait " + speciesId, parent);
            if (parent.GetComponent<LayoutGroup>() == null) Stretch(root);
            root.gameObject.AddComponent<LayoutElement>().preferredHeight = height;
            var fallback = Rect("Portrait fallback", root); Stretch(fallback);
            var icon = Rect("Portrait silhouette", fallback); Stretch(icon, 0, 0, 0, 0, new Vector2(.32f, .30f), new Vector2(.68f, .78f));
            var silhouette = icon.gameObject.AddComponent<Image>(); silhouette.sprite = NavigationIcon("dex"); silhouette.color = BookMuted; silhouette.raycastTarget = false;
            var message = Label(fallback, "그림 준비 중", 17, TextAnchor.LowerCenter); message.color = BookMuted; Stretch(message.rectTransform);
            if (string.IsNullOrEmpty(sprite)) return;
            var frame = Rect("Portrait image", root); Stretch(frame);
            var image = frame.gameObject.AddComponent<RawImage>(); image.color = Color.clear; image.raycastTarget = false;
            var fit = frame.gameObject.AddComponent<AspectRatioFitter>(); fit.aspectMode = AspectRatioFitter.AspectMode.FitInParent;
            Action<CritterArt> apply = art =>
            {
                if (image == null || art == null) return;
                image.texture = art[ArtPose.Idle]; image.uvRect = faceOnly ? FaceCrop(speciesId) : new Rect(0, 0, 1, 1);
                fit.aspectRatio = art.Aspect * image.uvRect.width / image.uvRect.height;
                image.color = Color.white; fallback.gameObject.SetActive(false);
                if (faceOnly)
                {
                    var maskImage = root.gameObject.AddComponent<Image>(); maskImage.sprite = ActionCircleSprite();
                    maskImage.preserveAspect = true; maskImage.raycastTarget = false;
                    root.gameObject.AddComponent<Mask>().showMaskGraphic = false;
                }
            };
#if UNITY_EDITOR
            apply(SpriteLoader.LoadNow(sprite));
#else
            StartCoroutine(SpriteLoader.Load(sprite, apply));
#endif
        }

        static Rect FaceCrop(string id)
        {
            switch (id)
            {
                case "road_sprout": return new Rect(.0f, .20f, .60f, .70f);
                case "puddle_pip": return new Rect(.12f, .34f, .66f, .65f);
                case "lamp_moth": return new Rect(.26f, .27f, .55f, .70f);
                case "storm_lantern": return new Rect(.29f, .43f, .58f, .56f);
                case "highway_comet": return new Rect(.33f, .32f, .64f, .68f);
                case "sea_mist": return new Rect(.21f, .21f, .62f, .78f);
                default: return new Rect(0, 0, 1, 1);
            }
        }

        void BookItemArt(Transform parent, string id, float height)
        {
            var root = Rect("Item artwork " + id, parent);
            if (parent.GetComponent<LayoutGroup>() == null) Stretch(root);
            root.gameObject.AddComponent<LayoutElement>().preferredHeight = height;
            var art = root.gameObject.AddComponent<Image>(); art.sprite = BookItemSprite(id); art.preserveAspect = true; art.raycastTarget = false;
        }

        static Sprite BookItemSprite(string id)
        {
            if (BookItemSprites.TryGetValue(id, out var cached)) return cached;
            const int size = 160;
            var pixels = new Color[size * size];
            var brown = Hex("795034"); var orange = Hex("D78A45"); var green = Hex("66834C");
            var bark = Hex("AD7544"); var endWood = Hex("E2B775"); var ring = Hex("B47D43");
            var stoneLight = Hex("A9ACA4"); var stoneDark = Hex("7D857D"); var stoneEdge = Hex("CBD0C1");
            var leafLight = Hex("829A50"); var carrotLine = Hex("AE6435");
            var berry = Hex("A75063"); var berryLight = Hex("DB8992");
            var plate = Hex("B69A6D"); var bowl = Hex("8C9D89"); var soup = Hex("E2BC69");
            var roast = Hex("B16A47"); var steam = Hex("B3A182");
            var berryCenters = new[] { new Vector2(-.23f, -.12f), new Vector2(.23f, -.12f), new Vector2(0, .19f) };
            for (var y = 0; y < size; y++) for (var x = 0; x < size; x++)
            {
                var p = new Vector2((x + .5f - size / 2f) / (size / 2f), (y + .5f - size / 2f) / (size / 2f));
                var color = Color.clear;
                if (id == "wood")
                {
                    var q = new Vector2(p.x * .92f + p.y * .39f, p.y * .92f - p.x * .39f);
                    BookPaint(Mathf.Max(Mathf.Abs(q.x) - .57f, Mathf.Abs(q.y) - .29f), brown, ref color);
                    BookPaint(Mathf.Max(Mathf.Abs(q.x + .02f) - .51f, Mathf.Abs(q.y - .04f) - .20f), bark, ref color);
                    if (Mathf.Abs(q.x) < .48f && (Mathf.Abs(q.y - .12f) < .018f || Mathf.Abs(q.y + .08f) < .018f)) color = brown;
                    var end = new Vector2((q.x - .48f) / .18f, q.y / .30f).magnitude;
                    BookPaint((end - 1) * .18f, endWood, ref color);
                    if (end < .76f && end > .60f) color = ring;
                }
                else if (id == "stone")
                {
                    var d = Mathf.Max(Mathf.Abs(p.x + p.y * .20f) * .87f + Mathf.Abs(p.y) * .40f - .59f, Mathf.Abs(p.y) - .43f);
                    BookPaint(d, p.y > p.x * .33f ? stoneLight : stoneDark, ref color);
                    if (d < -.05f && Mathf.Abs(p.y - p.x * .33f) < .014f) color = stoneEdge;
                }
                else if (id == "ingredient")
                {
                    BookPaint(new Vector2((p.x + .09f) / .38f, (p.y + .12f) / .54f).magnitude * .38f - .38f, orange, ref color);
                    BookPaint(new Vector2((p.x - .12f) / .14f, (p.y - .45f) / .26f).magnitude * .14f - .14f, green, ref color);
                    BookPaint(new Vector2((p.x + .12f) / .18f, (p.y - .43f) / .22f).magnitude * .18f - .18f, leafLight, ref color);
                    if (p.x > -.24f && p.x < .05f && (Mathf.Abs(p.y - .05f) < .02f || Mathf.Abs(p.y + .18f) < .02f)) color = carrotLine;
                }
                else if (id == "berry_snack" || id == "snack")
                {
                    foreach (var center in berryCenters)
                    {
                        BookPaint(Vector2.Distance(p, center) - .27f, berry, ref color);
                        BookPaint(Vector2.Distance(p, center + new Vector2(-.07f, .08f)) - .07f, berryLight, ref color, false);
                    }
                    BookPaint(new Vector2((p.x - .15f) / .26f, (p.y - .49f) / .12f).magnitude * .12f - .12f, green, ref color);
                }
                else
                {
                    var feast = id == "picnic_feast";
                    BookPaint(new Vector2(p.x / .68f, (p.y + .35f) / .15f).magnitude * .15f - .15f, plate, ref color);
                    if (p.y < .12f) BookPaint(new Vector2(p.x / .53f, p.y / .43f).magnitude * .43f - .43f, bowl, ref color);
                    BookPaint(new Vector2(p.x / .58f, (p.y - .12f) / .18f).magnitude * .18f - .18f, soup, ref color);
                    BookPaint(Vector2.Distance(p, new Vector2(-.17f, .14f)) - .09f, feast ? roast : orange, ref color, false);
                    BookPaint(Vector2.Distance(p, new Vector2(.19f, .12f)) - .07f, green, ref color, false);
                    if (p.y > .37f && p.y < .69f && Mathf.Abs(p.x + .12f + Mathf.Sin(p.y * 14) * .04f) < .025f) color = steam;
                }
                pixels[y * size + x] = color;
            }
            var texture = new Texture2D(size, size, TextureFormat.RGBA32, false) { name = "Book item " + id, filterMode = FilterMode.Bilinear };
            texture.SetPixels(pixels); texture.Apply(false, true);
            var sprite = Sprite.Create(texture, new Rect(0, 0, size, size), new Vector2(.5f, .5f), size);
            return BookItemSprites[id] = sprite;
        }

        static void BookPaint(float distance, Color fill, ref Color pixel, bool outlined = true)
        {
            if (distance > .025f) return;
            pixel = outlined && distance > -.015f ? BookOutline : fill;
            pixel.a *= Mathf.Clamp01((.025f - distance) * 160);
        }

        static string BookAttributeLabel(string value) => value == "normal" ? "일반" : value == "dark" ? "어둠" : AttributeLabel(value);

        static string MaterialUse(string id) => id == "wood" ? "시설을 짓고 친구의 행동을 훈련할 때 쓰는 재료예요." : id == "stone" ? "시설을 짓거나 업그레이드할 때 쓰는 재료예요." : id == "ingredient" ? "주방에서 친구에게 줄 요리를 만들 때 쓰는 재료예요." : "여행과 관찰로 모은 보급품이에요.";
    }
}
