package ai.allo.car.vehicle

import java.time.*
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class EnvTaggerTest {
    private val zone = ZoneId.of("Asia/Seoul")
    private fun at(h: Int, m: Int = 0) = ZonedDateTime.of(LocalDate.of(2026, 11, 10), LocalTime.of(h, m), zone).toInstant().toEpochMilli()

    @Test fun `wiper on means rain`() {
        assertTrue("rain" in EnvTagger().tags(at(14), 50.0, 1, false))
        assertFalse("rain" in EnvTagger().tags(at(14), 50.0, 0, false))
    }

    @Test fun `headlight in daytime is tunnel, at night it is night`() {
        assertEquals(listOf("tunnel"), EnvTagger().tags(at(14), 50.0, 0, true))
        assertEquals(listOf("night"), EnvTagger().tags(at(22), 50.0, 0, true))
    }

    @Test fun `highway needs sustained speed`() {
        val t = EnvTagger()
        val t0 = at(14)
        assertFalse("highway" in t.tags(t0, 100.0, 0, false))
        assertFalse("highway" in t.tags(t0 + 30_000, 100.0, 0, false))
        assertTrue("highway" in t.tags(t0 + 60_000, 100.0, 0, false))
        assertFalse("highway" in t.tags(t0 + 61_000, 60.0, 0, false))   // 속도 떨어지면 해제
    }

    @Test fun `region tag passes through only known values`() {
        assertTrue("coast" in EnvTagger().tags(at(14), 50.0, 0, false, "coast"))
        assertFalse("37.5,127.0" in EnvTagger().tags(at(14), 50.0, 0, false, "37.5,127.0"))
    }

    @Test fun `seat polarity flips sdk value`() {
        assertTrue(SeatPolarity.isOccupied(false))
        assertFalse(SeatPolarity.isOccupied(true))
        assertFalse(SeatPolarity.isOccupied(null))
    }
}
