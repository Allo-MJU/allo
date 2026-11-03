package ai.allo.car.vehicle

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** 검증 #8: SDK 는 점유를 false, 빈자리를 true 로 준다 (SDK_OCCUPIED = false). */
class SeatPolarityTest {
    @Test fun `any row 2 seat occupied counts as occupied`() {
        // ROW_2_LEFT 빈자리(true), ROW_2_RIGHT 점유(false) — 에뮬레이터 실측 값 그대로
        assertTrue(SeatPolarity.anyOccupied(listOf(true, false)))
    }

    @Test fun `all row 2 seats empty is not occupied`() {
        assertFalse(SeatPolarity.anyOccupied(listOf(true, true, true)))
    }

    @Test fun `unknown seat values are not occupied`() {
        assertFalse(SeatPolarity.anyOccupied(listOf(null, null)))
        assertFalse(SeatPolarity.anyOccupied(emptyList()))
    }
}
