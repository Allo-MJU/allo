package ai.allo.car.navi

import ai.allo.car.gleo.DestinationSuggester
import kotlin.test.*

class DestinationVisitTrackerTest {
    @Test fun `arrival requires current route and matching name and is recorded once`() {
        val t = DestinationVisitTracker { "route_1234567890abcdef" }
        val d = DestinationSuggester.CANDIDATES.first()
        t.start("session")
        t.destination("session", d.name, "", "", "", d.latitude, d.longitude)
        assertNull(t.arrive("other", d.name, 123, emptyList()))
        assertNull(t.arrive("session", "different", 123, emptyList()))
        val visit = assertNotNull(t.arrive("session", d.name, 123, listOf("creature-1")))
        assertEquals(d.placeId, visit.placeId)
        assertEquals(listOf("creature-1"), visit.companionIds)
        assertNull(t.arrive("session", d.name, 123, emptyList()))
    }
    @Test fun `changed or cancelled route invalidates previous destination`() {
        val t = DestinationVisitTracker { "route_1234567890abcdef" }
        t.start("s"); t.destination("s", "A", "provider", "one", "", 0.0, 0.0)
        t.destination("s", "B", "provider", "two", "", 0.0, 0.0)
        assertNull(t.arrive("s", "A", 1, emptyList()))
        t.cancel(); assertNull(t.arrive("s", "B", 1, emptyList()))
    }
    @Test fun `unidentified place has unique route identity rather than name matching`() {
        val t = DestinationVisitTracker { "route_1234567890abcdef" }
        t.start("s"); t.destination("s", "A", "", "", "", 0.0, 0.0)
        val v = assertNotNull(t.arrive("s", "A", 1, emptyList()))
        assertTrue(v.placeId.startsWith("unknown_")); assertEquals("unknown", v.regionTag)
    }
    @Test fun `accepted catalog route tolerates snapped SDK point without matching unrelated namesake`() {
        val d = DestinationSuggester.CANDIDATES.first()
        val t = DestinationVisitTracker { "route_1234567890abcdef" }
        t.expect(d); t.start("s")
        t.destination("s", d.name, "nav", "poi", "", d.latitude + 0.0018, d.longitude)
        assertEquals(d.placeId, t.arrive("s", d.name, 100, emptyList())!!.placeId)
        t.expect(d); t.start("s")
        t.destination("s", d.name, "nav", "different", "", d.latitude + 0.02, d.longitude)
        assertNotEquals(d.placeId, t.arrive("s", d.name, 101, emptyList())!!.placeId)
    }
    @Test fun `ended route waits briefly for actual arrival but cancel and new routes invalidate`() {
        var elapsed = 100L
        val t = DestinationVisitTracker(newRevision = { "route_1234567890abcdef" }, elapsedMs = { elapsed })
        t.start("s"); t.destination("s", "A", "p", "id", "", 0.0, 0.0); t.end()
        elapsed += 1000
        assertNotNull(t.arrive("s", "A", 1, emptyList()))
        t.start("s"); t.destination("s", "A", "p", "id", "", 0.0, 0.0); t.end(); elapsed += 30_001
        assertNull(t.arrive("s", "A", 1, emptyList()))
        t.start("s"); t.destination("s", "A", "p", "id", "", 0.0, 0.0); t.end(); t.cancel()
        assertNull(t.arrive("s", "A", 1, emptyList()))
        t.start("s"); t.destination("s", "A", "p", "id", "", 0.0, 0.0); t.end(); t.start("s")
        assertNull(t.arrive("s", "A", 1, emptyList()))
    }
}
