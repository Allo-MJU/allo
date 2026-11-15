package ai.allo.car.vehicle

import ai.allo.car.model.VehicleSnapshot
import ai.allo.car.sync.FirebaseRest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import kotlin.test.*

class CorneringSignalTest {
    private val signal = CorneringSignal()
    private fun read(now: Long = 1000, gear: String = "D", speed: Double = 30.0,
                     supported: Boolean = true, fresh: Boolean = true) =
        signal.snapshot(now, gear, speed, supported, fresh)

    @Test fun `normalizes observed SDK sign and saturates for visual bend`() {
        signal.accept(-60.0, 1000)
        assertEquals(0.5, read()!!.bend)
        signal.accept(60.0, 1000)
        assertEquals(-0.5, read()!!.bend)
        signal.accept(-500.0, 1000)
        assertEquals(1.0, read()!!.bend)
        signal.accept(500.0, 1000)
        assertEquals(-1.0, read()!!.bend)
        assertEquals(1, read()!!.version)
        assertEquals(1000, read()!!.receivedAtMs)
    }

    @Test fun `neutral deadzone stays straight`() {
        for (angle in listOf(-3.0, 0.0, 3.0)) {
            signal.accept(angle, 1000)
            assertEquals(0.0, read()!!.bend)
        }
    }

    @Test fun `only moving forward with supported fresh speed is eligible`() {
        signal.accept(-60.0, 1000)
        for (gear in listOf("P", "R", "N", "?")) assertNull(read(gear = gear))
        for (speed in listOf(-10.0, 0.0, 2.0, Double.NaN, 401.0)) assertNull(read(speed = speed))
        assertNull(read(supported = false))
        assertNull(read(fresh = false))
        assertNotNull(read(speed = 2.01))
    }

    @Test fun `stale future and invalid receive times are rejected`() {
        signal.accept(60.0, 1000)
        assertNotNull(read(now = 3500))
        assertNull(read(now = 3501))
        assertNull(read(now = 999))
        signal.accept(60.0, 0)
        assertNull(read())
    }

    @Test fun `null invalid readings and SDK failure discard earlier bend`() {
        for (bad in listOf(null, Double.NaN, Double.POSITIVE_INFINITY, 1080.01, -1080.01)) {
            signal.accept(60.0, 1000)
            signal.accept(bad, 1001)
            assertNull(read(now = 1001))
        }
        signal.accept(60.0, 1000)
        signal.invalidate()
        assertNull(read())
    }

    @Test fun `wire omits absent cornering and contains only version bend and receive time`() {
        val json = FirebaseRest("").json
        val base = VehicleSnapshot(1, "D", 30.0, 0.0, 0, 0, 0, false, false,
            envTags = emptyList(), capabilities = listOf("steering"))
        assertFalse("cornering" in Json.parseToJsonElement(json.encodeToString(base)).jsonObject)
        signal.accept(-60.0, 1000)
        val wire = Json.parseToJsonElement(json.encodeToString(base.copy(cornering = read()))).jsonObject
        assertEquals(setOf("version", "bend", "receivedAtMs"), wire.getValue("cornering").jsonObject.keys)
        val old = json.decodeFromString<VehicleSnapshot>(json.encodeToString(base))
        assertNull(old.cornering)
    }
    @Test fun `snapshot reads current clock after a callback instead of publish loop time`() {
        var now = 1000L
        val signal = CorneringSignal { now }
        val publishLoopTime = now
        now = 1001
        signal.receive(-60.0)
        assertEquals(1001L, signal.snapshotCurrent("D", 30.0, true, true)!!.receivedAtMs)
        assertNull(signal.snapshot(publishLoopTime, "D", 30.0, true, true))
        now = 999 // A genuinely future receipt must still be rejected.
        assertNull(signal.snapshotCurrent("D", 30.0, true, true))
    }

    @Test fun `queued 1200ms getter callbacks survive a new poll every second`() {
        var now = 1000L
        val signal = CorneringSignal { now }
        val callbacks = ArrayDeque<() -> Unit>()
        fun poll(angle: Double) {
            val request = signal.beginRead()
            callbacks.addLast { signal.completeRead(request, angle) }
        }
        poll(-60.0)
        now = 2000; poll(-120.0)
        now = 2200; callbacks.removeFirst()()
        assertEquals(0.5, signal.snapshotCurrent("D", 30.0, true, true)!!.bend)
        now = 3000; poll(-30.0)
        now = 3200; callbacks.removeFirst()()
        assertEquals(1.0, signal.snapshotCurrent("D", 30.0, true, true)!!.bend)
    }

    @Test fun `older completions cannot overwrite newer completion listener failure or stop`() {
        var now = 1000L
        val signal = CorneringSignal { now }
        fun bend() = signal.snapshotCurrent("D", 30.0, true, true)?.bend
        val older = signal.beginRead(); val newer = signal.beginRead()
        signal.completeRead(newer, -120.0)
        signal.completeRead(older, 60.0)
        assertEquals(1.0, bend())
        signal.failRead(older)
        assertEquals(1.0, bend())
        val beforeListener = signal.beginRead()
        signal.receive(-30.0)
        signal.completeRead(beforeListener, 120.0)
        assertEquals(0.25, bend())
        val beforeFailure = signal.beginRead()
        signal.invalidate() // Shared listener failure and stop path.
        signal.completeRead(beforeFailure, 120.0)
        assertNull(bend())
        val failed = signal.beginRead(); val pending = signal.beginRead()
        signal.failRead(failed)
        signal.completeRead(pending, 120.0)
        assertNull(bend())
        val timedOut = signal.beginRead()
        now = 3501
        signal.completeRead(timedOut, 120.0)
        assertNull(bend())
    }

}
