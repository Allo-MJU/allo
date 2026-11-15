package ai.allo.car.ui

import java.io.File
import java.security.MessageDigest
import kotlinx.serialization.json.*
import kotlin.test.*

class PlazaArtTest {
    @Test fun `all twelve supplied identities use literal original assets`() {
        val root = File("src/main/assets/supplied")
        val manifest = Json.parseToJsonElement(File(root, "sha256.json").readText()).jsonObject
        val catalog = SpeciesCatalog.parse(File("../../data/characters.json").readText())
        assertEquals(12, catalog.entries.size)
        assertEquals(SuppliedCharacters.ids, catalog.entries.keys)
        assertEquals(120, manifest.size)
        manifest.forEach { (path, hash) ->
            val actual = MessageDigest.getInstance("SHA-256").digest(File(root, path).readBytes()).joinToString("") { "%02x".format(it) }
            assertEquals(hash.jsonPrimitive.content, actual, path)
        }
        for (id in catalog.entries.keys) for (pose in PetPose.entries) {
            val path = assertNotNull(SuppliedCharacters.path(id, pose))
            assertTrue(File("src/main/assets", path).isFile)
            assertFalse(path.contains("sheet"))
        }
    }
    @Test fun `unmapped gameplay IDs never impersonate supplied art`() {
        listOf("bridge_hopper", "mountain_sprite", "river_glider", "tide_keeper", "tunnel_moth", "star_owl").forEach {
            assertNull(SuppliedCharacters.path(it, PetPose.Idle))
        }
    }
}
