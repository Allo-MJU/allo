using System;
using UnityEngine;

namespace Allo.Bridge
{
    /// Flutter 메시지 한 줄을 읽는다. 순수 함수라 EditMode 테스트로 확인한다.
    /// - 버전(v)이 달라도 아는 필드는 읽는다 (다음 버전 Flutter 와 섞여도 죽지 않게)
    /// - 모르는 type 은 true 와 payload=null 로 돌려준다 (무시)
    /// - 깨진 JSON 은 false
    public static class MessageParser
    {
        public static bool TryParse(string json, out string type, out object payload)
        {
            type = null;
            payload = null;
            if (string.IsNullOrWhiteSpace(json)) return false;
            try
            {
                var env = JsonUtility.FromJson<Envelope>(json);
                if (env == null || string.IsNullOrEmpty(env.type)) return false;
                type = env.type;
                payload = type switch
                {
                    "scene" => JsonUtility.FromJson<SceneState>(json),
                    "cast" => Normalize(JsonUtility.FromJson<CastState>(json)),
                    "jolt" => JsonUtility.FromJson<JoltState>(json),
                    "settings" => JsonUtility.FromJson<SettingsState>(json),
                    _ => null,
                };
                return true;
            }
            catch (ArgumentException)
            {
                return false;
            }
        }

        static CastState Normalize(CastState c)
        {
            c.friends ??= Array.Empty<CastMember>();
            if (c.companion != null && string.IsNullOrEmpty(c.companion.id)) c.companion = null;
            return c;
        }
    }
}
