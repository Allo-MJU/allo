package ai.allo.car.ui

/** Row-major source cells. Animation uses authored limb poses, not whole-image transforms. */
data class PetSpriteSpec(
    val path: String,
    val frameMs: Int,
    val timeline: List<Int>,
    val columns: Int = 4,
    val rows: Int = 2,
    val repeat: Boolean = true,
    val alphaCutoff: Int = 0,
    val contentInsetFraction: Float = 0f,
) {
    val durationMs: Int get() = frameMs * timeline.size
    fun frameAt(elapsedMs: Long, enabled: Boolean): Int {
        if (!enabled || elapsedMs < 0) return timeline.first()
        val time = if (repeat) elapsedMs % durationMs else elapsedMs.coerceAtMost(durationMs - 1L)
        return timeline[(time / frameMs).toInt()]
    }
    fun cell(frame: Int): Pair<Int, Int> {
        require(frame in 0 until columns * rows)
        return frame % columns to frame / columns
    }
    /** Floor each cell boundary independently: every source pixel belongs to exactly one cell. */
    fun sourceRect(frame: Int, width: Int, height: Int): SpriteCell {
        require(validDimensions(width, height))
        val (column, row) = cell(frame)
        val left = column * width / columns
        val top = row * height / rows
        return SpriteCell(left, top, (column + 1) * width / columns - left, (row + 1) * height / rows - top)
    }
    fun validDimensions(width: Int, height: Int): Boolean = width in columns..4096 && height in rows..4096 &&
        width.toLong() * height <= 8_388_608L
}

data class SpriteCell(val left: Int, val top: Int, val width: Int, val height: Int)

object PetSpriteSheets {
    val fall = PetSpriteSpec("poses/road_sprout/fall-sheet.png", 180, listOf(0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7), repeat = false)
    val run = PetSpriteSpec("poses/road_sprout/run-sheet.png", 100, (0..7).toList())
    // Hold the waiting and recovery poses so the catch-and-loss action reads clearly.
    val fish = PetSpriteSpec("poses/road_sprout/fish-sheet.png", 300, listOf(0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 7, 7))
    // Linger in the resting poses; breathing and turning are authored in the frames.
    val sleep = PetSpriteSpec("poses/road_sprout/sleep-sheet.png", 450, listOf(0, 0, 1, 2, 3, 4, 5, 5, 6, 7, 7))

    // Only species with authored sheets participate; unknown IDs keep their static artwork.
    private val sheetsBySpecies = listOf(
        "road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist",
    ).associateWith { speciesId ->
        mapOf(PetPose.Move to run, PetPose.Fishing to fish, PetPose.Sleep to sleep, PetPose.Fall to fall).mapValues { (_, sheet) ->
            sheet.copy(path = "poses/$speciesId/${sheet.path.substringAfterLast('/')}")
        }
    } + listOf(
        "breeze_wyrm", "cloud_strider", "dewcap", "dune_roller", "ember_crab", "pebble_orbit",
    ).associateWith { speciesId ->
        // Preserve the shared fishing clock; these characters have no authored run/sleep/fall sheets.
        mapOf(PetPose.Fishing to fish.copy(path = "fishing/$speciesId/fish.png", alphaCutoff = 32, contentInsetFraction = .08f))
    }

    // New artwork packs three eight-frame actions in one 4-column, 6-row atlas.
    private val atlasesBySpecies = listOf(
        "bridge_hopper", "mountain_sprite", "river_glider", "tide_keeper", "tunnel_moth", "star_owl",
    ).associateWith { id ->
        mapOf(PetPose.Move to run, PetPose.Fishing to fish, PetPose.Sleep to sleep).mapValues { (pose, sheet) ->
            val offset = when (pose) { PetPose.Fishing -> 8; PetPose.Sleep -> 16; else -> 0 }
            sheet.copy(path = "poses/$id/actions.png", rows = 6, alphaCutoff = 32, timeline = sheet.timeline.map { it + offset })
        }
    }

    /** Select the appropriate atlas cell for idle or motion-disabled displays. */
    fun stillForDisplay(speciesId: String?, pose: PetPose, parked: Boolean): PetSpriteSpec? {
        val action = if (parked && pose in setOf(PetPose.Sleep, PetPose.Fishing)) pose else PetPose.Move
        val spec = atlasesBySpecies[speciesId]?.get(action) ?: return null
        return spec.copy(timeline = listOf(spec.timeline.first()))
    }

    fun forDisplay(speciesId: String?, pose: PetPose, parked: Boolean, runningMotion: Boolean, drivingFishing: Boolean = false): PetSpriteSpec? {
        val sheets = sheetsBySpecies[speciesId] ?: atlasesBySpecies[speciesId] ?: return null
        val allowed = when (pose) {
            PetPose.Move, PetPose.Fall -> !parked && runningMotion
            PetPose.Fishing -> parked || drivingFishing
            PetPose.Sleep -> parked
            else -> false
        }
        return if (allowed) sheets[pose] else null
    }
}
