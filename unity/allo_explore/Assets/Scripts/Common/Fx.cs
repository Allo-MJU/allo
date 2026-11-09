using System.Collections.Generic;
using UnityEngine;

namespace Allo
{
    /// 작은 연출: 하트·반짝이가 위로 떠오르며 사라진다 (탭·먹이·발견 반응). 텍스처는 코드로 그린다.
    public static class Fx
    {
        static Texture2D _heart, _spark, _note;
        static Material _mat;

        public static Texture2D Heart => _heart ??= Draw(64, (u, v) =>
        {
            // 하트: (x²+y²-1)³ - x²y³ < 0
            var x = u * 1.3f; var y = v * 1.3f + 0.15f;
            var a = x * x + y * y - 1;
            return a * a * a - x * x * y * y * y < 0 ? new Color(1f, 0.42f, 0.52f) : Color.clear;
        });

        public static Texture2D Spark => _spark ??= Draw(64, (u, v) =>
        {
            // 네 갈래 별
            var d = Mathf.Pow(Mathf.Abs(u), 0.5f) + Mathf.Pow(Mathf.Abs(v), 0.5f);
            return d < 0.95f ? Color.Lerp(Color.white, new Color(1f, 0.93f, 0.5f), d) : Color.clear;
        });

        public static Texture2D Note => _note ??= Draw(64, (u, v) =>
        {
            // 음표: 머리(타원) + 기둥 + 깃발
            var hx = (u + 0.25f) / 0.32f; var hy = (v + 0.55f) / 0.22f;
            if (hx * hx + hy * hy < 1) return new Color(0.35f, 0.3f, 0.6f);
            if (u > 0.0f && u < 0.14f && v > -0.55f && v < 0.75f) return new Color(0.35f, 0.3f, 0.6f);
            if (u >= 0.14f && u < 0.55f && v > 0.35f + (u - 0.14f) * 0.6f && v < 0.75f) return new Color(0.35f, 0.3f, 0.6f);
            return Color.clear;
        });

        static Texture2D Draw(int n, System.Func<float, float, Color> f)
        {
            var t = new Texture2D(n, n, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            var px = new Color[n * n];
            for (var y = 0; y < n; y++)
            for (var x = 0; x < n; x++)
                px[y * n + x] = f((x + 0.5f) / n * 2 - 1, (y + 0.5f) / n * 2 - 1);
            t.SetPixels(px);
            t.Apply();
            return t;
        }

        static Material Mat(Material baseMat, Texture2D tex)
        {
            if (_mat == null) _mat = new Material(baseMat ?? new Material(Shader.Find("Legacy Shaders/Transparent/Cutout/Diffuse")));
            return new Material(_mat) { mainTexture = tex };
        }

        /// at 주변에서 n 개가 0.9초 동안 떠오르며 사라진다. size 는 미터
        public static void Burst(Vector3 at, Texture2D tex, Material baseMat, int n = 5, float size = 0.07f, float spread = 0.12f)
        {
            var m = Mat(baseMat, tex);
            for (var i = 0; i < n; i++)
            {
                var go = GameObject.CreatePrimitive(PrimitiveType.Quad);
                Object.Destroy(go.GetComponent<Collider>());
                go.name = "Fx";
                var r = go.GetComponent<Renderer>();
                r.sharedMaterial = m;
                r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                r.receiveShadows = false;
                var f = go.AddComponent<Floaty>();
                f.start = at + new Vector3(Random.Range(-spread, spread), Random.Range(0, spread * 0.5f), Random.Range(-spread, spread));
                f.rise = Random.Range(0.12f, 0.22f) * size / 0.07f;
                f.size = size * Random.Range(0.8f, 1.25f);
                f.delay = i * 0.06f;
            }
        }

        /// 떠오르며 커졌다 사라지는 한 장. 카메라를 향한다
        public sealed class Floaty : MonoBehaviour
        {
            public Vector3 start;
            public float rise = 0.15f, size = 0.07f, delay, life = 0.9f;
            float _t;

            void LateUpdate()
            {
                _t += Time.deltaTime;
                var k = Mathf.Clamp01((_t - delay) / life);
                if (_t - delay >= life) { Destroy(gameObject); return; }
                var cam = Camera.main;
                var p = start + Vector3.up * (rise * Mathf.Sin(k * Mathf.PI * 0.5f));
                transform.position = p;
                if (cam != null) transform.rotation = Quaternion.LookRotation(p - cam.transform.position);
                var s = size * (0.6f + 0.6f * Mathf.Sin(k * Mathf.PI)) * (k < 0.001f ? 0 : 1);
                transform.localScale = new Vector3(s, s, 1);
            }
        }
    }
}
