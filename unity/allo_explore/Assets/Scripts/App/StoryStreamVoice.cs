using System;
using System.Collections;
using System.Text;
using Allo.Bridge;
using UnityEngine;
using UnityEngine.Networking;

namespace Allo.App
{
    [Serializable] public sealed class StoryVoiceConfig
    {
        public string requestId, baseUrl, token;
        // The embedded Unity library is exported as a release build; the Flutter host decides
        // whether it is a debug build that may use a loopback http gateway.
        public bool hostDebug;
    }

    public sealed class StoryStreamVoice : MonoBehaviour
    {
        [Serializable] sealed class Request { public string species, text; }
        sealed class PcmDownload : DownloadHandlerScript
        {
            readonly StoryPcmBuffer _buffer;
            public PcmDownload(StoryPcmBuffer buffer) : base(new byte[8192]) { _buffer = buffer; }
            protected override bool ReceiveData(byte[] data, int length) => data != null && _buffer.Append(data, length);
        }
        Coroutine _routine;
        UnityWebRequest _request;
        StoryPcmBuffer _buffer;
        AudioClip _clip;
        AudioSource _source;
        string _requestId;
        StoryVoiceConfig _config;
        int _generation;
        double _startedAtDspTime;

        public static bool ValidEndpoint(string value, bool development)
        {
            if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || !string.IsNullOrEmpty(uri.UserInfo) ||
                !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment)) return false;
            return uri.Scheme == "https" || (development && uri.Scheme == "http" &&
                (uri.Host == "10.0.2.2" || uri.Host == "127.0.0.1" || uri.Host == "localhost"));
        }
        void OnEnable() { FlutterBridge.StoryVoiceConfigured += Configure; }
        void OnDisable() { FlutterBridge.StoryVoiceConfigured -= Configure; Stop(); }
        void OnDestroy() { Stop(); }
        void Configure(StoryVoiceConfig config)
        {
            // Responses from previous utterances cannot start or replace playback.
            if (config?.requestId == _requestId) _config = config;
        }
        public void Play(string species, string text, Action fallback)
        {
            Stop();
            _requestId = Guid.NewGuid().ToString("N");
            _routine = StartCoroutine(Stream(_generation, species, text, fallback));
        }
        IEnumerator Stream(int generation, string species, string text, Action fallback)
        {
            FlutterBridge.Send("storyVoiceConfigRequest", FlutterBridge.Field("requestId", _requestId));
            var deadline = Time.realtimeSinceStartup + 5f;
            while (_config == null && Time.realtimeSinceStartup < deadline) yield return null;
            if (generation != _generation) yield break;
            var config = _config; _config = null; _requestId = null;
            if (config == null || string.IsNullOrEmpty(config.token) ||
                !ValidEndpoint(config.baseUrl, Debug.isDebugBuild || config.hostDebug))
            { fallback(); _routine = null; yield break; }
            _buffer = new StoryPcmBuffer();
            var buffer = _buffer;
            _request = new UnityWebRequest(config.baseUrl.TrimEnd('/') + "/v1/story/stream", "POST");
            _request.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(JsonUtility.ToJson(new Request { species = species, text = text })));
            _request.downloadHandler = new PcmDownload(buffer);
            _request.SetRequestHeader("Content-Type", "application/json");
            _request.SetRequestHeader("Authorization", "Bearer " + config.token);
            config.token = null;
            _request.redirectLimit = 0; // Never forward transient authorization to a redirected host.
            _request.timeout = 45;
            // SendWebRequest throws synchronously (e.g. insecure http blocked by Player Settings).
            // An exception would kill this coroutine silently, so fall back to the bundled clip.
            UnityWebRequestAsyncOperation operation = null;
            try { operation = _request.SendWebRequest(); }
            catch (InvalidOperationException) { }
            if (operation == null)
            {
                _request.Dispose(); _request = null; buffer.Cancel(); _buffer = null;
                fallback(); _routine = null; yield break;
            }
            var started = false;
            var firstAudioDeadline = Time.realtimeSinceStartup + 10f;
            while (!operation.isDone)
            {
                if (!started && ValidAudioResponse(_request) && buffer.Count >= 3600)
                { StartAudio(buffer); started = true; }
                if (buffer.Failed || (!started && Time.realtimeSinceStartup > firstAudioDeadline))
                { _request.Abort(); break; }
                yield return null;
            }
            var success = _request.result == UnityWebRequest.Result.Success && ValidAudioResponse(_request) && buffer.Finish();
            _request.Dispose(); _request = null;
            if (!started && success && buffer.Count > 0) { StartAudio(buffer); started = true; }
            if (!started) { buffer.Cancel(); fallback(); }
            else
            {
                // Do not restart local speech after a partially heard network utterance.
                while (buffer.Count > 0) yield return null;
                // Queue-empty means samples were handed to Unity, not yet heard. Include
                // underrun silence in the source timeline and wait for the final handed-off
                // frame plus the device DSP buffers; a fixed short delay truncates the tail.
                AudioSettings.GetDSPBufferSize(out var dspLength, out var dspCount);
                var deviceLatency = (double)dspLength * dspCount / Math.Max(1, AudioSettings.outputSampleRate);
                var tailEnd = _startedAtDspTime + (double)buffer.LastDataEndFrame / 24000 + deviceLatency;
                while (AudioSettings.dspTime < tailEnd) yield return null;
                ClearAudio();
            }
            _buffer = null; _routine = null;
        }
        static bool ValidAudioResponse(UnityWebRequest request) => ValidAudioHeaders(request.responseCode,
            request.GetResponseHeader("Content-Type"), request.GetResponseHeader("X-Audio-Format"),
            request.GetResponseHeader("X-Audio-Sample-Rate"), request.GetResponseHeader("X-Audio-Channels"));
        public static bool ValidAudioHeaders(long status, string type, string format, string rate, string channels) =>
            status == 200 && (type ?? "").Split(';')[0].Trim().Equals("application/octet-stream", StringComparison.OrdinalIgnoreCase) &&
            format == "s16le" && rate == "24000" && channels == "1";
        void StartAudio(StoryPcmBuffer buffer)
        {
            if (_source == null)
            {
                _source = gameObject.AddComponent<AudioSource>();
                _source.playOnAwake = false; _source.spatialBlend = 0;
            }
            _clip = AudioClip.Create("Story stream", 24000, 1, 24000, true, buffer.Read);
            _source.loop = true; _source.clip = _clip;
            _startedAtDspTime = AudioSettings.dspTime;
            _source.Play();
        }
        void ClearAudio()
        {
            if (_source != null) { _source.Stop(); _source.clip = null; }
            if (_clip != null) { Destroy(_clip); _clip = null; }
        }
        public void Stop()
        {
            _generation++; _requestId = null;
            if (_config != null) _config.token = null;
            _config = null;
            if (_routine != null) { StopCoroutine(_routine); _routine = null; }
            _request?.Abort(); _request?.Dispose(); _request = null;
            _buffer?.Cancel(); _buffer = null;
            ClearAudio();
        }
    }
}
