package ai.allo.car.ui

import java.io.File
import java.io.DataInputStream
import kotlin.test.*

class PlazaArtTest {
    @Test fun `all extra plaza species have complete RGBA action atlas files`() {
        assertEquals(6, plazaAtlases.size)
        plazaAtlases.forEach { (id, spec) ->
            val file = File("src/main/assets", spec.path)
            assertTrue(file.isFile, "Missing plaza art for $id")
            val (width, height) = DataInputStream(file.inputStream()).use { input ->
                assertEquals(0x89504E470D0A1A0AuL.toLong(), input.readLong(), id)
                assertEquals(13, input.readInt(), id)
                assertEquals(0x49484452, input.readInt(), id)
                val width = input.readInt()
                val height = input.readInt()
                assertEquals(8, input.readUnsignedByte(), id)
                assertEquals(6, input.readUnsignedByte(), "Expected RGBA PNG: $id")
                width to height
            }
            assertTrue(spec.validDimensions(width, height), id)
            spec.timeline.forEach { frame ->
                val cell = spec.sourceRect(frame, width, height)
                assertTrue(cell.left >= 0 && cell.top >= 0 && cell.left + cell.width <= width && cell.top + cell.height <= height)
            }
        }
    }
}
