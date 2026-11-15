package ai.allo.car.ui

import java.io.File
import java.io.DataInputStream
import kotlin.test.*

class SuppliedCharactersTest {
    @Test fun `canonical display catalog contains exactly supplied identities and original poses`() {
        val catalog = SpeciesCatalog.parse(File("../../data/characters.json").readText())
        assertEquals(12, catalog.entries.size)
        assertEquals(SuppliedPoseCharacters.ids, catalog.entries.keys)
        for (id in catalog.entries.keys) for (pose in PetPose.entries) {
            val path = assertNotNull(SuppliedPoseCharacters.path(id, pose))
            assertFalse(path.contains("sheet")); assertFalse(path.contains("actions"))
            DataInputStream(File("../../phone/assets/$path").inputStream()).use {
                assertEquals(-8552249625308161526L, it.readLong())
                assertEquals(13, it.readInt()); assertEquals(0x49484452, it.readInt())
                assertTrue(it.readInt() in 1..2048); assertTrue(it.readInt() in 1..2048)
            }
        }
    }
    @Test fun `legacy game identities cannot silently become a different supplied character`() {
        listOf("bridge_hopper", "mountain_sprite", "river_glider", "tide_keeper", "tunnel_moth", "star_owl", "../road_sprout").forEach {
            assertNull(SuppliedPoseCharacters.path(it, PetPose.Idle))
        }
        assertEquals("poses/dewcap/idle.png", SuppliedPoseCharacters.path("dewcap", PetPose.Fishing))
        assertEquals("poses/ember_crab/sleep.png", SuppliedPoseCharacters.path("ember_crab", PetPose.Sleep))
    }
}
