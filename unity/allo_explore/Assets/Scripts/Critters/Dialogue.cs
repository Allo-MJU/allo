using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.Networking;

namespace Allo.Critters
{
    /// 차 안 말풍선 대사 뱅크 (phone/assets/data/cabin_dialogue.json). 규칙은 docs/dialogue-style.md.
    /// 키 = 상황|대상|문맥. 대상은 종 id → @속성 → * 순, 문맥은 그 문맥 → * 순으로 찾는다.
    /// 같은 키에서 바로 전에 쓴 문장은 피한다. {name} 과 조사 {name:이/가} 를 채운다.
    public static class Dialogue
    {
        [Serializable] class Item { public string key; public string[] lines; }
        [Serializable] class Bank { public Item[] items; }

        static Dictionary<string, string[]> _bank;
        static readonly Dictionary<string, int> _last = new();
        static bool _loading;

        public static bool Ready => _bank != null;

        /// 테스트·에디터용: JSON 문자열에서 바로 채운다
        public static void Parse(string json)
        {
            var b = JsonUtility.FromJson<Bank>(json);
            var d = new Dictionary<string, string[]>();
            if (b?.items != null)
                foreach (var it in b.items)
                    if (!string.IsNullOrEmpty(it.key) && it.lines != null && it.lines.Length > 0) d[it.key] = it.lines;
            _bank = d;
            _last.Clear();
        }

        public static void Clear() { _bank = null; _last.Clear(); }

        /// Flutter 에셋(같은 APK 의 flutter_assets)에서 읽는다. 에디터에서는 phone/assets 폴더
        public static IEnumerator Load()
        {
            if (_bank != null || _loading) yield break;
            _loading = true;
            const string rel = "data/cabin_dialogue.json";
#if UNITY_EDITOR
            var file = Path.GetFullPath(Path.Combine(Application.dataPath, "../../../phone/assets", rel));
            if (File.Exists(file)) { Parse(File.ReadAllText(file)); _loading = false; yield break; }
#endif
            var url = $"{Application.streamingAssetsPath}/flutter_assets/assets/{rel}";
            using var req = UnityWebRequest.Get(url);
            yield return req.SendWebRequest();
            if (req.result == UnityWebRequest.Result.Success) Parse(req.downloadHandler.text);
            else Debug.LogWarning($"[Dialogue] 대사 뱅크를 못 읽었어요: {req.error}");
            _loading = false;
        }

        /// 종 한글 이름 (`name|종|*`). 없으면 id
        public static string NameOf(string species)
        {
            if (_bank != null && _bank.TryGetValue($"name|{species}|*", out var l) && l.Length > 0) return l[0];
            return species;
        }

        public static string Pick(string evt, string species, string attribute, string context, System.Random rng)
        {
            if (_bank == null) return null;
            var targets = new[] { species, "@" + attribute, "*" };
            var contexts = string.IsNullOrEmpty(context) || context == "*" ? new[] { "*" } : new[] { context, "*" };
            foreach (var t in targets)
            {
                if (string.IsNullOrEmpty(t) || t == "@") continue;
                foreach (var c in contexts)
                {
                    var key = $"{evt}|{t}|{c}";
                    if (!_bank.TryGetValue(key, out var lines) || lines.Length == 0) continue;
                    var i = lines.Length == 1 ? 0 : rng.Next(lines.Length);
                    if (lines.Length > 1 && _last.TryGetValue(key, out var prev) && i == prev) i = (i + 1) % lines.Length;
                    _last[key] = i;
                    return Fill(lines[i], NameOf(species));
                }
            }
            return null;
        }

        /// {name} 과 조사 플레이스홀더를 채운다
        public static string Fill(string s, string name)
        {
            if (string.IsNullOrEmpty(s)) return s;
            var batchim = HasBatchim(name);
            return s.Replace("{name:이/가}", batchim ? "이" : "가")
                .Replace("{name:은/는}", batchim ? "은" : "는")
                .Replace("{name:을/를}", batchim ? "을" : "를")
                .Replace("{name:아/야}", batchim ? "아" : "야")
                .Replace("{name}", name);
        }

        /// 마지막 글자에 받침이 있는지 (한글이 아니면 없는 것으로)
        public static bool HasBatchim(string s)
        {
            if (string.IsNullOrEmpty(s)) return false;
            var c = s[s.Length - 1];
            if (c < 0xAC00 || c > 0xD7A3) return false;
            return (c - 0xAC00) % 28 != 0;
        }
    }
}
