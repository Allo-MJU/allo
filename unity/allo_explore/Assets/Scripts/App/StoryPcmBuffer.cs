using System;

namespace Allo.App
{
    // Audio thread and Unity download callbacks share this bounded queue.
    // PCM is signed 16-bit little endian, mono, 24 kHz (not network-endian L16).
    public sealed class StoryPcmBuffer
    {
        readonly float[] _samples;
        readonly object _gate = new object();
        int _read, _count, _low = -1;
        long _framesRead, _lastDataEndFrame;
        bool _closed, _failed;
        public StoryPcmBuffer(int capacity = 24000 * 60) { _samples = new float[capacity]; }
        public int Count { get { lock (_gate) return _count; } }
        public long LastDataEndFrame { get { lock (_gate) return _lastDataEndFrame; } }
        public bool Failed { get { lock (_gate) return _failed; } }
        public bool Append(byte[] data, int length)
        {
            lock (_gate)
            {
                if (_closed || _failed) return false;
                for (var i = 0; i < length; i++)
                {
                    if (_low < 0) { _low = data[i]; continue; }
                    if (_count == _samples.Length) { _failed = true; return false; }
                    var value = (short)(_low | (data[i] << 8)); _low = -1;
                    _samples[(_read + _count) % _samples.Length] = value / 32768f;
                    _count++;
                }
                return true;
            }
        }
        public void Read(float[] output)
        {
            lock (_gate)
            {
                Array.Clear(output, 0, output.Length);
                if (_closed) return;
                var n = Math.Min(output.Length, _count);
                for (var i = 0; i < n; i++) output[i] = _samples[(_read + i) % _samples.Length];
                if (n > 0) _lastDataEndFrame = _framesRead + n;
                _framesRead += output.Length;
                _read = (_read + n) % _samples.Length; _count -= n;
            }
        }
        public bool Finish() { lock (_gate) { if (_low >= 0) _failed = true; return !_failed; } }
        public void Cancel() { lock (_gate) { _closed = true; _count = 0; _low = -1; } }
    }
}
