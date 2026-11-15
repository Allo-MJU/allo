using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.Networking;

namespace Allo.Critters
{
    public enum ArtPose { Idle, Move, Happy, Sleep }

    /// 한 종의 그림 묶음. D 의 포즈 그림(idle·move·happy·sleep)이 있으면 쓰고, 없는 포즈는 idle 로 대신한다.
    /// D 의 그림은 모두 왼쪽을 본다 (FacesLeft).
    public sealed class CritterArt
    {
        readonly Dictionary<ArtPose, Texture2D> _tex = new();

        public bool FacesLeft = true;

        public CritterArt(Texture2D idle) => _tex[ArtPose.Idle] = idle;

        public Texture2D this[ArtPose p] => _tex.TryGetValue(p, out var t) ? t : _tex[ArtPose.Idle];

        public void Set(ArtPose p, Texture2D t) => _tex[p] = t;

        /// 가로 / 세로. 한 종의 포즈 그림은 캔버스 크기가 같다
        public float Aspect => (float)this[ArtPose.Idle].width / this[ArtPose.Idle].height;

        /// 임시 얼굴 (정면이라 좌우가 없다)
        public static CritterArt Placeholder(string attribute, int seed) =>
            new(PlaceholderFace.Make(attribute, seed)) { FacesLeft = false };
    }

    /// D 의 캐릭터 그림을 Flutter 에셋에서 읽는다. 같은 APK 안 assets/flutter_assets/ 에 있다.
    /// sprite 가 "species/road_sprout.png" 이면 포즈는 "species/road_sprout_move.png" 처럼 옆에 둔다.
    /// 없거나 실패하면 아무 일도 하지 않는다 (임시 얼굴이 그대로 남는다).
    public static class SpriteLoader
    {
        static readonly Dictionary<string, CritterArt> Cache = new();
        static readonly HashSet<string> ActionAtlasSpecies = new()
        { "bridge_hopper", "mountain_sprite", "river_glider", "tide_keeper", "tunnel_moth", "star_owl" };

        static string ActionAtlasPath(string sprite)
        {
            var id = Path.GetFileNameWithoutExtension(sprite);
            return ActionAtlasSpecies.Contains(id) && sprite == "species/" + id + ".png"
                ? "poses/" + id + "/actions.png" : null;
        }

        static string PosePath(string sprite, ArtPose p)
        {
            if (p == ArtPose.Idle) return sprite;
            var ext = Path.GetExtension(sprite);
            return sprite.Substring(0, sprite.Length - ext.Length) + "_" + p.ToString().ToLowerInvariant() + ext;
        }

        /// idle 을 먼저 읽어 done 을 부르고, 나머지 포즈는 읽히는 대로 채운다
        public static IEnumerator Load(string sprite, Action<CritterArt> done)
        {
            if (string.IsNullOrEmpty(sprite)) yield break;
            if (Cache.TryGetValue(sprite, out var hit)) { done(hit); yield break; }
#if UNITY_EDITOR
            var now = LoadNow(sprite);
            if (now != null) done(now);
            yield break;
#else
            Texture2D idle = null;
            yield return Fetch(sprite, t => idle = t);
            if (idle == null)
            {
                var atlasPath = ActionAtlasPath(sprite);
                if (atlasPath == null) yield break;
                var url = $"{Application.streamingAssetsPath}/flutter_assets/assets/{atlasPath}";
                using var request = UnityWebRequest.Get(url);
                yield return request.SendWebRequest();
                if (request.result != UnityWebRequest.Result.Success) yield break;
                if (!Cache.TryGetValue(sprite, out var fallback))
                    fallback = DecodeActionAtlas(request.downloadHandler.data, atlasPath);
                if (fallback != null) { Cache[sprite] = fallback; done(fallback); }
                yield break;
            }
            var art = new CritterArt(idle);
            Cache[sprite] = art;
            done(art);
            foreach (var p in new[] { ArtPose.Move, ArtPose.Happy, ArtPose.Sleep })
                if (!Broken(PosePath(sprite, p))) yield return Fetch(PosePath(sprite, p), t => art.Set(p, t));
#endif
        }

