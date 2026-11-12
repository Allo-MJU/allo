package ai.allo.car.model

import kotlin.test.*

class PairingRefreshTest {
    @Test fun `only a ready unpaired parked session can request a new code`() {
        val c = PairingRefresh { "request" }
        assertNull(c.begin("s", true, true, false, true))
        assertNull(c.begin("s", false, false, false, true))
        assertNull(c.begin("s", false, true, true, true))
        assertNull(c.begin("s", false, true, false, false))
        assertNotNull(c.begin("s", false, true, false, true))
        assertTrue(c.ui.busy)
        assertNull(c.begin("s", false, true, false, true))
    }
    @Test fun `uncertain result retries same request and cannot reset an established pairing`() {
        var counter = 0
        val c = PairingRefresh { "id-${++counter}" }
        val first = c.begin("s", false, true, false, true)!!
        c.complete(first, false)
        assertNotNull(c.ui.message)
        assertNull(c.begin("s", true, true, false, true))
        val retry = c.begin("s", false, true, false, true)!!
        assertEquals(first, retry)
        c.complete(retry, true)
        assertNull(c.ui.message)
        assertNotEquals(first.requestId, c.begin("s", false, true, false, true)!!.requestId)
    }
    @Test fun `old session completion cannot change new request`() {
        val c = PairingRefresh { "id" }
        val old = c.begin("s1", false, true, false, true)!!
        c.reset()
        c.begin("s2", false, true, false, true)
        c.complete(old, true)
        assertTrue(c.ui.busy)
    }
}
