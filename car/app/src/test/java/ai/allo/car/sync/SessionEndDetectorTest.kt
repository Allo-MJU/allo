package ai.allo.car.sync

import ai.allo.car.sync.SessionEndDetector.Reason
import kotlin.test.*

class SessionEndDetectorTest {
    private val min = 60_000L

    @Test fun `parked 3 minutes after driving ends the session once`() {
        val d = SessionEndDetector()
        assertNull(d.update(0, "D", 5_000.0, routeActive = false, arrived = false))
        assertNull(d.update(1_000, "P", 5_000.0, false, false))
        assertNull(d.update(1_000 + 3 * min - 1, "P", 5_000.0, false, false))
        assertEquals(Reason.PARKED, d.update(1_000 + 3 * min, "P", 5_000.0, false, false))
        assertNull(d.update(1_000 + 4 * min, "P", 5_000.0, false, false))   // 한 번만
    }

    @Test fun `leaving P restarts the hold`() {
        val d = SessionEndDetector()
        d.update(0, "P", 5_000.0, false, false)
        d.update(2 * min, "D", 5_000.0, false, false)
        assertNull(d.update(3 * min, "P", 5_000.0, false, false))
        assertNull(d.update(5 * min, "P", 5_000.0, false, false))
        assertEquals(Reason.PARKED, d.update(6 * min, "P", 5_000.0, false, false))
    }

    @Test fun `never ends before the car has driven`() {
        val d = SessionEndDetector()
        assertNull(d.update(0, "P", 0.0, false, false))
        assertNull(d.update(60 * min, "P", 99.0, false, false))
        assertNull(d.update(60 * min, "P", 0.0, false, arrived = true))
    }

    @Test fun `arrival ends as soon as the gear is P`() {
        val d = SessionEndDetector()
        assertNull(d.update(0, "D", 5_000.0, routeActive = true, arrived = true))
        assertEquals(Reason.ARRIVED, d.update(1_000, "P", 5_000.0, false, true))
    }

    @Test fun `a rest stop during route guidance waits 30 minutes`() {
        val d = SessionEndDetector()
        assertNull(d.update(0, "P", 5_000.0, routeActive = true, arrived = false))
        assertNull(d.update(10 * min, "P", 5_000.0, true, false))
        assertEquals(Reason.PARKED, d.update(30 * min, "P", 5_000.0, true, false))
    }

    @Test fun `reset allows the next session to end`() {
        val d = SessionEndDetector()
        d.update(0, "P", 5_000.0, false, true)
        d.reset()
        assertNull(d.update(1_000, "P", 0.0, false, false))
        assertEquals(Reason.ARRIVED, d.update(2_000, "P", 200.0, false, true))
    }
}
