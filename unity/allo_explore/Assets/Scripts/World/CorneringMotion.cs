using Allo.Bridge;
using UnityEngine;

namespace Allo.World
{
    public sealed class CorneringMotion
    {
        long _lastStamp;
        double _expiresAt;
        bool _present;
        float _visual;
        public float Bend { get; private set; }

        public bool Receive(CorneringState sample, long nowMs, double elapsed)
        {
            if (sample == null || sample.version != 1 || float.IsNaN(sample.bend) ||
                sample.bend < -1 || sample.bend > 1 || sample.receivedAtMs <= 0)
            {
                _present = false;
                return false;
            }
            if (sample.receivedAtMs <= _lastStamp) return false;
            var ageMs = nowMs - sample.receivedAtMs;
            if (ageMs < -1000 || ageMs > 5000)
            {
                _present = false;
                return false;
            }
            _lastStamp = sample.receivedAtMs;
            Bend = sample.bend;
            _expiresAt = elapsed + System.Math.Min(3.5, (5000 - ageMs) / 1000.0);
            _present = true;
            return true;
        }

        public bool Active(double elapsed, bool moving)
        {
            if (!moving || elapsed > _expiresAt) _present = false;
            return _present;
        }

        public float Step(bool showBend, float dt)
        {
            _visual = Mathf.Lerp(_visual, showBend ? Bend : 0, 1 - Mathf.Exp(-5 * dt));
            return _visual;
        }
    }
}
