using System;
using Allo.Critters;
using UnityEngine;
using UnityEngine.Events;
using UnityEngine.UI;

namespace Allo.App
{
    public sealed partial class AppUi
    {
        static readonly Color Ink = Hex("5C4B51"), Cream = Hex("FBF3DD"), Mint = Hex("86D6AE"), Yellow = Hex("FFD966"), Sky = Hex("DDF1FD"), CoralLight = Hex("FDE3DF"), Muted = Hex("74636A"), Disabled = Hex("DEDACD");
        static Color Hex(string value) { ColorUtility.TryParseHtmlString("#" + value, out var color); return color; }

        RectTransform Rect(string name, Transform parent)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(parent, false);
            return (RectTransform)go.transform;
        }
        static void Stretch(RectTransform rect, float left = 0, float bottom = 0, float right = 0, float top = 0, Vector2? min = null, Vector2? max = null)
        {
            rect.anchorMin = min ?? Vector2.zero; rect.anchorMax = max ?? Vector2.one;
            rect.offsetMin = new Vector2(left, bottom); rect.offsetMax = new Vector2(right, top);
        }
        RectTransform Surface(string name, Transform parent, Color color, bool border = true)
        {
            var rect = Rect(name, parent);
            var image = rect.gameObject.AddComponent<Image>();
            image.sprite = _round; image.type = Image.Type.Sliced; image.color = color;
            if (border)
            {
                var outline = rect.gameObject.AddComponent<Outline>();
                outline.effectColor = Ink; outline.effectDistance = new Vector2(2, -2); outline.useGraphicAlpha = true;
                var shadow = rect.gameObject.AddComponent<Shadow>();
                shadow.effectColor = new Color(.20f, .14f, .11f, .18f); shadow.effectDistance = new Vector2(0, -5);
            }
            return rect;
        }
        RectTransform Sheet(Transform parent, float minX = 0, float maxX = 1, bool glass = false)
        {
            var surface = Surface("Panel", parent, glass ? new Color(.984f, .953f, .867f, .93f) : Cream);
            Stretch(surface, minX == 0 ? 0 : 8, 0, maxX == 1 ? 0 : -8, 0, new Vector2(minX, 0), new Vector2(maxX, 1));
            var viewport = Rect("Viewport", surface);
            Stretch(viewport, 8, 8, -8, -8);
            viewport.gameObject.AddComponent<RectMask2D>();
            var content = Rect("Content", viewport);
            content.anchorMin = new Vector2(0, 1); content.anchorMax = Vector2.one; content.pivot = new Vector2(.5f, 1);
            content.offsetMin = Vector2.zero; content.offsetMax = Vector2.zero;
            var group = Column(content, 14);
            group.padding = new RectOffset(18, 18, 16, 22);
            var fit = content.gameObject.AddComponent<ContentSizeFitter>(); fit.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            var scroll = surface.gameObject.AddComponent<ScrollRect>();
            scroll.viewport = viewport; scroll.content = content; scroll.horizontal = false;
            scroll.movementType = ScrollRect.MovementType.Clamped; scroll.scrollSensitivity = 30;
            // Pane order is stable within each view. Confirmation sheets have their own offset.
            var key = _renderedView + (_confirmAction == null ? ":view:" : ":confirmation:") + _scrolls.Count;
            _scrolls[key] = scroll;
            return content;
        }
        VerticalLayoutGroup Column(RectTransform rect, float spacing = 12)
        {
            var g = rect.gameObject.AddComponent<VerticalLayoutGroup>();
            g.spacing = spacing; g.childControlWidth = true; g.childControlHeight = true;
            g.childForceExpandWidth = true; g.childForceExpandHeight = false;
            return g;
        }
        HorizontalLayoutGroup Row(RectTransform rect, float spacing = 12)
        {
            var g = rect.gameObject.AddComponent<HorizontalLayoutGroup>();
            g.spacing = spacing; g.childControlWidth = true; g.childControlHeight = true;
            g.childForceExpandWidth = true; g.childForceExpandHeight = false;
            g.childAlignment = TextAnchor.MiddleCenter;
            return g;
        }
        RectTransform NewRow(Transform parent, float height = 68)
        {
            var rect = Rect("Row", parent); Row(rect);
            var le = rect.gameObject.AddComponent<LayoutElement>(); le.preferredHeight = height; le.minHeight = height;
            return rect;
        }
        Text Label(Transform parent, string value, int size = 24, TextAnchor align = TextAnchor.UpperLeft)
        {
            var rect = Rect("Text", parent);
            var t = rect.gameObject.AddComponent<Text>();
            t.font = _font; t.fontSize = size; t.color = Ink; t.text = value ?? ""; t.alignment = align;
            t.horizontalOverflow = HorizontalWrapMode.Wrap; t.verticalOverflow = VerticalWrapMode.Truncate;
            t.raycastTarget = false; t.supportRichText = false;
            return t;
        }
        Text Copy(Transform parent, string value, int size = 24)
        {
            var text = Label(parent, value, size);
            var layout = text.gameObject.AddComponent<LayoutElement>();
            layout.minHeight = size * 1.35f;
            // Text provides its wrapped preferred height to the layout group.
            return text;
        }
        void Heading(Transform parent, string value) { Copy(parent, value, 32); }
        void Note(Transform parent, string value) { var text = Copy(parent, value, 22); text.color = Muted; }
        void Space(Transform parent, float size = 8)
        { var rect = Rect("Space", parent); rect.gameObject.AddComponent<LayoutElement>().preferredHeight = size; }

