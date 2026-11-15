package ai.allo.car.ui

import java.io.File
import java.io.DataInputStream
import kotlin.test.*

class PlazaWalkArtTest {
    @Test fun `each supplied identity has a complete eight frame walking loop`() {
        assertEquals(12, SuppliedCharacters.ids.size)
        SuppliedCharacters.ids.forEach { id ->
            val spec = assertNotNull(PlazaWalkArt.spec(id))
            val file = if (id in PlazaWalkArt.existing) File("../../phone/assets", spec.path) else File("src/main/assets", spec.path)
            assertTrue(file.isFile, id)
            DataInputStream(file.inputStream()).use { input ->
                assertEquals(0x89504E470D0A1A0AuL.toLong(), input.readLong(), id)
                assertEquals(13, input.readInt()); assertEquals(0x49484452, input.readInt())
                val w = input.readInt(); val h = input.readInt()
                assertTrue(spec.validDimensions(w,h), id)
                assertEquals(8, spec.timeline.distinct().size)
                spec.timeline.forEach { frame ->
                    val cell = spec.sourceRect(frame,w,h)
                    assertTrue(cell.left >= 0 && cell.top >= 0 && cell.left + cell.width <= w && cell.top + cell.height <= h, id)
                }
            }
        }
    }
    @Test fun `collected gameplay species use their own atlas without aliasing supplied identities`() {
        val catalog = SpeciesCatalog.parse(File("../../data/species.json").readText())
        for (id in catalog.entries.keys - SuppliedCharacters.ids) {
            val spec = assertNotNull(PlazaWalkArt.spec(id), id)
            assertEquals("poses/$id/actions.png", spec.path)
            assertEquals(6, spec.rows)
            assertEquals((0..7).toSet(), spec.timeline.toSet())
            assertTrue(File("../../phone/assets", spec.path).isFile)
            assertNull(SuppliedCharacters.path(id, PetPose.Idle))
        }
    }
    @Test fun `walking direction respects left and right facing source sheets`() {
        assertFalse(PlazaWalkArt.mirror("road_sprout", true, true))
        assertTrue(PlazaWalkArt.mirror("road_sprout", true, false))
        assertTrue(PlazaWalkArt.mirror("ember_crab", true, true))
        assertFalse(PlazaWalkArt.mirror("ember_crab", true, false))
        assertFalse(PlazaWalkArt.mirror("dune_roller", true, true))
        assertTrue(PlazaWalkArt.mirror("dune_roller", true, false))
        assertNull(PlazaWalkArt.spec("unknown"))
    }
}
