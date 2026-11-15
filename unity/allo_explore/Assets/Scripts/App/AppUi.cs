using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace Allo.App
{
    /// Landscape application chrome. Game state is owned by the host, never by this view.
    public sealed partial class AppUi : MonoBehaviour
    {
        RectTransform _safe, _content, _bookBackdrop;
        bool _lastStoryUiBlocked, _lastLearningUiBlocked;
        public bool CabinGesturesBlocked => StoryUiBlocked || _nativeSpeechHidden || _state?.learning?.recording == true;
        public bool StoryUiBlocked => View == "cabin" && (_speechDrawer || _zoneDrawer || _confirmAction != null);
        Text _title, _connection, _status;
        Button _pairingTitle;
        Image _statusSurface;
        Font _font;
        Sprite _round;
        AppState _state;
        bool _dirty = true;
        string _renderedView, _selectedCreature, _selectedDex, _campTab = "builder", _selectedTarget;
        string _sessionId = "", _pairCode = "", _speech = "";
        string _confirmTitle, _confirmDescription;
        Action _confirmAction;
        readonly Dictionary<string, float> _scrollPositions = new Dictionary<string, float>();
        readonly Dictionary<string, Text> _resourceTexts = new Dictionary<string, Text>();
        readonly Dictionary<string, Button> _nav = new Dictionary<string, Button>();
        readonly Dictionary<string, string> _workers = new Dictionary<string, string>();
        readonly List<Action> _liveChecks = new List<Action>();
        Rect _lastSafe;
        Vector2Int _lastScreen;
        readonly Dictionary<string, ScrollRect> _scrolls = new Dictionary<string, ScrollRect>();

        void Awake()
        {
            _font = Resources.Load<Font>("Fonts/DoHyeon-Regular");
            if (_font == null) _font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            _round = RoundedSprite();
            BuildChrome();
        }

        void OnEnable()
        {
            AppSession.Changed += OnState;
            Allo.Critters.CritterDirector.CompanionTapped += OnCompanionTapped;
            OnState(AppSession.State);
        }

        void OnDisable() { AppSession.Changed -= OnState; Allo.Critters.CritterDirector.CompanionTapped -= OnCompanionTapped; }
        void OnApplicationPause(bool paused) { OnCompanionForegroundChanged(!paused); }
        void OnApplicationFocus(bool focused) { OnCompanionForegroundChanged(focused); }
        void OnState(AppState state)
        {
            if (state != null && state.view == "cabin" &&
                (!state.connected || state.egg?.active != true || _state?.egg?.id != state.egg?.id))
            {
                // An expired or replaced egg no longer owns its drawer or discard confirmation.
                _speechDrawer = _zoneDrawer = false;
                _confirmAction = null; _confirmTitle = null; _confirmDescription = null;
            }
            OnLearningTargetChanged(state);
            SyncNativeCompanionSpeech(state);
            SyncVillageCharacter(state);
            SyncVillageSelection(state);
            SyncQuestCard(state);
            _state = state; _dirty = true;
            if (_villageLayer != null) _villageLayer.gameObject.SetActive(state != null && state.ready && (state.view == "home" || state.view == "camp"));
        }

        void LateUpdate()
        {
            ApplySafeArea();
            // Window-story experiments remain standalone; this app owns direct conversation only.
            var storyBlocked = StoryUiBlocked;
            if (storyBlocked != _lastStoryUiBlocked)
            {
                _lastStoryUiBlocked = storyBlocked;
                AppSession.Request("storyUiBlocked", new AppAction { blocked = storyBlocked });
            }
            var learningBlocked = StoryUiBlocked;
            if (learningBlocked != _lastLearningUiBlocked)
            {
                _lastLearningUiBlocked = learningBlocked;
                AppSession.Request("learningUiBlocked", new AppAction { blocked = learningBlocked });
            }
            UpdateVillageGeometry();
            TickVillageFriends(Time.unscaledDeltaTime);
            PlaceCompanionBubble();
            foreach (var check in _liveChecks) check();
            if (!_dirty || _safe == null) return;
            UpdateChrome();
            // Snapshot ticks must not tear down a focused keyboard field or an active drag.
            var selected = EventSystem.current != null ? EventSystem.current.currentSelectedGameObject : null;
            var input = selected != null ? selected.GetComponent<InputField>() : null;
            if (input != null && input.isFocused && _renderedView == View) return;
            if (Input.GetMouseButton(0) || Input.touchCount > 0) return;
            Render();
            PlaceCompanionBubble();
        }

        void BuildChrome()
        {
            if (FindFirstObjectByType<EventSystem>() == null)
            {
                var es = new GameObject("AppEventSystem", typeof(EventSystem), typeof(StandaloneInputModule));
                es.transform.SetParent(transform, false);
            }
            var canvasGo = new GameObject("Application UI", typeof(RectTransform), typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            canvasGo.transform.SetParent(transform, false);
            var canvas = canvasGo.GetComponent<Canvas>(); canvas.renderMode = RenderMode.ScreenSpaceOverlay; canvas.sortingOrder = 100;
            var scaler = canvasGo.GetComponent<CanvasScaler>(); scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1600, 720); scaler.matchWidthOrHeight = 1;
            _safe = Rect("Safe area", canvasGo.transform); Stretch(_safe);
            _bookBackdrop = Rect("Camp reading backdrop", canvasGo.transform); Stretch(_bookBackdrop);
            _bookBackdrop.SetAsFirstSibling();
            var landscape = Rect("Reading village landscape", _bookBackdrop); Stretch(landscape);
            var landscapeImage = landscape.gameObject.AddComponent<RawImage>();
            landscapeImage.texture = Resources.Load<Texture2D>("VillageArt/background");
            landscapeImage.color = new Color(.45f, .45f, .45f, 1); landscapeImage.raycastTarget = false;
            if (landscapeImage.texture != null)
            {
                var fit = landscape.gameObject.AddComponent<AspectRatioFitter>();
                fit.aspectMode = AspectRatioFitter.AspectMode.EnvelopeParent;
                fit.aspectRatio = (float)landscapeImage.texture.width / landscapeImage.texture.height;
            }
            _bookBackdrop.gameObject.SetActive(false);
            var header = Surface("Compact application HUD", _safe, new Color(.07f, .12f, .10f, .68f), false);
            Stretch(header, 0, -62, 0, -8, new Vector2(0, 1), Vector2.one);
            var crest = Button(header, "ALLO", () => Navigate("home"), Color.clear, 40, true, 24);
            Stretch((RectTransform)crest.transform, 10, 7, 110, -7, Vector2.zero, new Vector2(0, 1)); crest.GetComponent<Outline>().enabled = false; _nav["home"] = crest;
            _title = Label(header, "우리의 마을", 24, TextAnchor.MiddleLeft); _title.color = Cream; Stretch(_title.rectTransform, 124, 0, -780, 0);
            _pairingTitle = Button(header, "차량 QR 연결하기", () => Navigate("pairing"), new Color(1, 1, 1, .10f), 44, true, 22);
            Stretch((RectTransform)_pairingTitle.transform, 124, 7, 382, -7, Vector2.zero, new Vector2(0, 1));
            SmoothCabinSurface(_pairingTitle.GetComponent<Image>());
            _pairingTitle.GetComponent<Outline>().enabled = false;
            _pairingTitle.GetComponentInChildren<Text>().color = Cream;
            var balances = Rect("Material HUD", header); Stretch(balances, -700, 7, -180, -7, new Vector2(1, 0), Vector2.one); Row(balances, 8);
            foreach (var id in new[] { "wood", "stone", "ingredient" })
            {
                var pill = Button(balances, "—", () => Navigate("inventory"), new Color(0, 0, 0, .20f), 40, true, 20);
                pill.GetComponent<Outline>().enabled = false;
                _resourceTexts[id] = pill.GetComponentInChildren<Text>(); _resourceTexts[id].color = Cream;
            }
            var connection = Surface("Connection chip", header, new Color(0, 0, 0, .20f), false);
            Stretch(connection, -170, 7, -10, -7, new Vector2(1, 0), Vector2.one);
            _connection = Label(connection, "연결 확인 중", 18, TextAnchor.MiddleCenter); _connection.color = Cream; Stretch(_connection.rectTransform, 4, 0, -4, 0);
            connection.gameObject.AddComponent<Button>().onClick.AddListener(() => Navigate("settings"));
            _content = Rect("Screen", _safe); Stretch(_content, 14, 20, -126, -78);
            var rail = Rect("Village action rail", _safe);
            Stretch(rail, -108, 16, -8, -78, new Vector2(1, 0), Vector2.one);
            var railLayout = Column(rail, 8); railLayout.childAlignment = TextAnchor.MiddleCenter;
            string[] ids = { "cabin", "camp", "dex", "inventory", "settings" };
            string[] labels = { "차 안", "시설", "도감", "가방", "설정" };
            for (var i = 0; i < ids.Length; i++)
            {
                var id = ids[i];
                var button = Button(rail, labels[i], () => Navigate(id), Color.clear, 56, true, 19);
                var layout = button.GetComponent<LayoutElement>(); layout.minHeight = layout.preferredHeight = 94;
                button.GetComponent<Outline>().enabled = false;
                var text = button.GetComponentInChildren<Text>(); text.color = Cream;
                Stretch(text.rectTransform, 0, 0, 0, 24, Vector2.zero, new Vector2(1, 0));
                var circle = Surface("Action circle", button.transform, new Color(.07f, .12f, .10f, .78f), false);
                circle.anchorMin = circle.anchorMax = new Vector2(.5f, .65f); circle.sizeDelta = new Vector2(64, 64);
                circle.GetComponent<Image>().sprite = ActionCircleSprite(); circle.GetComponent<Image>().type = Image.Type.Simple;
                var ring = circle.gameObject.AddComponent<Outline>(); ring.effectColor = Yellow; ring.effectDistance = new Vector2(1.5f, -1.5f); ring.enabled = false;
                button.targetGraphic = circle.GetComponent<Image>();
                var icon = Rect("Navigation icon", circle); icon.anchorMin = icon.anchorMax = new Vector2(.5f, .5f); icon.sizeDelta = new Vector2(30, 30);
                var image = icon.gameObject.AddComponent<Image>(); image.sprite = NavigationIcon(id); image.color = Cream; image.raycastTarget = false;
                _nav[id] = button;
            }
            var status = Surface("Context toast", _safe, Cream);
            Stretch(status, -430, -124, 430, -76, new Vector2(.5f, 1), new Vector2(.5f, 1));
            _statusSurface = status.GetComponent<Image>();
            _status = Label(status, "", 21, TextAnchor.MiddleCenter); Stretch(_status.rectTransform, 16, 2, -16, -2);
            status.gameObject.SetActive(false);
            ApplySafeArea();
        }

        void ApplySafeArea()
        {
            var screen = new Vector2Int(Screen.width, Screen.height);
            var safe = Screen.safeArea;
            if (_safe == null || screen.x <= 0 || screen.y <= 0 || (safe == _lastSafe && screen == _lastScreen)) return;
            _lastSafe = safe; _lastScreen = screen;
            _safe.anchorMin = new Vector2(safe.xMin / screen.x, safe.yMin / screen.y);
            _safe.anchorMax = new Vector2(safe.xMax / screen.x, safe.yMax / screen.y);
            _safe.offsetMin = _safe.offsetMax = Vector2.zero;
        }

        void UpdateChrome()
        {
            var view = View;
            _bookBackdrop.gameObject.SetActive(view == "dex" || view == "inventory");
            var emptyCabin = view == "cabin" && _state != null && _state.ready && !_state.connected;
            _title.transform.parent.gameObject.SetActive(true);
            _nav["cabin"].transform.parent.gameObject.SetActive(true);
            _title.gameObject.SetActive(view != "cabin");
            _pairingTitle.gameObject.SetActive(view == "cabin");
            _pairingTitle.interactable = CanAct;
            _title.text = view == "home" ? "우리의 마을" : ViewTitle(view);
            var s = _state;
            _connection.text = s == null || !s.ready ? "불러오는 중" : s.busy ? "처리 중" : s.sessionEnded ? "여행 종료" : s.isDemo ? (s.connected ? "테스트 연결됨" : "체험 모드") : s.connected ? "차량 연결" : "연결하기";
            _connection.color = Cream;
            var error = s != null && !string.IsNullOrEmpty(s.error);
            _statusSurface.color = error ? CoralLight : s != null && s.busy ? Sky : Cream;
            _status.text = s == null || !s.ready ? "마을을 불러오고 있어요." : error ? ErrorLabel(s.error) : s.busy ? "처리 중이에요. 잠시 기다려 주세요." : s.notice ?? "";
            _statusSurface.gameObject.SetActive(!emptyCabin && (s == null || !s.ready || error || s.busy || !string.IsNullOrEmpty(s.notice)));
            foreach (var entry in _resourceTexts)
            {
                var material = s == null ? null : Array.Find(Items(s.materials), m => m.id == entry.Key);
                entry.Value.text = material == null ? "—" : material.label + "  " + material.count;
            }
            foreach (var entry in _nav)
            {
                var selected = entry.Key == view;
                entry.Value.GetComponent<Image>().color = Color.clear;
                entry.Value.GetComponentInChildren<Text>().color = selected ? Yellow : Cream;
                var circle = entry.Value.transform.Find("Action circle");
                if (circle != null)
                {
                    circle.GetComponent<Outline>().enabled = selected;
                    circle.Find("Navigation icon").GetComponent<Image>().color = selected ? Yellow : Cream;
                }
                entry.Value.interactable = s != null && s.ready && !s.busy;
            }
        }

        void Render()
        {
            _liveChecks.Clear();
            Canvas.ForceUpdateCanvases();
            foreach (var panel in _scrolls)
                if (panel.Value != null) _scrollPositions[panel.Key] = panel.Value.verticalNormalizedPosition;
            foreach (Transform child in _content) { child.gameObject.SetActive(false); Destroy(child.gameObject); }
            _scrolls.Clear();
            if (_renderedView != View) { _confirmAction = null; _confirmTitle = null; }
            _renderedView = View;
            if (_villageLayer != null) _villageLayer.gameObject.SetActive(_state != null && _state.ready && (View == "home" || View == "camp"));
            if (_state == null || !_state.ready)
            {
                var loading = Sheet(_content);
                Heading(loading, "작은 세상을 준비하고 있어요");
                Copy(loading, "친구와 보급품을 확인한 뒤 광장이 열려요. 연결이 늦어지면 아래에서 다시 확인해 주세요.");
                Button(loading, "다시 확인", () => Send("refresh"), Mint);
            }
            else if (_confirmAction != null) BuildConfirmation();
            else
            {
                switch (View)
                {
                    case "cabin": BuildCabin(); break;
                    case "camp": BuildCamp(); break;
                    case "dex": BuildDex(); break;
                    case "inventory": BuildInventory(); break;
                    case "settings": BuildSettings(); break;
                    case "pairing": BuildPairing(); break;
                    default: BuildHome(); break;
                }
            }
            Canvas.ForceUpdateCanvases();
            foreach (var panel in _scrolls)
                if (_scrollPositions.TryGetValue(panel.Key, out var position)) panel.Value.verticalNormalizedPosition = position;
            _dirty = false;
        }

        void BuildConfirmation()
        {
            if (View == "home" || View == "camp") BuildVillageMap(0, false);
            var sheet = DockSheet(480);
            Heading(sheet, _confirmTitle);
            Copy(sheet, _confirmDescription, 26);
            var row = NewRow(sheet);
            Button(row, "돌아가기", () => { _confirmAction = null; _dirty = true; }, Cream);
            Button(row, "확인하고 진행", () => { var action = _confirmAction; _confirmAction = null; action?.Invoke(); _dirty = true; }, Yellow, 68, CanAct);
        }

        void Confirm(string title, string description, Action action)
        { _confirmTitle = title; _confirmDescription = description; _confirmAction = action; _dirty = true; }
        void ConfirmIntent(string title, string description, string action, AppAction body)
        {
            body.action = action;
            Confirm(title, description, () => Send(action, body));
        }
        void Navigate(string view)
        {
            _confirmAction = null; _confirmTitle = null; _dirty = true;
            CloseQuestCard(true);
            if (!CanAct) return;
            if (view == "home" || (view == "camp" && View != "camp")) _campDetail = false;
            Send("navigate", new AppAction { view = view });
        }
        void Send(string action, AppAction body = null) { if (action == "refresh" || CanAct) AppSession.Request(action, body); }
        string View => AppSession.CurrentView;
        bool CanAct => _state != null && _state.ready && !_state.busy;
        static T[] Items<T>(T[] values) => values ?? Array.Empty<T>();
        static string ErrorLabel(string error)
        {
            switch (error)
            {
                case "insufficient_materials": return "재료가 부족해요. 보급품에서 보유량을 확인해 주세요.";
                case "missing_worker": return "담당 친구가 없어요. 캠프에서 역할에 맞는 친구를 정해 주세요.";
                case "invalid_worker": return "이 역할을 맡을 수 없는 친구예요. 다른 친구를 골라 주세요.";
                case "creature_busy": case "role_busy": return "이미 다른 작업을 하고 있어요. 작업이 끝난 뒤 다시 해 주세요.";
                case "facility_locked": return "시설 레벨이 부족해요. 캠프에서 시설을 먼저 지어 주세요.";
                case "already_learned": return "이미 배운 행동이에요. 다른 훈련을 골라 주세요.";
                case "save_failed": return "저장하지 못했어요. 저장 상태를 다시 확인한 뒤 시도해 주세요.";
                case "missing_food": return "완성한 요리가 부족해요. 캠프 주방에서 먼저 만들어 주세요.";
                case "not_ready": return "아직 정보를 불러오고 있어요. 잠시 뒤 다시 확인해 주세요.";
                default: return error;
            }
        }
        static string ViewTitle(string view) => view == "pairing" ? "차량 연결하기" : view == "cabin" ? "차 안에서 함께하기" : view == "camp" ? "함께 만드는 캠프" : view == "dex" ? "우리 친구 도감" : view == "inventory" ? "보급품 가방" : "연결과 설정";
        static string DefaultStatus(string view) => view == "home" ? "광장의 친구들과 함께, 다음 여행을 준비해요." : view == "cabin" ? "알을 쓰다듬고 말을 걸며 가까워져요." : view == "camp" ? "건설 · 요리 · 훈련은 각 담당 친구와 함께 진행해요." : view == "inventory" ? "여행에서 모은 재료와 완성한 요리를 확인해요." : view == "dex" ? "함께한 친구를 골라 요리와 배운 행동을 확인해요." : "차량에 표시된 세션 ID와 페어링 코드를 입력해 주세요.";
    }
}
