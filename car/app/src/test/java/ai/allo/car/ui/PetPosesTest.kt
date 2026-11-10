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
}
