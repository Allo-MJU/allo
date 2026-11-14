using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.Networking;
using UnityEngine.UI;

namespace Allo.App
{
    [RequireComponent(typeof(RawImage))]
    public sealed class VillageCharacterArt : MonoBehaviour
    {
        const float FrameSeconds = .16f;
        static readonly HashSet<string> WalkingSpecies = new HashSet<string>
        { "road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist" };
        static readonly Dictionary<string, Texture2D> Textures = new Dictionary<string, Texture2D>();
        RawImage _image;
        AspectRatioFitter _fit;
        GameObject _fallback;
        Texture2D _idle, _atlas;
        string _species, _idlePath, _atlasPath;
        bool _moving, _facingLeft, _reducedMotion;
        bool _loadComplete = true, _loading;
        float _elapsed;
        int _binding;

        public bool IsMoving => _moving;
        public bool FacingLeft => _facingLeft;
        public bool IsAnimated => _moving && !_reducedMotion && _atlas != null;
        public int FrameIndex => IsAnimated ? Mathf.FloorToInt(_elapsed / FrameSeconds) % 8 : 0;

        void Awake()
        {
            _image = GetComponent<RawImage>();
            _fit = GetComponent<AspectRatioFitter>();
        }

        public void Bind(string speciesId, string idleSpritePath, GameObject fallback)
        {
            if (_image == null) Awake();
            StopAllCoroutines();
            ++_binding;
            _species = speciesId;
            _idlePath = idleSpritePath;
            _atlasPath = WalkingSpecies.Contains(speciesId ?? "") ? "poses/" + speciesId + "/run-sheet.png" : null;
            _fallback = fallback;
            _idle = _atlas = null;
            _loadComplete = _loading = false;
            _elapsed = 0;
            Refresh();
            ResumeLoading();
        }

        void OnEnable() => ResumeLoading();

        void OnDisable()
        {
            // Deactivating the village stops child coroutines; resume unfinished art on return.
            ++_binding;
            StopAllCoroutines();
            _loading = false;
        }

        void ResumeLoading()
        {
            if (!isActiveAndEnabled || _loadComplete || _loading) return;
            _loading = true;
#if UNITY_EDITOR
            _idle = ReadEditor(_idlePath, false);
            _atlas = ReadEditor(_atlasPath, true);
            _loadComplete = true;
            _loading = false;
            Refresh();
#else
            StartCoroutine(LoadBinding(_binding, _idlePath, _atlasPath));
#endif
        }

        public void SetMotion(bool moving, bool facingLeft, bool reducedMotion)
        {
            if (_moving != moving || _reducedMotion != reducedMotion) _elapsed = 0;
            _moving = moving;
            _facingLeft = facingLeft;
            _reducedMotion = reducedMotion;
            Refresh();
        }

        void Update() => Advance(Time.unscaledDeltaTime);

        public void Advance(float deltaTime)
        {
            if (!isActiveAndEnabled || !_moving || _reducedMotion) return;
            // Keep the inspector clock while its atlas is still being fetched.
            _elapsed = (_elapsed + Mathf.Max(0, deltaTime)) % (8 * FrameSeconds);
            Refresh();
        }

        void Refresh()
        {
            if (_image == null) return;
            var sheet = IsAnimated || _idle == null;
            var texture = sheet ? _atlas : _idle;
            _image.texture = texture;
            _image.color = texture == null ? Color.clear : Color.white;
            if (_fallback != null) _fallback.SetActive(texture == null);
            if (texture == null) { _image.uvRect = new Rect(0, 0, 1, 1); return; }
            var uv = sheet ? FrameUv(FrameIndex, texture.width, texture.height) : new Rect(0, 0, 1, 1);
            var sourceLeft = _species == "road_sprout" || _species == "puddle_pip";
            if (sourceLeft != _facingLeft) { uv.x += uv.width; uv.width = -uv.width; }
            _image.uvRect = uv;
            if (_fit != null) _fit.aspectRatio = sheet ? (texture.width / 4f) / (texture.height / 2f) : (float)texture.width / texture.height;
        }

        // Integer boundaries preserve every source pixel in the odd-sized 4 × 2 sheets.
        public static Rect FrameUv(int frame, int width, int height)
        {
            if (frame < 0 || frame >= 8) throw new ArgumentOutOfRangeException(nameof(frame));
            var column = frame % 4; var row = frame / 4;
            var left = column * width / 4; var right = (column + 1) * width / 4;
            var top = row * height / 2; var bottom = (row + 1) * height / 2;
            return new Rect(left / (float)width, 1 - bottom / (float)height,
                (right - left) / (float)width, (bottom - top) / (float)height);
        }

        static bool Cached(string path, out Texture2D texture)
        {
            texture = null;
            return !string.IsNullOrEmpty(path) && Textures.TryGetValue(path, out texture) && texture != null;
        }

#if UNITY_EDITOR
        static Texture2D ReadEditor(string path, bool sheet)
        {
            if (string.IsNullOrEmpty(path)) return null;
            if (Cached(path, out var cached)) return cached;
            var root = Path.GetFullPath(Path.Combine(Application.dataPath, "../../../phone/assets"));
            var file = Path.Combine(root, path);
            return File.Exists(file) ? Decode(File.ReadAllBytes(file), path, sheet) : null;
        }
#else
        IEnumerator LoadBinding(int binding, string idlePath, string atlasPath)
        {
            Texture2D idle = null;
            yield return Fetch(idlePath, false, texture => idle = texture);
            if (this == null || binding != _binding) yield break;
            _idle = idle;
            Refresh();
            Texture2D atlas = null;
            yield return Fetch(atlasPath, true, texture => atlas = texture);
            if (this == null || binding != _binding) yield break;
            _atlas = atlas;
            _loadComplete = true;
            _loading = false;
            Refresh();
        }

        static IEnumerator Fetch(string path, bool sheet, Action<Texture2D> done)
        {
            if (string.IsNullOrEmpty(path)) yield break;
            if (Cached(path, out var cached)) { done(cached); yield break; }
            var url = Application.streamingAssetsPath + "/flutter_assets/assets/" + path;
            if (!url.Contains("://")) url = new Uri(url).AbsoluteUri;
            using var request = UnityWebRequest.Get(url);
            yield return request.SendWebRequest();
            if (request.result != UnityWebRequest.Result.Success) yield break;
            // Concurrent actors can finish the same request; decode and upload only once.
            if (Cached(path, out cached)) { done(cached); yield break; }
            var texture = Decode(request.downloadHandler.data, path, sheet);
            if (texture != null) done(texture);
        }
#endif

        static Texture2D Decode(byte[] png, string path, bool sheet)
        {
            var texture = new Texture2D(2, 2, TextureFormat.RGBA32, false)
            { name = path, wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            if (!texture.LoadImage(png) || (sheet && (texture.width < 4 || texture.height < 2)))
            {
                if (Application.isPlaying) Destroy(texture); else DestroyImmediate(texture);
                return null;
            }
            if (sheet)
            {
                // Match the car's alpha cutoff, keeping RGB straight for the UI shader.
                var pixels = texture.GetPixels32();
                for (var i = 0; i < pixels.Length; i++)
                    pixels[i].a = (byte)Mathf.Clamp(Mathf.RoundToInt((pixels[i].a - 32) * 255f / 223), 0, 255);
                texture.SetPixels32(pixels);
            }
            texture.Apply(false, true);
            Textures[path] = texture;
            return texture;
        }
    }
}
