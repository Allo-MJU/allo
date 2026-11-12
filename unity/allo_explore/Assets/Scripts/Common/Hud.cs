using Allo.Bridge;
using Allo.Critters;
using Allo.World;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace Allo
{
    /// Unity 화면 안 버튼과 짧은 안내 글. 코드로 만든다 (프리팹 없음).
    /// - 왼쪽 위 돌아가기 → Flutter 로 close
    /// - 오른쪽 위 주행 종료 (체험 주행일 때만, settings.canEndTrip) → endTrip
    /// - 오른쪽 아래 먹이 주기 → 동행 캐릭터가 사과를 먹고, Flutter 로 feed
    /// - 아직 알만 있으면 그 자리에 노래·담요 (알 돌보기 → care)
    /// - 아래 가운데 "봤어!" (창밖 친구가 보일 때만) → spotted
    /// - 위 가운데 안내 글 (Flutter 가 toast 로 보낸 문구)
    /// 글은 Flutter 가 정하고, 여기서는 버튼 이름 정도만 둔다.
    public sealed class Hud : MonoBehaviour
    {
        public Camera cam;
        public CritterDirector critters;
        public WorldDirector world;

        static readonly Color Ink = new(0.17f, 0.15f, 0.14f);
        static readonly Color Cream = new(0.99f, 0.96f, 0.9f, 0.92f);
        static readonly Color Yellow = new(1f, 0.83f, 0.31f, 0.95f);
        static readonly Color Mint = new(0.35f, 0.85f, 0.63f, 0.95f);

        Font _font;
        Sprite _pill;
        GameObject _endGo, _spotGo, _snackGo, _ballGo, _singGo, _blanketGo;
        Text _blanketLabel;
        Text _toast;
        CanvasGroup _toastGroup;
        float _toastUntil;

        void Awake()
        {
            _font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            _pill = RoundedSprite(28);
            Build();
        }

        void OnEnable()
        {
            FlutterBridge.SettingsChanged += OnSettings;
            FlutterBridge.Toasted += OnToast;
            Allo.App.AppSession.Changed += OnAppState;
            OnAppState(Allo.App.AppSession.State);
        }

        void OnDisable()
        {
            FlutterBridge.SettingsChanged -= OnSettings;
            FlutterBridge.Toasted -= OnToast;
            Allo.App.AppSession.Changed -= OnAppState;
        }

        void Start()
        {
            if (FlutterBridge.LastSettings != null) OnSettings(FlutterBridge.LastSettings);
        }

        void OnSettings(SettingsState s)
        {
            transform.Find("Canvas")?.gameObject.SetActive(!s.appMode && Allo.App.AppSession.State == null);
            if (_endGo != null) _endGo.SetActive(s.canEndTrip);
        }

        void OnAppState(Allo.App.AppState state) =>
            transform.Find("Canvas")?.gameObject.SetActive(!FlutterBridge.UsesAppPresentation);

        void OnToast(ToastState t) => Show(t.text, 2.6f);

        float _holdUntil;

        /// 다른 안내가 덮지 못하게 잠깐 붙잡아 두는 글 (알에서 태어날 때)
        public void ShowHold(string text, float seconds)
        {
            _holdUntil = 0;
            Show(text, seconds);
            _holdUntil = Time.unscaledTime + seconds;
        }

        public void Show(string text, float seconds = 2.4f)
        {
            if (_toast == null || Time.unscaledTime < _holdUntil) return;
            _toast.text = text;
            _toastGroup.alpha = 1;
            _toastUntil = Time.unscaledTime + seconds;
        }

        void Update()
        {
            if (_spotGo != null)
            {
                var show = world != null && world.Spottable != null;
                if (_spotGo.activeSelf != show) _spotGo.SetActive(show);
            }
            // 동행 없이 알만 있으면 간식·공 대신 알 돌보기 버튼
            if (critters != null && _singGo != null)
            {
                var eggMode = critters.Companion == null && (critters.HasEgg || critters.Hatching);
                if (_singGo.activeSelf != eggMode)
                {
                    _singGo.SetActive(eggMode);
                    _blanketGo.SetActive(eggMode);
                    _snackGo.SetActive(!eggMode);
                    _ballGo.SetActive(!eggMode);
                }
                if (eggMode) _blanketLabel.text = critters.EggCovered ? "담요 걷기" : "담요";
            }
            if (_toastGroup != null && _toastGroup.alpha > 0 && Time.unscaledTime > _toastUntil)
                _toastGroup.alpha = Mathf.MoveTowards(_toastGroup.alpha, 0, Time.unscaledDeltaTime * 2.5f);
        }

        void Build()
        {
            if (FindFirstObjectByType<EventSystem>() == null)
            {
                var es = new GameObject("EventSystem");
                es.transform.SetParent(transform, false);
                es.AddComponent<EventSystem>();
                es.AddComponent<StandaloneInputModule>();
            }
            var go = new GameObject("Canvas");
            go.transform.SetParent(transform, false);
            var canvas = go.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceCamera;
            canvas.worldCamera = cam != null ? cam : Camera.main;
            canvas.planeDistance = 0.1f; // 차 안 물체(머리받침)보다 앞에
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 720);
            scaler.matchWidthOrHeight = 0.5f;
            go.AddComponent<GraphicRaycaster>();
            var root = go.transform;

            Button(root, "←", new Vector2(0, 1), new Vector2(26, -26), new Vector2(64, 64), Cream, 34, FlutterBridge.RequestClose);
            _endGo = Button(root, "주행 종료", new Vector2(1, 1), new Vector2(-26, -26), new Vector2(170, 58), Cream, 26, EndTrip);
            _endGo.SetActive(false);
            _snackGo = Button(root, "간식", new Vector2(1, 0), new Vector2(-26, 26), new Vector2(150, 66), Yellow, 28, Feed);
            _ballGo = Button(root, "공", new Vector2(1, 0), new Vector2(-190, 26), new Vector2(110, 66), Mint, 28, Ball);
            _singGo = Button(root, "♪ 노래", new Vector2(1, 0), new Vector2(-26, 26), new Vector2(150, 66), Yellow, 28, Sing);
            _blanketGo = Button(root, "담요", new Vector2(1, 0), new Vector2(-190, 26), new Vector2(130, 66), Mint, 28, Blanket);
            _blanketLabel = _blanketGo.GetComponentInChildren<Text>();
            _singGo.SetActive(false);
            _blanketGo.SetActive(false);
            _spotGo = Button(root, "봤어!", new Vector2(0.5f, 0), new Vector2(0, 26), new Vector2(170, 66), Mint, 30, Spot);
            _spotGo.SetActive(false);

            var toast = Panel(root, "Toast", new Vector2(0.5f, 1), new Vector2(0, -26), new Vector2(620, 56), new Color(0.12f, 0.1f, 0.1f, 0.62f));
            _toastGroup = toast.AddComponent<CanvasGroup>();
            _toastGroup.alpha = 0;
            _toastGroup.blocksRaycasts = false;
            _toast = Label(toast.transform, "", 27, Color.white);
        }

        GameObject Button(Transform parent, string label, Vector2 anchor, Vector2 pos, Vector2 size, Color color, int fontSize, UnityEngine.Events.UnityAction onClick)
        {
            var go = Panel(parent, label, anchor, pos, size, color);
            var b = go.AddComponent<Button>();
            var colors = b.colors;
            colors.pressedColor = new Color(0.85f, 0.85f, 0.85f);
            colors.fadeDuration = 0.05f;
            b.colors = colors;
            b.onClick.AddListener(onClick);
            Label(go.transform, label, fontSize, Ink);
            return go;
        }

        GameObject Panel(Transform parent, string name, Vector2 anchor, Vector2 pos, Vector2 size, Color color)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            var rt = go.AddComponent<RectTransform>();
            rt.anchorMin = rt.anchorMax = rt.pivot = anchor;
            rt.anchoredPosition = pos;
            rt.sizeDelta = size;
            var img = go.AddComponent<Image>();
            img.sprite = _pill;
            img.type = Image.Type.Sliced;
            img.color = color;
            return go;
        }

        Text Label(Transform parent, string text, int size, Color color)
        {
            var go = new GameObject("Label");
            go.transform.SetParent(parent, false);
            var rt = go.AddComponent<RectTransform>();
            rt.anchorMin = Vector2.zero;
            rt.anchorMax = Vector2.one;
            rt.offsetMin = new Vector2(8, 2);
            rt.offsetMax = new Vector2(-8, -2);
            var t = go.AddComponent<Text>();
            t.font = _font;
            t.fontSize = size;
            t.fontStyle = FontStyle.Bold;
            t.color = color;
            t.text = text;
            t.alignment = TextAnchor.MiddleCenter;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.raycastTarget = false;
            return t;
        }

        /// 둥근 알약 모양 9분할 스프라이트 (흰색, 색은 Image.color 로)
        static Sprite RoundedSprite(int radius)
        {
            var n = radius * 2 + 8;
            var tex = new Texture2D(n, n, TextureFormat.RGBA32, false) { filterMode = FilterMode.Bilinear };
            var px = new Color[n * n];
            for (var y = 0; y < n; y++)
            for (var x = 0; x < n; x++)
            {
                var dx = Mathf.Max(0, Mathf.Abs(x + 0.5f - n / 2f) - (n / 2f - radius));
                var dy = Mathf.Max(0, Mathf.Abs(y + 0.5f - n / 2f) - (n / 2f - radius));
                var d = Mathf.Sqrt(dx * dx + dy * dy);
                px[y * n + x] = new Color(1, 1, 1, Mathf.Clamp01(radius - d + 0.5f));
            }
            tex.SetPixels(px);
            tex.Apply();
            return Sprite.Create(tex, new Rect(0, 0, n, n), new Vector2(0.5f, 0.5f), 100, 0, SpriteMeshType.FullRect, new Vector4(radius, radius, radius, radius));
        }

        void EndTrip()
        {
            FlutterBridge.Send("endTrip");
            if (_endGo != null) _endGo.SetActive(false);
            Show("주행을 마칠게요");
        }

        /// 간식을 손에 든다 (장면에 맞는 것). 화면을 톡 치거나 휙 밀면 던진다. 다시 누르면 친구 옆에 내려놓는다
        void Feed() => critters?.Hold(false);

        void Ball() => critters?.Hold(true);

        void Sing() => critters?.SingToEgg();

        void Blanket() => critters?.ToggleEggBlanket();

        void Spot()
        {
            if (world != null) world.Spot(world.Spottable);
        }
    }
}
