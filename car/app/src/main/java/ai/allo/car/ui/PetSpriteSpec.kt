package ai.allo.car.ui

/** Row-major source cells. Animation uses authored limb poses, not whole-image transforms. */
data class PetSpriteSpec(
    val path: String,
    val frameMs: Int,
    val timeline: List<Int>,
    val columns: Int = 4,
    val rows: Int = 2,
) {
    val durationMs: Int get() = frameMs * timeline.size
    fun frameAt(elapsedMs: Long, enabled: Boolean): Int {
        if (!enabled || elapsedMs < 0) return timeline.first()
        return timeline[((elapsedMs % durationMs) / frameMs).toInt()]
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
    val run = PetSpriteSpec("poses/road_sprout/run-sheet.png", 100, (0..7).toList())
    // Hold the waiting and recovery poses so the catch-and-loss action reads clearly.
    val fish = PetSpriteSpec("poses/road_sprout/fish-sheet.png", 300, listOf(0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 7, 7))

    fun forDisplay(speciesId: String?, pose: PetPose, parked: Boolean, previewRunning: Boolean): PetSpriteSpec? {
        if (speciesId != "road_sprout") return null
        return when {
            pose == PetPose.Move && previewRunning -> run
            pose == PetPose.Fishing && parked -> fish
            else -> null
        }
    }
}
