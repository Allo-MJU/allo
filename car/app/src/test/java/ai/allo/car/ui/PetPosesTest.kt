package ai.allo.car.ui

import kotlin.test.*

class PetPosesTest {
    @Test fun `only matching design species resolve to pose assets`() {
        assertEquals("poses/road_sprout/move.png", PetPoses.assetPath("road_sprout", PetPose.Move))
        assertEquals("poses/sea_mist/sleep.png", PetPoses.assetPath("sea_mist", PetPose.Sleep))
        assertEquals("poses/lamp_moth/idle.png", PetPoses.assetPath("lamp_moth", PetPose.Fishing))
        assertNull(PetPoses.assetPath("tide_keeper", PetPose.Sleep))
        assertNull(PetPoses.assetPath("../road_sprout", PetPose.Move))
        assertNull(PetPoses.assetPath(null, PetPose.Move))
    }
    @Test fun `driving or interrupted parking never animates`() {
        PetPose.entries.forEach { assertFalse(PetPoses.animates(it, false, true, true, true)) }
        assertFalse(PetPoses.animates(PetPose.Move, true, true, true, true))
        assertFalse(PetPoses.animates(PetPose.Sleep, true, false, true, true))
        assertFalse(PetPoses.animates(PetPose.Sleep, true, true, false, true))
        assertFalse(PetPoses.animates(PetPose.Fishing, true, true, true, false))
        assertTrue(PetPoses.animates(PetPose.Sleep, true, true, true, true))
        assertTrue(PetPoses.animates(PetPose.Fishing, true, true, true, true))
    }
    @Test fun `running motion requires explicit preview opt in and active motion permission`() {
        assertFalse(PetPoses.animates(PetPose.Move, false, true, true, true))
        assertTrue(PetPoses.animates(PetPose.Move, false, true, true, true, previewRunning = true))
        assertFalse(PetPoses.animates(PetPose.Move, false, true, true, false, previewRunning = true))
        assertFalse(PetPoses.animates(PetPose.Move, false, true, false, true, previewRunning = true))
    }

    @Test fun `fishing choreography raises catches releases and splashes within bounds`() {
        assertEquals(FishingStage.Waiting, petMotion(.1f, true).stage)
        assertEquals(FishingStage.Lifting, petMotion(.4f, true).stage)
        assertTrue(petMotion(.5f, true).lift > petMotion(.4f, true).lift)
        assertEquals(FishingStage.Caught, petMotion(.6f, true).stage)
        assertTrue(petMotion(.6f, true).fish)
        assertEquals(FishingStage.Escaping, petMotion(.75f, true).stage)
        assertTrue(petMotion(.8f, true).escape > petMotion(.7f, true).escape)
        assertEquals(FishingStage.Splash, petMotion(.9f, true).stage)
        assertFalse(petMotion(.9f, true).fish)
        for (i in 0..1000) {
            val motion = petMotion(i / 1000f, true)
            listOf(motion.breathe, motion.bounce, motion.lift, motion.escape, motion.splash).forEach {
                assertTrue(it in 0f..1.00001f)
            }
        }
        assertEquals(PetMotion(), petMotion(.6f, false))
        assertEquals(PetMotion(), petMotion(Float.NaN, true))
    }
}