        static IEnumerator Fetch(string path, Action<Texture2D> done)
        {
            var url = $"{Application.streamingAssetsPath}/flutter_assets/assets/{path}";
            using var req = UnityWebRequest.Get(url);
            yield return req.SendWebRequest();
            if (req.result != UnityWebRequest.Result.Success) yield break;
            var t = Decode(req.downloadHandler.data, path);
            if (t != null) done(t);
        }

        /// 에디터(캡처)용: 폰 에셋 폴더에서 바로 읽는다
        public static CritterArt LoadNow(string sprite)
        {
            if (string.IsNullOrEmpty(sprite)) return null;
            if (Cache.TryGetValue(sprite, out var hit)) return hit;
            var root = Path.GetFullPath(Path.Combine(Application.dataPath, "../../../phone/assets"));
            Texture2D Read(string p)
            {
                var f = Path.Combine(root, p);
                return File.Exists(f) ? Decode(File.ReadAllBytes(f), p) : null;
            }
            var idle = Read(sprite);
            if (idle == null)
            {
                var atlasPath = ActionAtlasPath(sprite);
                if (atlasPath == null) return null;
                var file = Path.Combine(root, atlasPath);
                var fallback = File.Exists(file) ? DecodeActionAtlas(File.ReadAllBytes(file), atlasPath) : null;
                if (fallback != null) Cache[sprite] = fallback;
                return fallback;
            }
            var art = new CritterArt(idle);
            foreach (var p in new[] { ArtPose.Move, ArtPose.Happy, ArtPose.Sleep })
            {
                if (Broken(PosePath(sprite, p))) continue;
                var t = Read(PosePath(sprite, p));
                if (t != null) art.Set(p, t);
            }
            return Cache[sprite] = art;
        }

        /// PNG → 밉맵 있는 premultiplied 텍스처 (Allo/Sprite 셰이더용)
        /// 바닥판이 그려져 있지 않고 몸이 희고 연한 종. 바닥판 지우기가 얼굴(엎드린 자세에서 그림 아래쪽)을 지운다
        static readonly string[] NoFloorPlate = { "sea_mist", "lamp_moth" };

        /// 원본이 깨진 포즈 그림 (배경을 지울 때 얼굴까지 투명해짐). 읽지 않고 idle 로 대신한다. D 가 고치면 빼기
        static readonly string[] BrokenPoses = { "sea_mist_happy" };

        static bool Broken(string path) => System.Array.IndexOf(BrokenPoses, Path.GetFileNameWithoutExtension(path)) >= 0;

        static bool HasFloorPlate(string path)
        {
            var name = Path.GetFileNameWithoutExtension(path);
            foreach (var id in NoFloorPlate)
                if (name == id || name.StartsWith(id + "_")) return false;
            return true;
        }

        static Texture2D Decode(byte[] png, string path)
        {
            var src = new Texture2D(2, 2, TextureFormat.RGBA32, false);
            if (!src.LoadImage(png)) { Drop(src); return null; }
            var px = src.GetPixels32();
            if (HasFloorPlate(path)) RemoveFloor(px, src.width, src.height);
            var result = Premultiplied(px, src.width, src.height, path);
            Drop(src);
            return result;
        }

        // These species have an authored 4 x 6 atlas rather than standalone PNGs.
        // Extract only the same species' cells; portraits must never show the full sheet.
        static CritterArt DecodeActionAtlas(byte[] png, string path)
        {
            var src = new Texture2D(2, 2, TextureFormat.RGBA32, false);
            if (!src.LoadImage(png) || src.width < 4 || src.height < 6 || src.width % 4 != 0 || src.height % 6 != 0)
            { Drop(src); return null; }
            var pixels = src.GetPixels32();
            var width = src.width / 4; var height = src.height / 6;
            Texture2D Cell(int frame)
            {
                var px = new Color32[width * height];
                var x = frame % 4 * width; var y = src.height - (frame / 4 + 1) * height;
                for (var row = 0; row < height; row++)
                    Array.Copy(pixels, (y + row) * src.width + x, px, row * width, width);
                // Match the village/car atlas alpha cutoff without applying the
                // unrelated standalone portrait floor-removal heuristic.
                for (var i = 0; i < px.Length; i++)
                    px[i].a = (byte)Mathf.Clamp(Mathf.RoundToInt((px[i].a - 32) * 255f / 223), 0, 255);
                return Premultiplied(px, width, height, path + "#" + frame);
            }
            var art = new CritterArt(Cell(0));
            art.Set(ArtPose.Move, Cell(1));
            art.Set(ArtPose.Sleep, Cell(16));
            Drop(src);
            return art;
        }

