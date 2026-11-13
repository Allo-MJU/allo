package ai.allo.car.ui

import org.junit.Assert.*
import org.junit.Test

class FishingSceneProfileTest {
    @Test fun `every authored species has an explicit direction and support profile`() {
        val original = setOf("road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist")
        val supplied = setOf("breeze_wyrm", "cloud_strider", "dewcap", "dune_roller", "ember_crab", "pebble_orbit")
        assertEquals(original + supplied, FishingSceneProfile.all.keys)
        assertEquals(setOf("lamp_moth", "storm_lantern", "highway_comet") + (supplied - "dune_roller"),
            FishingSceneProfile.all.filterValues { it.castsRight }.keys)
        assertEquals(setOf("lamp_moth", "sea_mist"), FishingSceneProfile.all.filterKeys { it in original }.filterValues { it.hovering }.keys)
        assertNull(FishingSceneProfile.forSpecies("unknown"))
    }
    @Test fun `contact rings stay on water side and disappear while lifting the line`() {
        FishingSceneProfile.all.forEach { (id, profile) ->
            assertEquals(if (id == "pebble_orbit") setOf(0, 1, 7) else setOf(0, 1, 6, 7), profile.contacts.keys)
            profile.contacts.values.forEach { contact ->
                assertTrue(contact.y in .6f.. .9f)
                assertTrue(if (profile.castsRight) contact.x > .75f else contact.x < .2f)
            }
            assertTrue(profile.groundY + .06f <= 1.05f)
        }
    }
}
