using UnityEngine;

namespace Allo.Bridge
{

/// Unity → Android 호스트(Kotlin `ai.allo.allo_phone.ExploreBridge`) 로 메시지를 보낸다.
/// 에디터에서는 로그만 남긴다.
public static class AndroidHost
{
    const string BridgeClass = "ai.allo.allo_phone.ExploreBridge";

    public static void Send(string json)
    {
#if UNITY_ANDROID && !UNITY_EDITOR
        using var bridge = new AndroidJavaClass(BridgeClass);
        bridge.CallStatic("fromUnity", json);
#else
        Debug.Log($"[AndroidHost] {json}");
#endif
    }
}
}