        Button Button(Transform parent, string value, Action action, Color color, float height = 68, bool enabled = true, int fontSize = 26)
        {
            var rect = Surface(value, parent, enabled ? color : Disabled);
            var element = rect.gameObject.AddComponent<LayoutElement>();
            element.preferredHeight = height; element.minHeight = height; element.flexibleWidth = 1; element.minWidth = 40;
            var button = rect.gameObject.AddComponent<Button>(); button.interactable = enabled;
            var colors = button.colors; colors.normalColor = Color.white; colors.highlightedColor = new Color(1, 1, 1, .93f);
            colors.pressedColor = new Color(.85f, .81f, .73f); colors.selectedColor = Color.white; colors.disabledColor = Color.white; colors.fadeDuration = .08f;
            button.colors = colors;
            button.onClick.AddListener(() => action?.Invoke());
            var text = Label(rect, value, fontSize, TextAnchor.MiddleCenter);
            text.color = enabled ? Ink : Muted; Stretch(text.rectTransform, 10, 4, -10, -4);
            return button;
        }

        void LiveEnable(Button button, Func<bool> condition, Color color)
        {
            Action check = () =>
            {
                if (button == null) return;
                var enabled = condition();
                button.interactable = enabled;
                button.GetComponent<Image>().color = enabled ? color : Disabled;
                var text = button.GetComponentInChildren<Text>();
                if (text != null) text.color = enabled ? Ink : Muted;
            };
            _liveChecks.Add(check); check();
        }

        InputField Field(Transform parent, string value, string placeholder, UnityAction<string> changed, int limit = 80, bool numeric = false)
        {
            var surface = Surface("Input: " + placeholder, parent, Color.white);
            var layout = surface.gameObject.AddComponent<LayoutElement>(); layout.preferredHeight = 68; layout.minHeight = 68;
            var field = surface.gameObject.AddComponent<InputField>();
            var text = Label(surface, "", 26, TextAnchor.MiddleLeft); text.raycastTarget = true;
            Stretch(text.rectTransform, 16, 4, -16, -4);
            var hint = Label(surface, placeholder, 24, TextAnchor.MiddleLeft); hint.color = Muted;
            Stretch(hint.rectTransform, 16, 4, -16, -4);
            field.textComponent = text; field.placeholder = hint; field.characterLimit = limit;
            field.contentType = numeric ? InputField.ContentType.IntegerNumber : InputField.ContentType.Standard;
            field.lineType = InputField.LineType.SingleLine; field.text = value; field.caretColor = Ink; field.customCaretColor = true;
            field.selectionColor = new Color(.52f, .84f, .68f, .55f); field.onValueChanged.AddListener(changed);
            field.interactable = CanAct;
            field.onEndEdit.AddListener(_ => _dirty = true);
            return field;
        }
        void Progress(Transform parent, float value, string caption)
        {
            Copy(parent, caption, 24);
            var track = Surface("Progress", parent, Disabled, false);
            var size = track.gameObject.AddComponent<LayoutElement>(); size.preferredHeight = 20; size.minHeight = 20;
            var fill = Surface("Fill", track, Mint, false);
            Stretch(fill, 0, 0, 0, 0, Vector2.zero, new Vector2(Mathf.Clamp01(value), 1));
        }
        void Art(Transform parent, string sprite, float height = 156)
        {
            if (string.IsNullOrEmpty(sprite)) return;
            var rect = Rect("Friend portrait", parent);
            if (parent.GetComponent<LayoutGroup>() == null) Stretch(rect);
            var layout = rect.gameObject.AddComponent<LayoutElement>(); layout.preferredHeight = height; layout.minHeight = height;
            var child = Rect("Artwork", rect); Stretch(child);
            var image = child.gameObject.AddComponent<RawImage>(); image.raycastTarget = false; image.color = new Color(1, 1, 1, 0);
            var fit = child.gameObject.AddComponent<AspectRatioFitter>(); fit.aspectMode = AspectRatioFitter.AspectMode.FitInParent;
            var placeholder = Label(rect, "그림 준비 중", 22, TextAnchor.MiddleCenter);
            placeholder.color = Muted; Stretch(placeholder.rectTransform);
            StartCoroutine(SpriteLoader.Load(sprite, art =>
            {
                if (image == null) return;
                image.texture = art[ArtPose.Idle]; image.color = Color.white; fit.aspectRatio = art.Aspect;
                if (placeholder != null) placeholder.gameObject.SetActive(false);
            }));
        }
        static Sprite RoundedSprite()
        {
            const int n = 64, radius = 23;
            var texture = new Texture2D(n, n, TextureFormat.RGBA32, false) { name = "ALLO UI rounded surface", filterMode = FilterMode.Bilinear };
            var pixels = new Color[n * n];
            for (var y = 0; y < n; y++) for (var x = 0; x < n; x++)
            {
                var dx = Mathf.Max(0, Mathf.Abs(x + .5f - n / 2f) - (n / 2f - radius));
                var dy = Mathf.Max(0, Mathf.Abs(y + .5f - n / 2f) - (n / 2f - radius));
                pixels[y * n + x] = new Color(1, 1, 1, Mathf.Clamp01(radius - Mathf.Sqrt(dx * dx + dy * dy) + .5f));
            }
            texture.SetPixels(pixels); texture.Apply();
            return Sprite.Create(texture, new UnityEngine.Rect(0, 0, n, n), new Vector2(.5f, .5f), 100, 0, SpriteMeshType.FullRect, new Vector4(radius, radius, radius, radius));
        }
    }
}
