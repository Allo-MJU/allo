using System;
using System.Collections;
using UnityEngine;
using UnityEngine.Networking;

namespace Allo.Critters
{
    /// D 의 캐릭터 그림을 Flutter 에셋에서 읽는다. 같은 APK 안 assets/flutter_assets/ 에 있다.
    /// 없거나 실패하면 아무 일도 하지 않는다 (임시 얼굴이 그대로 남는다).
    public static class SpriteLoader
    {
        public static IEnumerator Load(string sprite, Action<Texture2D> done)
        {
            if (string.IsNullOrEmpty(sprite)) yield break;
            var url = $"{Application.streamingAssetsPath}/flutter_assets/assets/{sprite}";
            using var req = UnityWebRequestTexture.GetTexture(url);
            yield return req.SendWebRequest();
            if (req.result == UnityWebRequest.Result.Success) done(DownloadHandlerTexture.GetContent(req));
        }
    }
}
