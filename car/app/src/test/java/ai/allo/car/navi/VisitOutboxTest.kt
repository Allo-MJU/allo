package ai.allo.car.navi
import kotlin.test.*
class VisitOutboxTest {
    @Test fun `failed delivery remains durable and success removes only matching visit`() {
        var stored = "[]"
        val v = DestinationVisit("s", "visit_a", "route_a", "unknown_a", "A", "unknown", 1, emptyList())
        var box = VisitOutbox({stored}, { stored = it; true })
        assertTrue(box.add(v)); assertTrue(box.add(v)); assertEquals(1, box.pending().size)
        box = VisitOutbox({stored}, { stored = it; true })
        assertEquals(v, box.pending().single())
        box.remove("different"); assertEquals(1, box.pending().size)
        box.remove(v.visitId); assertTrue(box.pending().isEmpty())
    }
    @Test fun `failed commit with updated memory is committed again before fallback is removed`() {
        var disk = "[]"
        var memory = disk
        var fail = true
        val v = DestinationVisit("s", "visit_a", "route_a", "unknown_a", "A", "unknown", 1, emptyList())
        val box = VisitOutbox({ memory }, { value ->
            memory = value
            if (fail) false else { disk = value; true }
        })
        assertFalse(box.add(v))
        assertEquals(listOf(v), box.pending())
        fail = false
        assertTrue(box.add(v))
        memory = disk
        val restarted = VisitOutbox({ memory }, { value -> memory = value; disk = value; true })
        assertEquals(listOf(v), restarted.pending())
    }
}
