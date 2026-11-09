using UnityEngine;

namespace Allo.Critters
{
    /// D 의 캐릭터 그림이 없을 때 쓰는 임시 얼굴. 속성 색의 둥근 몸에 눈·볼·발을 그린다.
    public static class PlaceholderFace
    {
        public static Texture2D Make(string attribute, int seed)
        {
            const int n = 128;
            var body = attribute switch
            {
                "water" => new Color(0.36f, 0.66f, 0.85f),
                "dark" => new Color(0.48f, 0.38f, 0.72f),
                _ => new Color(0.42f, 0.75f, 0.5f),
            };
            var rng = new System.Random(seed);
            body = Color.Lerp(body, Color.white, (float)rng.NextDouble() * 0.2f);
            var shade = Color.Lerp(body, Color.black, 0.22f);
            var tex = new Texture2D(n, n, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
            var px = new Color[n * n];
            for (var y = 0; y < n; y++)
            for (var x = 0; x < n; x++)
            {
                var u = (x + 0.5f) / n * 2 - 1;
                var v = (y + 0.5f) / n * 2 - 1;
                var c = Color.clear;
                // 몸: 아래가 넓은 물방울형
                var bx = u / (0.78f + 0.12f * -v);
                var by = (v + 0.08f) / 0.86f;
                if (bx * bx + by * by < 1)
                {
                    c = Color.Lerp(body, shade, Mathf.Clamp01(-v * 0.6f + 0.2f + u * 0.25f));
                    // 왼쪽 위 광택
                    var gx = u + 0.35f; var gy = v - 0.4f;
                    if (gx * gx + gy * gy * 1.6f < 0.03f) c = Color.Lerp(c, Color.white, 0.7f);
                }
                // 발
                foreach (var fx in new[] { -0.35f, 0.35f })
                {
                    var dx = (u - fx) / 0.2f; var dy = (v + 0.9f) / 0.09f;
                    if (dx * dx + dy * dy < 1) c = shade;
                }
                // 눈
                foreach (var ex in new[] { -0.25f, 0.25f })
                {
                    var dx = (u - ex) / 0.11f; var dy = (v - 0.12f) / 0.15f;
                    if (dx * dx + dy * dy < 1)
                    {
                        c = new Color(0.12f, 0.1f, 0.1f);
                        var hx = (u - ex + 0.035f) / 0.04f; var hy = (v - 0.17f) / 0.05f;
                        if (hx * hx + hy * hy < 1) c = Color.white;
                    }
                    // 볼
                    var cx = (u - ex * 1.55f) / 0.1f; var cy = (v + 0.08f) / 0.06f;
                    if (cx * cx + cy * cy < 1 && c.a > 0) c = Color.Lerp(c, new Color(1f, 0.55f, 0.55f), 0.55f);
                }
                // 입
                { var mx = u / 0.08f; var my = (v + 0.02f) / 0.04f; if (mx * mx + my * my < 1 && v < -0.02f) c = new Color(0.3f, 0.15f, 0.15f); }
                px[y * n + x] = c;
            }
            tex.SetPixels(px);
            tex.Apply();
            return tex;
        }
    }
}
