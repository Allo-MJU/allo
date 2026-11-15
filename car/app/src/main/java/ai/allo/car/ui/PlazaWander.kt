package ai.allo.car.ui

/** Normalized foot positions on the garden, independent of pixels and sprite dimensions. */
internal data class PlazaWanderPose(
    val x: Float,
    val y: Float,
    val moving: Boolean,
    val facingLeft: Boolean,
)

private val widePlazaAnchors = listOf(
    .22f to .40f, .50f to .40f, .77f to .40f,
    .27f to .86f, .53f to .86f, .79f to .85f,
)
private val compactPlazaAnchors = listOf(
    .30f to .30f, .70f to .33f,
    .27f to .57f, .73f to .58f,
    .32f to .85f, .68f to .84f,
)

// Up to three friends share one front row, so each can be drawn much larger.
private val fewPlazaAnchors = listOf(.22f to .66f, .50f to .70f, .78f to .66f)

/** Sprite edge in dp. Two rows are sized so a front friend never covers a back friend's name. */
internal fun plazaPetSize(sceneWidth: Float, lawnHeight: Float, depthY: Float, count: Int, compact: Boolean): Float {
    if (compact) return (sceneWidth * .25f).coerceIn(84f, 150f) * (.85f + depthY * .20f)
    if (count <= 3) return minOf(sceneWidth * .19f, lawnHeight * .48f).coerceIn(140f, 320f)
    // Rows are at least .45 of the lawn apart, less the stroll (.036). A front sprite shows .86 of
    // its edge above its feet, the back one .14 below plus a 32dp name. Back friends are drawn at 80%.
    val front = minOf((lawnHeight * .414f - 32f) / .972f, sceneWidth * .185f).coerceIn(110f, 280f)
    return front * (.80f + .20f * ((depthY - .42f) / .42f).coerceIn(0f, 1f))
}

/** Each friend strolls, rests, returns and rests; easing keeps turns and cycle seams continuous. */
internal fun plazaWanderPose(index: Int, seconds: Float, compact: Boolean, count: Int = 6): PlazaWanderPose {
    val slot = Math.floorMod(index, 6)
    val (anchorX, anchorY) = if (compact) compactPlazaAnchors[slot] else if (count <= 3) fewPlazaAnchors[slot % 3] else widePlazaAnchors[slot]
    val walkSeconds = 4.5f + slot * .25f
    val restSeconds = 2.4f + slot * .3f
    val halfCycle = walkSeconds + restSeconds
    val cycle = halfCycle * 2f
    val clock = (if (seconds.isFinite()) seconds.coerceAtLeast(0f) else 0f) + slot * 3.7f
    val phase = clock % cycle
    val returning = phase >= halfCycle
    val leg = if (returning) phase - halfCycle else phase
    val progress = (leg / walkSeconds).coerceIn(0f, 1f)
    val eased = progress * progress * (3f - 2f * progress)
    val displacement = if (returning) 1f - 2f * eased else -1f + 2f * eased
    val slope = if (slot % 2 == 0) 1f else -1f
    return PlazaWanderPose(
        x = anchorX + .035f * displacement,
        y = anchorY + .018f * displacement * slope,
        moving = leg < walkSeconds,
        facingLeft = returning,
    )
}
