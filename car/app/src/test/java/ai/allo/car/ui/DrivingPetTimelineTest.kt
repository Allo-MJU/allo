package ai.allo.car.ui

import ai.allo.car.model.DrivingMotionState
import kotlin.test.*

class DrivingPetTimelineTest {
    private fun motion(rate: Float = 1f, serial: Long = 0, at: Long? = null, fresh: Boolean = true) =
        DrivingMotionState(speedKph = if (rate == 0f) 0.0 else 40.0, playbackRate = rate,
            brakeSerial = serial, brakeAtMs = at, fresh = fresh)

    @Test fun `speed changes preserve frame phase and high speed advances more frames`() {
        val slow = DrivingPetTimeline(); val fast = DrivingPetTimeline()
        slow.frame(0, motion(.5f), true); fast.frame(0, motion(1.8f), true)
        var s = DrivingPetFrame(); var f = DrivingPetFrame()
        for (t in 20L..1000L step 20) { s = slow.frame(t, motion(.5f), true); f = fast.frame(t, motion(1.8f), true) }
        assertEquals(PetPose.Move, s.pose)
        assertTrue(f.elapsedMs > s.elapsedMs * 2)
        val next = slow.frame(1020, motion(1.8f), true)
        assertTrue(next.elapsedMs >= s.elapsedMs)
        assertTrue(next.elapsedMs - s.elapsedMs < 36)
        assertEquals(PetPose.Idle, slow.frame(1040, motion(0f), true).pose)
    }

    @Test fun `brake plays down and recovery once then respects stopped speed`() {
        val timeline = DrivingPetTimeline()
        timeline.frame(1000, motion(), true)
        assertEquals(PetPose.Fall, timeline.frame(1100, motion(0f, 1, 1100), true).pose)
        assertEquals(500L, timeline.frame(1600, motion(0f, 1, 1100), true).elapsedMs)
        assertEquals(PetPose.Idle, timeline.frame(1100L + PetSpriteSheets.fall.durationMs, motion(0f, 1, 1100), true).pose)
        assertEquals(PetPose.Idle, timeline.frame(4000, motion(0f, 1, 1100), true).pose)
    }

    @Test fun `stale signal or background cancels fall without replay on resume`() {
        for (disconnect in listOf(true, false)) {
            val timeline = DrivingPetTimeline()
            timeline.frame(1000, motion(), true)
            timeline.frame(1100, motion(1f, 1, 1100), true)
            assertEquals(PetPose.Idle, timeline.frame(1200, motion(1f, 1, 1100, !disconnect), disconnect).pose)
            assertNotEquals(PetPose.Fall, timeline.frame(1300, motion(1f, 1, 1100), true).pose)
        }
    }

    @Test fun `old or initial brake events never replay after entering the screen`() {
        val timeline = DrivingPetTimeline()
        assertNotEquals(PetPose.Fall, timeline.frame(1000, motion(1f, 5, 950), true).pose)
        assertNotEquals(PetPose.Fall, timeline.frame(2000, motion(1f, 6, 1200), true).pose)
    }

    @Test fun `fall stops at recovery frame instead of wrapping to stumble`() {
        val spec = PetSpriteSheets.fall
        assertEquals(7, spec.frameAt(spec.durationMs.toLong(), true))
        assertEquals(7, spec.frameAt(100_000, true))
        assertEquals(0, spec.frameAt(100_000, false))
    }
}
