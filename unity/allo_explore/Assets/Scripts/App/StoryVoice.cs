using System;
using UnityEngine;

namespace Allo.App
{
    [Serializable] public sealed class StoryVoiceEntry
    {
        public string topicId, nodeId, text, species, resource;
    }
    [Serializable] public sealed class StoryVoiceCatalog
    {
        public StoryVoiceEntry[] entries = Array.Empty<StoryVoiceEntry>();
        public StoryVoiceEntry Find(StoryState story) => story == null ? null :
            Array.Find(entries, e => e.topicId == story.topicId && e.nodeId == story.nodeId && e.text == story.line);
    }

    // Tracks presentation transitions, independently of rapidly changing vehicle revisions.
    public sealed class StoryVoiceCursor
    {
        string _key;
        public bool Enter(StoryState story, bool visible)
        {
            if (!visible || story == null) { _key = null; return false; }
            var key = story.instanceId + ":" + story.topicId + ":" + story.nodeId + ":" + story.line;
            if (_key == key) return false;
            _key = key; return true;
        }
    }

    public sealed class StoryVoice : MonoBehaviour
    {
        StoryVoiceCatalog _catalog;
        readonly StoryVoiceCursor _cursor = new StoryVoiceCursor();
        AudioSource _source;
        StoryStreamVoice _stream;
        bool _paused;
        public StoryVoiceEntry Entry(StoryState state)
        {
            if (_catalog == null)
            {
                var json = Resources.Load<TextAsset>("StoryVoice/catalog");
                _catalog = json == null ? new StoryVoiceCatalog() : JsonUtility.FromJson<StoryVoiceCatalog>(json.text);
            }
            return _catalog.Find(state);
        }
        public string Narrator(StoryState state)
        {
            Entry(state);
            return state == null ? null : Array.Find(_catalog.entries, e => e.topicId == state.topicId)?.species;
        }
        public void Present(StoryState state, bool visible)
        {
            visible = visible && !_paused;
            if (!visible) { _cursor.Enter(null, false); Stop(); return; }
            if (!_cursor.Enter(state, true)) return;
            Stop();
            var entry = Entry(state);
            if (!Application.isPlaying) return;
            var narrator = Narrator(state);
            if (narrator == null || string.IsNullOrEmpty(state?.line)) return;
            if (_stream == null) _stream = gameObject.AddComponent<StoryStreamVoice>();
            _stream.Play(narrator, state.line, () => PlayLocal(entry));
        }
        void PlayLocal(StoryVoiceEntry entry)
        {
            if (entry == null) return;
            var clip = Resources.Load<AudioClip>(entry.resource);
            if (clip == null) return;
            if (_source == null)
            {
                _source = gameObject.AddComponent<AudioSource>();
                _source.playOnAwake = false; _source.loop = false; _source.spatialBlend = 0;
            }
            _source.clip = clip; _source.Play();
        }
        public void Stop()
        {
            _stream?.Stop();
            if (_source == null) return;
            _source.Stop(); _source.clip = null;
        }
        void OnApplicationPause(bool paused) { _paused = paused; if (paused) Present(null, false); }
        void OnDisable() { Present(null, false); }
        void OnDestroy() { Stop(); }
    }
}
