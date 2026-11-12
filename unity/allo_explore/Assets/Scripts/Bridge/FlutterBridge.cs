using System;
using System.Text;
using UnityEngine;

namespace Allo.Bridge
{
    /// "FlutterBridge" GameObject 에 붙는다. Kotlin 이
    /// UnityPlayer.UnitySendMessage("FlutterBridge", "OnFlutterMessage", json) 로 보낸다.
    ///
    /// - 시작할 때와 다시 화면에 나타날 때 ready 를 보낸다 (Flutter 가 마지막 장면·캐릭터를 다시 보낸다)
    /// - 안드로이드 뒤로 가기(Escape)는 키를 뗄 때 close 로 보낸다
    ///   (누를 때 보내면 Flutter 화면이 먼저 앞에 와서, 뗄 때의 뒤로 가기가 Flutter 화면까지 닫는다)
    /// - 마지막 상태를 Last* 로 들고 있어 늦게 구독한 쪽도 읽을 수 있다
    public sealed class FlutterBridge : MonoBehaviour
    {
        public static event Action<SceneState> SceneChanged;
        public static event Action<CastState> CastChanged;
        public static event Action<string> Jolted;
        public static event Action<SettingsState> SettingsChanged;
        public static event Action<ToastState> Toasted;
        public static event Action<RouteState> RouteChanged;
        public static event Action<EggState> EggChanged;

        public static SceneState LastScene { get; private set; }
        public static CastState LastCast { get; private set; }
        public static SettingsState LastSettings { get; private set; }
        public static RouteState LastRoute { get; private set; }
        public static EggState LastEgg { get; private set; }

        void Start() => SendReady();

        void OnApplicationFocus(bool focused)
        {
            if (focused) SendReady();
        }

        void Update()
        {
            if (Input.GetKeyUp(KeyCode.Escape)) RequestClose();
        }

        public void OnFlutterMessage(string json)
        {
            if (!MessageParser.TryParse(json, out var type, out var payload))
            {
                Debug.LogWarning($"[FlutterBridge] 읽지 못한 메시지: {json}");
                return;
            }
            switch (payload)
            {
                case SceneState s:
                    LastScene = s;
                    SceneChanged?.Invoke(s);
                    break;
                case CastState c:
                    LastCast = c;
                    CastChanged?.Invoke(c);
                    break;
                case JoltState j:
                    Jolted?.Invoke(j.kind);
                    break;
                case SettingsState st:
                    LastSettings = st;
                    SettingsChanged?.Invoke(st);
                    break;
                case ToastState t:
                    Toasted?.Invoke(t);
                    break;
                case RouteState r:
                    LastRoute = r;
                    RouteChanged?.Invoke(r);
                    break;
                case EggState e:
                    LastEgg = e;
                    EggChanged?.Invoke(e);
                    break;
                default:
                    Debug.Log($"[FlutterBridge] 무시: {type}");
                    break;
            }
        }

        static void SendReady() => Send("ready");

        /// 탐험 화면 안의 닫기 버튼·뒤로 가기에서 부른다
        public static void RequestClose() => Send("close");

        /// Unity → Flutter 한 줄. fields 는 `"id":"x"` 처럼 이미 JSON 조각이어야 한다 (Field 로 만든다)
        public static void Send(string type, string fields = null) =>
            AndroidHost.Send(string.IsNullOrEmpty(fields)
                ? $"{{\"v\":1,\"type\":\"{type}\"}}"
                : $"{{\"v\":1,\"type\":\"{type}\",{fields}}}");

        /// JSON 문자열 필드 한 개 (따옴표·역슬래시·제어문자만 피한다)
        public static string Field(string name, string value)
        {
            var sb = new StringBuilder("\"").Append(name).Append("\":\"");
            foreach (var ch in value ?? "")
            {
                switch (ch)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (ch < ' ') sb.Append("\\u").Append(((int)ch).ToString("x4"));
                        else sb.Append(ch);
                        break;
                }
            }
            return sb.Append('"').ToString();
        }
    }
}
