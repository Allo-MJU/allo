package ai.allo.car.ui

import kotlin.test.*

class PetSpriteSpecTest {
    @Test fun `running sheet cannot replace real vehicle driving pose`() {
        assertNull(PetSpriteSheets.forDisplay("road_sprout", PetPose.Move, false, false))
        assertNull(PetSpriteSheets.forDisplay("road_sprout", PetPose.Move, true, false))
        assertEquals(PetSpriteSheets.run, PetSpriteSheets.forDisplay("road_sprout", PetPose.Move, false, true))
        assertNull(PetSpriteSheets.forDisplay("road_sprout", PetPose.Fishing, false, true))
        assertEquals(PetSpriteSheets.fish, PetSpriteSheets.forDisplay("road_sprout", PetPose.Fishing, true, false))
        assertNull(PetSpriteSheets.forDisplay("puddle_pip", PetPose.Fishing, true, false))
    }
    @Test fun `run advances exact cells loops and freezes on motion disable`() {
        val spec = PetSpriteSheets.run
        (0..7).forEach { i ->
            assertEquals(i, spec.frameAt(i * 100L, true))
            assertEquals(i % 4 to i / 4, spec.cell(i))
            assertEquals(0, spec.frameAt(i * 100L, false))
        }
        assertEquals(7, spec.frameAt(799, true))
        assertEquals(0, spec.frameAt(800, true))
        assertEquals(0, spec.frameAt(-1, true))
        assertFailsWith<IllegalArgumentException> { spec.cell(8) }
    }
    @Test fun `fishing holds story endpoints and rejects malformed sheet dimensions`() {
        val spec = PetSpriteSheets.fish
        assertEquals(0, spec.frameAt(899, true))
        assertEquals(1, spec.frameAt(900, true))
        assertEquals(7, spec.frameAt(spec.durationMs - 1L, true))
        assertEquals(0, spec.frameAt(spec.durationMs.toLong(), true))
        assertTrue(spec.validDimensions(1536, 1024))
        assertTrue(spec.validDimensions(1535, 1024))
        assertTrue(spec.validDimensions(1536, 1023))
        assertFalse(spec.validDimensions(4096, 4096))
        assertFalse(spec.validDimensions(-1, -1))
    }
    @Test fun `fractional cell dimensions cover every source pixel exactly once`() {
        val spec = PetSpriteSheets.run
        val width = 1774
        val height = 887
        assertTrue(spec.validDimensions(width, height))
        val cells = (0..7).map { spec.sourceRect(it, width, height) }
        assertEquals(listOf(443, 444, 443, 444), cells.take(4).map { it.width })
        assertEquals(443, cells.first().height)
        assertEquals(444, cells.last().height)
        assertEquals(width * height, cells.sumOf { it.width * it.height })
        (0..1).forEach { row ->
            val rowCells = cells.drop(row * 4).take(4)
            assertEquals(0, rowCells.first().left)
            assertEquals(width, rowCells.last().left + rowCells.last().width)
            rowCells.zipWithNext().forEach { (left, right) -> assertEquals(left.left + left.width, right.left) }
        }
        assertEquals(cells[0].top + cells[0].height, cells[4].top)
        assertEquals(height, cells.last().top + cells.last().height)
    }
}
