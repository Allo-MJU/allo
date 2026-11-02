package ai.allo.car.vehicle

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SignalDerivationTest {
    @Test fun `hard deceleration counts once per event`() {
        val d = SignalDerivation()
        d.update(0, 60.0, 0.0, null)
        d.update(1_000, 40.0, 0.0, null)   // -20 kph/s → 급제동
        d.update(2_000, 25.0, 0.0, null)   // 쿨다운 안 → 안 셈
        d.update(5_000, 25.0, 0.0, null)
        d.update(6_000, 5.0, 0.0, null)    // 두 번째
        assertEquals(2, d.harshBrakeCount)
    }

    @Test fun `steering at parking speed is ignored`() {
        val d = SignalDerivation()
        d.update(0, 5.0, 0.0, null)
        d.update(1_000, 5.0, 200.0, null)
        assertEquals(0, d.harshSteerCount)
        d.update(2_000, 40.0, 200.0, null)
        d.update(3_000, 40.0, 20.0, null)  // 180 deg/s at 40kph
        assertEquals(1, d.harshSteerCount)
    }

    @Test fun `distance falls back to speed integration when odometer is flat`() {
        val d = SignalDerivation()
        d.update(0, 36.0, null, 1000.0)
        d.update(1_000, 36.0, null, 1000.0)   // 오도미터 안 변함 → 10m/s 적분
        d.update(2_000, 36.0, null, 1000.0)
        assertEquals(20.0, d.distanceM, 0.01)
        d.update(3_000, 36.0, null, 2000.0)   // 오도미터 1km 점프 → 델타 사용
        assertEquals(1020.0, d.distanceM, 0.01)
    }

    @Test fun `reset clears everything`() {
        val d = SignalDerivation()
        d.update(0, 60.0, 0.0, null); d.update(1_000, 0.0, 0.0, null)
        d.reset()
        assertEquals(0, d.harshBrakeCount); assertTrue(d.distanceM == 0.0)
    }
}
