package ai.allo.car.gleo

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DestinationSuggesterTest {
    @Test fun `fallback picks first region that is not current`() {
        assertEquals("coast", DestinationSuggester.pick(null)!!.destination.region)
        assertEquals("coast", DestinationSuggester.pick("city")!!.destination.region)
        assertEquals("mountain", DestinationSuggester.pick("coast")!!.destination.region)
        assertFalse(DestinationSuggester.pick("city")!!.unvisited)
    }

    @Test fun `unvisited list wins over fallback and skips current region`() {
        val s = DestinationSuggester.pick("mountain", listOf("mountain", "city"))!!
        assertEquals("city", s.destination.region)
        assertTrue(s.unvisited)
    }

    @Test fun `empty unvisited list means nothing to suggest`() {
        assertNull(DestinationSuggester.pick("city", emptyList()))
    }

    @Test fun `accept returns offered destination once`() {
        val flow = DestinationFlow(now = { 0L })
        val offered = flow.offer("city")!!.destination
        assertEquals(offered, flow.accept())
        assertNull(flow.accept())
    }

    @Test fun `accept without offer or after ttl is rejected`() {
        assertNull(DestinationFlow().accept())
        var t = 0L
        val flow = DestinationFlow(now = { t }, ttlMs = 1_000)
        flow.offer("city")
        t = 1_001
        assertNull(flow.accept())
    }
}
