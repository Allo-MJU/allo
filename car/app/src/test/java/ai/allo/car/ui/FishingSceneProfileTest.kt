package ai.allo.car.ui

import org.junit.Assert.*
import org.junit.Test

class FishingSceneProfileTest {
    @Test fun `every authored species has an explicit direction and support profile`() {
        assertEquals(setOf("road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist"), FishingSceneProfile.all.keys)
        assertEquals(setOf("lamp_moth", "storm_lantern", "highway_comet"), FishingSceneProfile.all.filterValues { it.castsRight }.keys)
        assertEquals(setOf("lamp_moth", "sea_mist"), FishingSceneProfile.all.filterValues { it.hovering }.keys)
        assertNull(FishingSceneProfile.forSpecies("unknown"))
    }
    @Test fun `contact rings stay on water side and disappear while lifting the line`() {
        FishingSceneProfile.all.values.forEach { profile ->
            assertEquals(setOf(0, 1, 6, 7), profile.contacts.keys)
            profile.contacts.values.forEach { contact ->
                assertTrue(contact.y in .6f.. .9f)
                assertTrue(if (profile.castsRight) contact.x > .8f else contact.x < .2f)
            }
            assertTrue(profile.groundY + .06f <= 1.05f)
        }
    }
}
