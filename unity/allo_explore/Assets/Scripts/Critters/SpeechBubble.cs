using UnityEngine;
using UnityEngine.UI;

namespace Allo.Critters
{
    /// 캐릭터 머리 위 말풍선. 월드 공간 캔버스라 캐릭터를 따라다니고 늘 카메라를 본다.
    /// 나타날 때 톡 커지고, 시간이 지나면 작아지며 사라진다. 캐릭터마다 하나.
    public sealed class SpeechBubble : MonoBehaviour
    {
        const float Width = 0.34f;     // m
        const float FontMeters = 0.026f;

        Transform _follow;
        float _lift;
        Text _text;
        RectTransform _rect;
        CanvasGroup _group;
        float _until, _born;
        Camera _cam;

        static Sprite _bubbleSprite;
        static Font _font;

        public bool Showing => Time.time < _until;

        public static SpeechBubble Make(Transform parent, Transform follow, float lift, Camera cam)
        {
            var go = new GameObject("SpeechBubble");
            go.transform.SetParent(parent, false);
            var b = go.AddComponent<SpeechBubble>();
            b._follow = follow; b._lift = lift; b._cam = cam;
            b.Build();
            return b;
        }

        void Build()
        {
            _font ??= Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            var canvas = gameObject.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.WorldSpace;
            canvas.worldCamera = _cam;
            canvas.sortingOrder = 50;
            _rect = GetComponent<RectTransform>();
            const float px = 1000f; // 캔버스 1m = 1000px
            _rect.sizeDelta = new Vector2(Width * px, 120);
            _rect.localScale = Vector3.one / px;
            _rect.pivot = new Vector2(0.5f, 0);

            var bg = new GameObject("Bg");
            bg.transform.SetParent(transform, false);
            var bgRect = bg.AddComponent<RectTransform>();
            bgRect.anchorMin = Vector2.zero; bgRect.anchorMax = Vector2.one; bgRect.offsetMin = bgRect.offsetMax = Vector2.zero;
            var img = bg.AddComponent<Image>();
            img.sprite = BubbleSprite();
            img.type = Image.Type.Sliced;
            img.color = new Color(1f, 0.99f, 0.95f, 0.96f);
            img.raycastTarget = false;

            var tgo = new GameObject("Text");
            tgo.transform.SetParent(transform, false);
            var tr = tgo.AddComponent<RectTransform>();
            tr.anchorMin = Vector2.zero; tr.anchorMax = Vector2.one;
            tr.offsetMin = new Vector2(18, 26); tr.offsetMax = new Vector2(-18, -12); // 아래 꼬리 자리
            _text = tgo.AddComponent<Text>();
            _text.font = _font; _text.fontSize = Mathf.RoundToInt(FontMeters * px); _text.fontStyle = FontStyle.Bold;
            _text.color = new Color(0.22f, 0.18f, 0.12f);
            _text.alignment = TextAnchor.MiddleCenter;
            _text.horizontalOverflow = HorizontalWrapMode.Wrap; _text.verticalOverflow = VerticalWrapMode.Overflow;
            _text.raycastTarget = false;
            _text.lineSpacing = 1.05f;

            _group = gameObject.AddComponent<CanvasGroup>();
            _group.alpha = 0; _group.blocksRaycasts = false; _group.interactable = false;
        }

        public void Show(string text, float seconds)
        {
            if (string.IsNullOrEmpty(text)) return;
            _text.text = text;
            // 글 줄 수에 맞춰 높이
            var lines = Mathf.Max(1, Mathf.CeilToInt(text.Length * _text.fontSize * 0.95f / (_rect.sizeDelta.x - 36)));
            _rect.sizeDelta = new Vector2(_rect.sizeDelta.x, 46 + lines * _text.fontSize * 1.25f);
            _until = Time.time + seconds;
            _born = Time.time;
            _group.alpha = 1;
        }

        public void Hide() => _until = 0;

        void LateUpdate() => Place();

        /// 캐릭터 머리 위로 옮기고 카메라를 본다 (에디터 캡처에서도 직접 부른다)
        public void Place()
        {
            if (_follow == null) { Destroy(gameObject); return; }
            var cam = _cam != null ? _cam : Camera.main;
            if (!Showing)
            {
                if (_group.alpha > 0) _group.alpha = Mathf.MoveTowards(_group.alpha, 0, Time.deltaTime * 4);
                if (_group.alpha <= 0) return;
            }
            var age = Time.time - _born;
            var pop = age < 0.25f ? 0.6f + 0.4f * Mathf.Sin(age / 0.25f * Mathf.PI * 0.5f) + Mathf.Sin(age / 0.25f * Mathf.PI) * 0.12f : 1f;
            transform.position = _follow.position + Vector3.up * _lift;
            if (cam != null)
            {
                var fwd = transform.position - cam.transform.position;
                if (fwd.sqrMagnitude > 1e-6f) transform.rotation = Quaternion.LookRotation(fwd);
                // 가까우면 조금 작게, 멀면 조금 크게 (읽히는 크기 유지)
                var d = Mathf.Clamp(fwd.magnitude, 0.35f, 2.5f);
                var k = Mathf.Lerp(0.7f, 1.6f, (d - 0.35f) / 2.15f);
                _rect.localScale = Vector3.one / 1000f * k * pop;
            }
        }

        /// 둥근 모서리 + 아래 꼬리가 있는 9분할 스프라이트
        static Sprite BubbleSprite()
        {
            if (_bubbleSprite != null) return _bubbleSprite;
            const int n = 64, r = 16, tail = 12;
            var tex = new Texture2D(n, n, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            var px = new Color[n * n];
            for (var y = 0; y < n; y++)
            for (var x = 0; x < n; x++)
            {
                var inside = false;
                if (y >= tail)
                {
                    // 둥근 사각형 (y: tail..n-1)
                    var cx = Mathf.Clamp(x, r, n - 1 - r); var cy = Mathf.Clamp(y, tail + r, n - 1 - r);
                    inside = (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r;
                }
                else
                {
                    // 꼬리: 가운데 아래로 좁아지는 삼각형
                    var half = (y / (float)tail) * 7f + 1f;
                    inside = Mathf.Abs(x - n / 2f) <= half;
                }
                px[y * n + x] = inside ? Color.white : Color.clear;
            }
            tex.SetPixels(px); tex.Apply();
            _bubbleSprite = Sprite.Create(tex, new Rect(0, 0, n, n), new Vector2(0.5f, 0), 100, 0, SpriteMeshType.FullRect,
                new Vector4(r + 2, tail + r + 2, r + 2, r + 2));
            return _bubbleSprite;
        }
    }
}
