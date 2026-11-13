package ai.allo.car.ui

import kotlin.test.*
import ai.allo.car.model.PleosRoute

class PetPosesTest {
    @Test fun `only verified connected driving uses fishing even for legacy fishing status routes`() {
        for (route in PleosRoute.entries) {
            for (connected in listOf(false, true)) for (fresh in listOf(false, true)) {
                assertEquals(route == PleosRoute.Driving && connected && fresh,
                    PetPoses.forRoute(route, connected, fresh) == PetPose.Fishing,
                    "$route connected=$connected fresh=$fresh")
            }
        }
        assertEquals(PetPose.Sleep, PetPoses.forRoute(PleosRoute.Ended, true))
        assertEquals(PetPose.Idle, PetPoses.forRoute(PleosRoute.Disconnected, false))
        assertEquals(PetPose.Idle, PetPoses.forRoute(PleosRoute.SelectionPending, true))
        assertEquals(PetPose.Idle, PetPoses.forRoute(PleosRoute.Saving, true))
    }

    @Test fun `original standalone poses resolve without treating atlases as single images`() {
        assertEquals("poses/road_sprout/move.png", PetPoses.assetPath("road_sprout", PetPose.Move))
        assertEquals("poses/sea_mist/sleep.png", PetPoses.assetPath("sea_mist", PetPose.Sleep))
        assertEquals("poses/lamp_moth/idle.png", PetPoses.assetPath("lamp_moth", PetPose.Fishing))
        assertNull(PetPoses.assetPath("tide_keeper", PetPose.Sleep))
        assertNull(PetPoses.assetPath("../road_sprout", PetPose.Move))
        assertNull(PetPoses.assetPath(null, PetPose.Move))
    }
    @Test fun `disabled running and interrupted parking never animate`() {
        PetPose.entries.forEach { assertFalse(PetPoses.animates(it, false, true, true, true)) }
        assertFalse(PetPoses.animates(PetPose.Move, true, true, true, true))
        assertFalse(PetPoses.animates(PetPose.Sleep, true, false, true, true))
        assertFalse(PetPoses.animates(PetPose.Sleep, true, true, false, true))
        assertFalse(PetPoses.animates(PetPose.Fishing, true, true, true, false))
        assertTrue(PetPoses.animates(PetPose.Sleep, true, true, true, true))
        assertTrue(PetPoses.animates(PetPose.Fishing, true, true, true, true))
    }
    @Test fun `vehicle running stops on disconnect background reduced motion and parking`() {
        assertFalse(PetPoses.animates(PetPose.Move, false, true, true, true))
        assertTrue(PetPoses.animates(PetPose.Move, false, true, true, true, runningMotion = true))
        assertFalse(PetPoses.animates(PetPose.Move, false, true, true, false, runningMotion = true))
        assertFalse(PetPoses.animates(PetPose.Move, false, true, false, true, runningMotion = true))
        assertFalse(PetPoses.animates(PetPose.Move, false, false, true, true, runningMotion = true))
        assertFalse(PetPoses.animates(PetPose.Move, true, true, true, true, runningMotion = true))
    }

    @Test fun `automatic driving fishing obeys connection lifecycle and reduced motion gates`() {
        for (connected in listOf(false, true)) for (resumed in listOf(false, true))
            for (motionEnabled in listOf(false, true)) {
                assertEquals(connected && resumed && motionEnabled,
                    PetPoses.animates(PetPose.Fishing, false, connected, resumed, motionEnabled, drivingFishing = true))
            }
        for (pose in PetPose.entries.filter { it != PetPose.Fishing }) {
            assertFalse(PetPoses.animates(pose, false, true, true, true, drivingFishing = true))
        }
        assertFalse(PetPoses.animates(PetPose.Fishing, false, true, true, true))
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
