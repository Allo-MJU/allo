package ai.allo.car.navi

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** schema.md 3.3: etaSec 는 "내비 미사용 시 null". 폰은 null 이면 거리 폴백. */
class NaviEtaTest {
    @Test fun `route guidance with remaining time gives eta seconds`() {
        assertEquals(1_800L, NaviEta.etaSec(status = "ROUTE_DRIVE", remainSec = 1_800))
    }

    @Test fun `free drive or inactive navigation gives null`() {
        assertNull(NaviEta.etaSec(status = "FREE_DRIVE", remainSec = 1_800))
        assertNull(NaviEta.etaSec(status = "INACTIVE", remainSec = 1_800))
        assertNull(NaviEta.etaSec(status = null, remainSec = 1_800))
    }

    @Test fun `zero or missing remaining time gives null`() {
        assertNull(NaviEta.etaSec(status = "ROUTE_DRIVE", remainSec = 0))
        assertNull(NaviEta.etaSec(status = "ROUTE_DRIVE", remainSec = null))
    }
}
