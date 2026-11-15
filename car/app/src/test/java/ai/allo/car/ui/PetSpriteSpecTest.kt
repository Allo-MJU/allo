package ai.allo.car.ui

import kotlin.test.*

class PetSpriteSpecTest {
    @Test fun `new supplied characters use their own fishing art on the shared scene clock`() {
        val ids = listOf("breeze_wyrm", "cloud_strider", "dewcap", "dune_roller", "ember_crab", "pebble_orbit")
        ids.forEach { id ->
            val spec = assertNotNull(PetSpriteSheets.forDisplay(id, PetPose.Fishing, false, false, drivingFishing = true), id)
            assertEquals("fishing/$id/fish.png", spec.path)
            assertEquals(4, spec.columns)
            assertEquals(2, spec.rows)
            assertEquals(32, spec.alphaCutoff)
            assertEquals(.08f, spec.contentInsetFraction)
            assertEquals(PetSpriteSheets.fish.durationMs, spec.durationMs)
            assertEquals(PetSpriteSheets.fish.timeline, spec.timeline)
            (0L..spec.durationMs.toLong() step 100L).forEach { elapsed ->
                assertEquals(PetSpriteSheets.fish.frameAt(elapsed, true), spec.frameAt(elapsed, true))
                assertEquals(0, spec.frameAt(elapsed, false))
            }
            assertEquals(spec, PetSpriteSheets.forDisplay(id, PetPose.Fishing, true, false))
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Fishing, false, true))
            PetPose.entries.filter { it != PetPose.Fishing }.forEach { pose ->
                assertNull(PetSpriteSheets.forDisplay(id, pose, false, true, drivingFishing = true))
                assertNull(PetSpriteSheets.forDisplay(id, pose, true, true, drivingFishing = true))
            }
        }
    }

    @Test fun `all designed species use their own sheets with identical playback gates`() {
        val ids = listOf("road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist")
        val paths = mutableSetOf<String>()
        ids.forEach { id ->
            listOf(PetPose.Move to "run", PetPose.Fishing to "fish", PetPose.Sleep to "sleep").forEach { (pose, file) ->
                val spec = assertNotNull(PetSpriteSheets.forDisplay(id, pose, pose != PetPose.Move, true))
                assertEquals("poses/$id/$file-sheet.png", spec.path)
                assertTrue(paths.add(spec.path))
                assertEquals((0..7).toSet(), spec.timeline.toSet())
                assertEquals(0, spec.frameAt(spec.durationMs.toLong(), true))
                assertEquals(0, spec.frameAt(1200L, false))
            }
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Move, false, false))
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Move, true, false))
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Fishing, false, true))
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Sleep, false, true))
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Idle, true, true))
        }
        assertEquals(18, paths.size)
        listOf(null, "../road_sprout", "Road_Sprout", "unknown").forEach { id ->
            PetPose.entries.forEach { pose -> assertNull(PetSpriteSheets.forDisplay(id, pose, pose != PetPose.Move, true)) }
        }
    }
    @Test fun `automatic fishing uses each companions fish sheet without opting into running`() {
        for (id in listOf("road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist")) {
            val spec = assertNotNull(PetSpriteSheets.forDisplay(id, PetPose.Fishing, false, false, drivingFishing = true))
            assertEquals("poses/$id/fish-sheet.png", spec.path)
            assertEquals(0, spec.frameAt(1200, false))
            assertNotEquals(0, spec.frameAt(1200, true))
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Move, false, false, drivingFishing = true))
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Fall, false, false, drivingFishing = true))
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Sleep, false, false, drivingFishing = true))
        }
        assertNull(PetSpriteSheets.forDisplay("unknown", PetPose.Fishing, false, false, drivingFishing = true))
    }

    @Test fun `six previously missing species have distinct atlases and correct action rows`() {
        val ids = listOf("bridge_hopper", "mountain_sprite", "river_glider", "tide_keeper", "tunnel_moth", "star_owl")
        ids.forEach { id ->
            listOf(PetPose.Move to 0, PetPose.Fishing to 8, PetPose.Sleep to 16).forEach { (pose, first) ->
                val spec = assertNotNull(PetSpriteSheets.forDisplay(id, pose, pose != PetPose.Move, true))
                assertEquals("poses/$id/actions.png", spec.path)
                assertEquals(4, spec.columns)
                assertEquals(6, spec.rows)
                assertEquals(32, spec.alphaCutoff)
                assertEquals((first..first + 7).toSet(), spec.timeline.toSet())
                assertEquals(first, spec.frameAt(1200, false))
                assertEquals(first, spec.frameAt(spec.durationMs.toLong(), true))
                assertEquals(first % 4 to first / 4, spec.cell(first))
            }
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Sleep, false, true))
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Fishing, false, true))
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Move, true, true))
            assertNull(PetSpriteSheets.forDisplay(id, PetPose.Move, false, false))
            val idle = assertNotNull(PetSpriteSheets.stillForDisplay(id, PetPose.Idle, true))
            assertEquals(listOf(0), idle.timeline)
            assertEquals(listOf(16), PetSpriteSheets.stillForDisplay(id, PetPose.Sleep, true)?.timeline)
            assertEquals(listOf(0), PetSpriteSheets.stillForDisplay(id, PetPose.Sleep, false)?.timeline)
        }
        assertNull(PetSpriteSheets.stillForDisplay("../star_owl", PetPose.Idle, true))
    }

    @Test fun `sleeping frames require parking and freeze when motion is disabled`() {
        assertEquals(PetSpriteSheets.sleep, PetSpriteSheets.forDisplay("road_sprout", PetPose.Sleep, true, false))
        assertNull(PetSpriteSheets.forDisplay("road_sprout", PetPose.Sleep, false, true))
        assertNotNull(PetSpriteSheets.forDisplay("tide_keeper", PetPose.Sleep, true, false))
        val spec = PetSpriteSheets.sleep
        assertEquals(0, spec.frameAt(899, true))
        assertEquals(1, spec.frameAt(900, true))
        assertEquals((0..7).toSet(), spec.timeline.toSet())
        spec.timeline.indices.forEach { assertEquals(0, spec.frameAt(it * 450L, false)) }
        assertEquals(7, spec.frameAt(spec.durationMs - 1L, true))
        assertEquals(0, spec.frameAt(spec.durationMs.toLong(), true))
    }
    @Test fun `running sheet is selected by vehicle driving and never by parking`() {
        assertNull(PetSpriteSheets.forDisplay("road_sprout", PetPose.Move, false, false))
        assertNull(PetSpriteSheets.forDisplay("road_sprout", PetPose.Move, true, true))
        assertEquals(PetSpriteSheets.run, PetSpriteSheets.forDisplay("road_sprout", PetPose.Move, false, true))
        assertNull(PetSpriteSheets.forDisplay("road_sprout", PetPose.Fishing, false, true))
        assertEquals(PetSpriteSheets.fish, PetSpriteSheets.forDisplay("road_sprout", PetPose.Fishing, true, false))
        assertNotNull(PetSpriteSheets.forDisplay("tide_keeper", PetPose.Fishing, true, false))
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
