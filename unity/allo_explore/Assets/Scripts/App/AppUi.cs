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
        RectTransform _safe, _content;
        Text _title, _connection, _status;
        Image _statusSurface;
        Font _font;
        Sprite _round;
        AppState _state;
        bool _dirty = true;
        string _renderedView, _selectedCreature, _selectedDex, _campTab = "builder", _selectedTarget;
        string _sessionId = "", _pairCode = "", _speech = "", _tier = "small";
        string _confirmTitle, _confirmDescription;
        Action _confirmAction;
        readonly Dictionary<string, float> _scrollPositions = new Dictionary<string, float>();
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
            OnState(AppSession.State);
        }

        void OnDisable() { AppSession.Changed -= OnState; }
        void OnState(AppState state) { _state = state; _dirty = true; }

        void LateUpdate()
        {
            ApplySafeArea();
            foreach (var check in _liveChecks) check();
            if (!_dirty || _safe == null) return;
            UpdateChrome();
            // Snapshot ticks must not tear down a focused keyboard field or an active drag.
            var selected = EventSystem.current != null ? EventSystem.current.currentSelectedGameObject : null;
            var input = selected != null ? selected.GetComponent<InputField>() : null;
            if (input != null && input.isFocused && _renderedView == View) return;
            if (Input.GetMouseButton(0) || Input.touchCount > 0) return;
            Render();
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
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 100;
            var scaler = canvasGo.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1280, 720);
            scaler.matchWidthOrHeight = .5f;
            _safe = Rect("Safe area", canvasGo.transform);
            Stretch(_safe);

            var header = Rect("Header", _safe);
            Stretch(header, 24, -98, -24, -20, new Vector2(0, 1), new Vector2(1, 1));
            var titleSurface = Surface("Title", header, Cream);
            Stretch(titleSurface, 0, 0, -330, 0);
            _title = Label(titleSurface, "ALLO", 34, TextAnchor.MiddleLeft);
            Stretch(_title.rectTransform, 22, 0, -18, 0);
            var connectionSurface = Surface("Connection", header, Cream);
            Stretch(connectionSurface, -306, 0, 0, 0, new Vector2(1, 0), Vector2.one);
            _connection = Label(connectionSurface, "연결 확인 중", 24, TextAnchor.MiddleCenter);
            Stretch(_connection.rectTransform, 10, 0, -10, 0);
            var connectionButton = connectionSurface.gameObject.AddComponent<Button>();
            connectionButton.onClick.AddListener(() => Navigate("settings"));

            _content = Rect("Screen", _safe);
            Stretch(_content, 24, 172, -24, -116);
            var status = Surface("Status", _safe, Cream);
            Stretch(status, 24, 100, -24, 156, Vector2.zero, new Vector2(1, 0));
            _statusSurface = status.GetComponent<Image>();
            _status = Label(status, "캠프를 불러오고 있어요.", 22, TextAnchor.MiddleLeft);
            Stretch(_status.rectTransform, 18, 0, -18, 0);
            var nav = Rect("Navigation", _safe);
            Stretch(nav, 24, 20, -24, 88, Vector2.zero, new Vector2(1, 0));
            Row(nav, 10);
            string[] ids = { "home", "cabin", "camp", "dex", "inventory", "settings" };
            string[] labels = { "광장", "차 안", "캠프", "친구 도감", "보급품", "설정" };
            for (var i = 0; i < ids.Length; i++)
            {
                var id = ids[i];
                _nav[id] = Button(nav, labels[i], () => Navigate(id), Cream, 64, true, 25);
            }
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
            _title.text = view == "home" ? "ALLO  ·  우리들의 작은 광장" : ViewTitle(view);
            var s = _state;
            _connection.text = s == null || !s.ready ? "불러오는 중" : s.busy ? "처리 중" : s.sessionEnded ? "여행 종료" : s.connected ? (s.isDemo ? "체험 연결됨" : "차량 연결됨") : "차량 연결 안 됨";
            _connection.color = s != null && s.connected ? Ink : Muted;
            var error = s != null && !string.IsNullOrEmpty(s.error);
            _statusSurface.color = error ? CoralLight : s != null && s.busy ? Sky : Cream;
            _status.text = s == null || !s.ready ? "캠프를 불러오고 있어요." : error ? "! " + ErrorLabel(s.error) : s.busy ? "처리 중이에요. 잠시 기다려 주세요." : !string.IsNullOrEmpty(s.notice) ? s.notice : DefaultStatus(view);
            foreach (var entry in _nav)
            {
                entry.Value.GetComponent<Image>().color = entry.Key == view ? Mint : Cream;
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
            var sheet = Sheet(_content);
            Heading(sheet, _confirmTitle);
            Copy(sheet, _confirmDescription, 26);
            var row = NewRow(sheet);
            Button(row, "돌아가기", () => { _confirmAction = null; _dirty = true; }, Cream);
            Button(row, "확인하고 진행", () => { var action = _confirmAction; _confirmAction = null; action?.Invoke(); _dirty = true; }, Yellow, 68, CanAct);
        }

        void Confirm(string title, string description, Action action)
        { _confirmTitle = title; _confirmDescription = description; _confirmAction = action; _dirty = true; }
        void Navigate(string view) { if (CanAct) Send("navigate", new AppAction { view = view }); }
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
        static string ViewTitle(string view) => view == "cabin" ? "차 안에서 알 키우기" : view == "camp" ? "함께 만드는 캠프" : view == "dex" ? "우리 친구 도감" : view == "inventory" ? "보급품 가방" : "연결과 설정";
        static string DefaultStatus(string view) => view == "home" ? "광장의 친구들과 함께, 다음 여행을 준비해요." : view == "cabin" ? "알을 쓰다듬고 말을 걸며 가까워져요." : view == "camp" ? "건설 · 요리 · 훈련은 각 담당 친구와 함께 진행해요." : view == "inventory" ? "여행에서 모은 재료와 완성한 요리를 확인해요." : view == "dex" ? "함께한 친구를 골라 요리와 배운 행동을 확인해요." : "차량에 표시된 세션 ID와 페어링 코드를 입력해 주세요.";
    }
}
