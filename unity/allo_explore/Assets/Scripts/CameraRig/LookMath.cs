using UnityEngine;

namespace Allo.CameraRig
{
    /// 아이 시점 카메라 상태. yaw 는 [0,360), pitch 는 ±PitchLimit, rail 은 0(뒷좌석)~1(앞좌석 사이).
    public struct LookState
    {
        public float yaw;
        public float pitch;
        public float rail;
    }

    /// 둘러보기 계산. 순수 함수라 EditMode 테스트로 확인한다.
    /// 설계 2.1: 좌우 360도, 위아래 ±35도, 앞뒤는 뒷좌석↔앞좌석 레일 위에서만.
    public static class LookMath
    {
        public const float PitchLimit = 35f;

        /// 자이로는 손가락 조작을 거드는 정도로만 작게 더한다 (멀미 방지)
        public const float GyroScale = 0.3f;

        public static LookState Drag(LookState s, Vector2 deltaDegrees)
        {
            s.yaw = Mathf.Repeat(s.yaw + deltaDegrees.x, 360f);
            s.pitch = Mathf.Clamp(s.pitch + deltaDegrees.y, -PitchLimit, PitchLimit);
            return s;
        }

        public static LookState Pinch(LookState s, float deltaRail)
        {
            s.rail = Mathf.Clamp01(s.rail + deltaRail);
            return s;
        }

        public static LookState AddGyro(LookState s, Vector2 gyroDegrees, bool enabled) =>
            enabled ? Drag(s, gyroDegrees * GyroScale) : s;

        /// eye 에서 point 를 보는 yaw·pitch (baseYaw 를 0 으로). pitch 는 ±PitchLimit 안으로, rail 은 그대로
        public static LookState Toward(LookState s, Vector3 eye, Vector3 point, float baseYaw)
        {
            var d = point - eye;
            var flat = new Vector2(d.x, d.z).magnitude;
            s.yaw = Mathf.Repeat(Mathf.Atan2(d.x, d.z) * Mathf.Rad2Deg - baseYaw, 360f);
            s.pitch = Mathf.Clamp(Mathf.Atan2(d.y, Mathf.Max(flat, 1e-4f)) * Mathf.Rad2Deg, -PitchLimit, PitchLimit);
            return s;
        }

        /// a → b 를 k(0~1) 만큼. yaw 는 짧은 쪽으로 돈다
        public static LookState Blend(LookState a, LookState b, float k)
        {
            a.yaw = Mathf.Repeat(a.yaw + Mathf.DeltaAngle(a.yaw, b.yaw) * k, 360f);
            a.pitch = Mathf.Lerp(a.pitch, b.pitch, k);
            a.rail = Mathf.Lerp(a.rail, b.rail, k);
            return a;
        }

        public static Vector3 RailPosition(float rail, Vector3 rear, Vector3 front) =>
            Vector3.Lerp(rear, front, Mathf.Clamp01(rail));
    }
}