        static Texture2D Premultiplied(Color32[] px, int width, int height, string name)
        {
            for (var i = 0; i < px.Length; i++)
            {
                var a = px[i].a;
                px[i].r = (byte)(px[i].r * a / 255);
                px[i].g = (byte)(px[i].g * a / 255);
                px[i].b = (byte)(px[i].b * a / 255);
            }
            var t = new Texture2D(width, height, TextureFormat.RGBA32, true)
            {
                name = name,
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Trilinear,
                anisoLevel = 2,
            };
            t.SetPixels32(px);
            t.Apply(true, true);
            return t;
        }

        /// D 의 그림 아래에 함께 그려진 연한 회색 바닥판을 지운다 (3D 에서는 발밑 그림자를 따로 그린다).
        /// 아래쪽 띠에서 투명한 곳부터 이어진 '밝고 채도 낮은' 픽셀만 지우므로 몸 안쪽의 흰 부분은 남는다.
        public static int RemoveFloor(Color32[] px, int w, int h)
        {
            var band = Mathf.CeilToInt(h * 0.22f); // GetPixels32 는 아래 줄부터
            var seen = new bool[w * band];
            var q = new Queue<int>();
            for (var i = 0; i < w * band; i++)
                if (px[i].a < 26) { seen[i] = true; q.Enqueue(i); }
            // 맨 아래 9% 줄은 발 밑에 깔린 연한 바닥 자국(길싹이: 분홍빛 그림자 테두리, 아래 8~21줄)을 색조 가리지 않고 지운다.
            // 더 올리면 배 아래 크림색까지 지워진다 (길싹이 배 아랫단은 약 11%)
            var strip = Mathf.CeilToInt(h * 0.09f);
            bool Floor(Color32 c, int y)
            {
                if (c.a == 0) return true;
                var mx = Mathf.Max(c.r, Mathf.Max(c.g, c.b));
                var mn = Mathf.Min(c.r, Mathf.Min(c.g, c.b));
                if (y < strip) return mx >= 150 && mx - mn <= 60;
                // 바닥판은 '밝은' 따뜻한 회색(빨강 ≥ 파랑). 푸른빛 몸(바다안개 등)과 어두운 올리브색 발(길싹이)은 건드리지 않는다.
                // 밝기 150 미만을 바닥으로 치면 길싹이 발(40~120)이 지워져 발이 빈 채로 보였다 (2026-11-12)
                return mx >= 150 && mx - mn <= 34 && c.r + 6 >= c.b;
            }
            var removed = 0;
            // 2차: 아래 10% 안의 '아주 밝고 채도 낮은' 픽셀(발 사이에 끼인 그림자 판의 흰 테두리)은 투명 영역과 이어져 있지 않아도 지운다.
            // 발바닥 분홍(채도 43)과 배 크림색(10% 위)은 남는다
            var zone = Mathf.CeilToInt(h * 0.10f);
            for (var i = 0; i < w * zone; i++)
            {
                var c = px[i];
                if (c.a == 0) continue;
                var mx = Mathf.Max(c.r, Mathf.Max(c.g, c.b));
                var mn = Mathf.Min(c.r, Mathf.Min(c.g, c.b));
                if (mx >= 195 && mx - mn <= 40) { px[i] = new Color32(0, 0, 0, 0); removed++; }
            }
            while (q.Count > 0)
            {
                var i = q.Dequeue();
                if (px[i].a > 0) { px[i] = new Color32(0, 0, 0, 0); removed++; }
                int x = i % w, y = i / w;
                void Try(int nx, int ny)
                {
                    if (nx < 0 || nx >= w || ny < 0 || ny >= band) return;
                    var j = ny * w + nx;
                    if (seen[j] || !Floor(px[j], ny)) return;
                    seen[j] = true;
                    q.Enqueue(j);
                }
                Try(x - 1, y); Try(x + 1, y); Try(x, y - 1); Try(x, y + 1);
            }
            return removed;
        }

        static void Drop(UnityEngine.Object o)
        {
            if (Application.isPlaying) UnityEngine.Object.Destroy(o);
            else UnityEngine.Object.DestroyImmediate(o);
        }
    }
}
