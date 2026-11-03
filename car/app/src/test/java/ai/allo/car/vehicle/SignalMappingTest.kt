package ai.allo.car.vehicle

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SignalMappingTest {
    // --- wiperLevel: docs/verification.md #1 제안 매핑 ---

    @Test fun `wiper off and single-wipe modes are level 0`() {
        for (s in listOf("OFF", "MIST", "OTHER", "SERVICE")) {
            assertEquals(0, SignalMapping.wiperLevel(s, wiperOn = true), s)
        }
    }

    @Test fun `intermittent wiper is level 1`() {
        for (n in 1..5) assertEquals(1, SignalMapping.wiperLevel("INTERMITTENT_LEVEL_$n", wiperOn = true))
    }

    @Test fun `continuous wiper 1-2 is level 2 and 3-5 is level 3`() {
        assertEquals(2, SignalMapping.wiperLevel("CONTINUOUS_LEVEL_1", wiperOn = true))
        assertEquals(2, SignalMapping.wiperLevel("CONTINUOUS_LEVEL_2", wiperOn = true))
        for (n in 3..5) assertEquals(3, SignalMapping.wiperLevel("CONTINUOUS_LEVEL_$n", wiperOn = true))
    }

    @Test fun `auto wiper counts as rain only while actually wiping`() {
        assertEquals(1, SignalMapping.wiperLevel("AUTO", wiperOn = true))
        assertEquals(0, SignalMapping.wiperLevel("AUTO", wiperOn = false))
        assertEquals(0, SignalMapping.wiperLevel("AUTO", wiperOn = null))
    }

    @Test fun `unknown switch falls back to wiper state`() {
        assertEquals(1, SignalMapping.wiperLevel(null, wiperOn = true))
        assertEquals(0, SignalMapping.wiperLevel(null, wiperOn = false))
        assertEquals(0, SignalMapping.wiperLevel(null, wiperOn = null))
    }

    // --- headlightOn: 실제 하향등 점등 상태 (#2) ---

    @Test fun `low beam on means headlight on`() {
        assertTrue(SignalMapping.headlightOn("ON"))
    }

    @Test fun `daytime running lights and off are not headlight on`() {
        assertFalse(SignalMapping.headlightOn("DAYTIME_RUNNING"))
        assertFalse(SignalMapping.headlightOn("OFF"))
        assertFalse(SignalMapping.headlightOn(null))
    }

    // --- odometer: SDK km(Float) → SignalDerivation m (#4) ---

    @Test fun `odometer km is converted to meters`() {
        assertEquals(13_257.0, SignalMapping.odometerM(13.257f)!!, 0.5)
        assertEquals(0.0, SignalMapping.odometerM(0f)!!, 0.0)
    }

    @Test fun `missing odometer stays null`() {
        assertNull(SignalMapping.odometerM(null))
    }
}
