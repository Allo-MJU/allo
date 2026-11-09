using UnityEngine;

/// 연동 검증(spike)용 메시지 받기. 시작하면 ready 를 보내고, 받은 메시지는 그대로 echo 로 돌려준다.
/// Task 3 에서 FlutterBridge 로 바뀐다. GameObject 이름은 반드시 "FlutterBridge" (Kotlin 이 이 이름으로 보낸다).
public sealed class SpikeBridge : MonoBehaviour
{
    void Start() => SendReady();

    /// 탐험 화면을 닫아도 Unity 는 살아 있다. 다시 열려 화면에 나타나면 ready 를 다시 보내
    /// Flutter 의 새 탐험 화면이 마지막 장면·캐릭터를 보내게 한다.
    void OnApplicationFocus(bool focused)
    {
        if (focused) SendReady();
    }

    static void SendReady() => AndroidHost.Send("{\"v\":1,\"type\":\"ready\"}");

    /// Kotlin `UnityPlayer.UnitySendMessage("FlutterBridge", "OnFlutterMessage", json)`
    public void OnFlutterMessage(string json)
    {
        Debug.Log($"[SpikeBridge] got {json}");
        AndroidHost.Send("{\"v\":1,\"type\":\"echo\",\"len\":" + json.Length + "}");
    }

    /// 화면 아무 곳이나 두 번 탭하면 탐험 화면을 닫는다 (spike 용 돌아가기)
    void Update()
    {
        // 안드로이드 뒤로 가기는 Escape 로 들어온다. 키를 뗄 때 닫는다:
        // 누를 때 닫으면 Flutter 화면이 먼저 앞에 오고, 뗄 때의 뒤로 가기가 Flutter 화면까지 닫는다
        if (Input.GetKeyUp(KeyCode.Escape) ||
            (Input.touchCount == 1 && Input.GetTouch(0).tapCount == 2))
            AndroidHost.Send("{\"v\":1,\"type\":\"close\"}");
    }
}
