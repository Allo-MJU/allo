package ai.allo.car.ui

import java.io.File
import java.io.DataInputStream
import kotlin.test.*

/** Cross-checks packaged artwork paths and PNG headers against the shared game catalog. */
class PetArtworkAssetsTest {
    @Test fun `all twelve catalog species ship action PNGs and still artwork`() {
        val catalog = SpeciesCatalog.parse(File("../../data/species.json").readText())
        assertEquals(12, catalog.entries.size)
        val assets = File("../../phone/assets")
        catalog.entries.keys.forEach { id ->
            listOf(PetPose.Move, PetPose.Fishing, PetPose.Sleep).forEach { pose ->
                val spec = assertNotNull(PetSpriteSheets.forDisplay(id, pose, pose != PetPose.Move, true), "$id $pose")
                assertTrue(spec.path.startsWith("poses/$id/"))
                DataInputStream(File(assets, spec.path).inputStream()).use { input ->
                    assertEquals(-8552249625308161526L, input.readLong(), spec.path) // PNG signature
                    assertEquals(13, input.readInt())
                    assertEquals(0x49484452, input.readInt()) // IHDR
                    val width = input.readInt()
                    val height = input.readInt()
                    assertTrue(spec.validDimensions(width, height), spec.path)
                    assertEquals(8, input.readUnsignedByte())
                    assertEquals(6, input.readUnsignedByte(), "RGBA required: ${spec.path}")
                    val cells = (0 until spec.columns * spec.rows).map { spec.sourceRect(it, width, height) }
                    assertEquals(width * height, cells.sumOf { it.width * it.height })
                    assertEquals(height, cells.last().top + cells.last().height)
                }
            }
            val still = PetSpriteSheets.stillForDisplay(id, PetPose.Idle, true)
            if (still == null) {
                assertTrue(File(assets, assertNotNull(PetPoses.assetPath(id, PetPose.Idle))).isFile)
            } else {
                assertEquals(1, still.timeline.size)
                assertTrue(File(assets, still.path).isFile)
            }
        }
    }
}
