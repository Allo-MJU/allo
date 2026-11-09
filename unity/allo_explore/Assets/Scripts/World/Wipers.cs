using UnityEngine;

namespace Allo.World
{
    /// 앞유리 와이퍼 두 개. 비(1~3단)에 맞춰 왕복하고, 비가 그치면 아래로 돌아간다.
    /// 날개는 pivot 의 로컬 +y 방향으로 뻗고, 로컬 z(유리 법선) 축으로 돈다. 장면 빌드(AlloBuild)가 유리 크기에 맞춰 만든다.
    public sealed class Wipers : MonoBehaviour
    {
        public Transform left, right;
        [Tooltip("쉴 때 각도 (유리 아래 가장자리에 누움)")] public float parkDeg = 72;
        [Tooltip("왕복 폭 (도)")] public float sweepDeg = 118;

        int _rain;
        float _phase;   // 0~1 왕복 위상 (0 = 쉼)
        float _target;  // 비가 그치면 0 으로 돌아간다

        public void SetRain(int level)
        {
            _rain = Mathf.Clamp(level, 0, 3);
            // 재생 중이 아니면(에디터 캡처) 비 올 때 중간쯤 멈춰 보여 준다
            if (!Application.isPlaying) Pose(_rain > 0 ? 0.38f : 0);
        }

        void Update()
        {
            if (_rain > 0)
            {
                var cyclesPerSec = 0.35f + 0.3f * _rain;
                _phase = Mathf.Repeat(_phase + Time.deltaTime * cyclesPerSec, 1);
                Pose(0.5f - 0.5f * Mathf.Cos(_phase * Mathf.PI * 2));
            }
            else if (_target > 0.001f)
            {
                _target = Mathf.MoveTowards(_target, 0, Time.deltaTime * 1.2f);
                Pose(_target);
            }
        }

        /// 0 = 쉼, 1 = 가장 멀리 올라감
        public void Pose(float t)
        {
            _target = t;
            var a = parkDeg - sweepDeg * t;
            if (left != null) left.localRotation = Quaternion.AngleAxis(a, Vector3.forward);
            if (right != null) right.localRotation = Quaternion.AngleAxis(a, Vector3.forward);
        }
    }
}
