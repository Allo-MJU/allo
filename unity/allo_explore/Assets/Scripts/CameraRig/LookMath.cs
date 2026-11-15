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

        /// 화면 방향 보정이 적용된 센서의 오른손 좌표계를 Unity 카메라의 왼손 좌표계로 바꾼다.
        public static bool TryAttitude(Quaternion sensor, out Quaternion attitude)
        {
            var lengthSquared = Quaternion.Dot(sensor, sensor);
            attitude = Quaternion.identity;
            if (!(lengthSquared >= .5f && lengthSquared <= 1.5f)) return false;
            attitude = new Quaternion(sensor.x, sensor.y, -sensor.z, -sensor.w).normalized;
            return true;
        }

        public static LookState GyroTarget(LookState state, Quaternion neutral, Quaternion current)
        {
            var forward = Quaternion.Inverse(neutral) * current * Vector3.forward;
            var target = Toward(state, Vector3.zero, forward, 0);
            // 정수리 방향에서는 수평 방향을 읽을 수 없다.
            if (forward.x * forward.x + forward.z * forward.z < 1e-6f) target.yaw = state.yaw;
            return target;
        }

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
