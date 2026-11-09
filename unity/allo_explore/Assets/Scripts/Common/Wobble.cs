using UnityEngine;

namespace Allo
{
    /// 탭하면 잠깐 흔들린다 (머리받침·쿠션·인형·물병·손잡이). 원래 자세로 돌아온다.
    public sealed class Wobble : MonoBehaviour
    {
        [Tooltip("흔들리는 각도 (도)")] public float angle = 10;
        [Tooltip("커졌다 작아지는 비율")] public float scale = 0.08f;
        [Tooltip("몇 번 왕복할지")] public float swings = 3;
        public float seconds = 0.7f;

        float _t = -1;
        Quaternion _rot;
        Vector3 _scale;

        public bool Active => _t >= 0;

        public void Punch()
        {
            if (_t < 0)
            {
                _rot = transform.localRotation;
                _scale = transform.localScale;
            }
            _t = 0;
        }

        void Update()
        {
            if (_t < 0) return;
            _t += Time.deltaTime;
            var k = _t / seconds;
            if (k >= 1)
            {
                transform.localRotation = _rot;
                transform.localScale = _scale;
                _t = -1;
                return;
            }
            var d = Mathf.Sin(k * Mathf.PI * swings) * (1 - k);
            transform.localRotation = _rot * Quaternion.Euler(d * angle, 0, d * angle * 0.4f);
            transform.localScale = _scale * (1 + Mathf.Abs(d) * scale);
        }
    }
}
