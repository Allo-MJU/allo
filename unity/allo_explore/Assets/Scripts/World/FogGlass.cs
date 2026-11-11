using UnityEngine;

namespace Allo.World
{
    /// 차 유리 한 장의 김서림. 손가락으로 꾹 누르면 입김처럼 뿌옇게 되고, 그 위를 끌면 지워져 그림이 된다.
    /// 비가 오면 조금씩 저절로 서리고, 시간이 지나면 천천히 걷힌다.
    /// 그림은 Allo/Glass 의 _FogTex (R 채널) 로 넘긴다. 재질은 여러 창이 함께 쓰므로 MaterialPropertyBlock 으로 창마다 따로.
    [RequireComponent(typeof(Renderer))]
    public sealed class FogGlass : MonoBehaviour
    {
        const int W = 128;
        const float Breath = 0.2f;    // 입김 반지름 (가로 UV 기준)
        const float Brush = 0.045f;   // 손가락 굵기
        const float RainFog = 0.5f;   // 비 올 때 저절로 서리는 정도 (아래쪽. 위로 갈수록 옅다)
        const float ClearSeconds = 60; // 다 걷히는 시간

        public static bool Raining;

        Texture2D _tex;
        float[] _fog;
        int _h;
        float _aspect = 2;
        bool _dirty, _hasFog;
        float _applyAt;
        Renderer _r;
        MaterialPropertyBlock _mpb;

        void Awake()
        {
            _r = GetComponent<Renderer>();
            var mf = GetComponent<MeshFilter>();
            if (mf != null && mf.sharedMesh != null)
            {
                // 유리 판의 두 긴 변 비율 (얇은 축은 뺀다)
                var e = mf.sharedMesh.bounds.size;
                var dims = new[] { e.x, e.y, e.z };
                System.Array.Sort(dims);
                if (dims[1] > 1e-4f) _aspect = Mathf.Clamp(dims[2] / dims[1], 1, 4);
            }
            _h = Mathf.Max(16, Mathf.RoundToInt(W / _aspect));
            _fog = new float[W * _h];
            _tex = new Texture2D(W, _h, TextureFormat.R8, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            _mpb = new MaterialPropertyBlock();
            Push();
        }

        void OnDestroy()
        {
            if (_tex != null) Destroy(_tex);
        }

        public float FogAt(Vector2 uv)
        {
            var x = Mathf.Clamp(Mathf.FloorToInt(uv.x * W), 0, W - 1);
            var y = Mathf.Clamp(Mathf.FloorToInt(uv.y * _h), 0, _h - 1);
            return _fog[y * W + x];
        }

        /// 꾹 누른 자리에 입김
        public void Breathe(Vector2 uv) => Stamp(uv, Breath, 1, true);

        /// 손가락이 지나간 자리를 닦는다. 닦은 양을 돌려준다
        public float Wipe(Vector2 uv) => Stamp(uv, Brush, 0, false);

        /// 앞 점에서 이번 점까지 이어서 닦는다 (빠르게 그어도 선이 끊기지 않게)
        public float WipeLine(Vector2 from, Vector2 to)
        {
            var steps = Mathf.Clamp(Mathf.CeilToInt(Vector2.Distance(from, to) / (Brush * 0.5f)), 1, 64);
            var sum = 0f;
            for (var i = 1; i <= steps; i++) sum += Wipe(Vector2.Lerp(from, to, (float)i / steps));
            return sum;
        }

        float Stamp(Vector2 uv, float radius, float value, bool add)
        {
            var cx = uv.x * W; var cy = uv.y * _h;
            var r = radius * W;
            var changed = 0f;
            for (var y = Mathf.Max(0, (int)(cy - r)); y <= Mathf.Min(_h - 1, (int)(cy + r)); y++)
            for (var x = Mathf.Max(0, (int)(cx - r)); x <= Mathf.Min(W - 1, (int)(cx + r)); x++)
            {
                var d = Mathf.Sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) / r;
                if (d > 1) continue;
                var i = y * W + x;
                var before = _fog[i];
                if (add) _fog[i] = Mathf.Max(_fog[i], value * Mathf.SmoothStep(1, 0, d * d));
                else _fog[i] = Mathf.Min(_fog[i], Mathf.Lerp(value, _fog[i], Mathf.SmoothStep(0.6f, 1, d)));
                changed += Mathf.Abs(_fog[i] - before);
            }
            _dirty |= changed > 0;
            _hasFog |= add;
            return changed / Mathf.Max(1, r * r);
        }

        void Update()
        {
            if (!Raining && !_hasFog && !_dirty) return;
            var dt = Time.deltaTime;
            var any = false;
            _hasFog = false;
            for (var i = 0; i < _fog.Length; i++)
            {
                var f = _fog[i];
                var rainTarget = RainFog * (1 - 0.7f * (i / W) / (float)_h); // 아래가 짙고 위가 옅다
                if (Raining && f < rainTarget) f = Mathf.Min(rainTarget, f + dt / 25f);
                else if (f > 0) f = Mathf.Max(0, f - dt / ClearSeconds);
                if (f != _fog[i]) { _fog[i] = f; any = true; }
                if (f > 0) _hasFog = true;
            }
            _dirty |= any;
            if (_dirty && Time.unscaledTime >= _applyAt) Push();
        }

        void Push()
        {
            var px = new byte[_fog.Length];
            for (var i = 0; i < px.Length; i++) px[i] = (byte)(Mathf.Clamp01(_fog[i]) * 255);
            _tex.LoadRawTextureData(px);
            _tex.Apply(false);
            _r.GetPropertyBlock(_mpb);
            _mpb.SetTexture("_FogTex", _tex);
            _r.SetPropertyBlock(_mpb);
            _dirty = false;
            _applyAt = Time.unscaledTime + 1f / 20;
        }
    }
}
