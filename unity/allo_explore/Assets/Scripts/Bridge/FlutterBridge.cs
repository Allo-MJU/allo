using System;
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

        public static SceneState LastScene { get; private set; }
        public static CastState LastCast { get; private set; }
        public static SettingsState LastSettings { get; private set; }

        void Start() => SendReady();

        void OnApplicationFocus(bool focused)
        {
            if (focused) SendReady();
        }

        void Update()
        {
            if (Input.GetKeyUp(KeyCode.Escape)) AndroidHost.Send("{\"v\":1,\"type\":\"close\"}");
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
                default:
                    Debug.Log($"[FlutterBridge] 무시: {type}");
                    break;
            }
        }

        static void SendReady() => AndroidHost.Send("{\"v\":1,\"type\":\"ready\"}");

        /// 탐험 화면 안의 닫기 버튼 등에서 부른다
        public static void RequestClose() => AndroidHost.Send("{\"v\":1,\"type\":\"close\"}");
    }
}
