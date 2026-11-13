package ai.allo.car.ui

/** Normalized foot positions on the garden, independent of pixels and sprite dimensions. */
internal data class PlazaWanderPose(
    val x: Float,
    val y: Float,
    val moving: Boolean,
    val facingLeft: Boolean,
)

private val widePlazaAnchors = listOf(
    .22f to .42f, .50f to .40f, .77f to .43f,
    .27f to .84f, .53f to .85f, .79f to .82f,
)
private val compactPlazaAnchors = listOf(
    .30f to .30f, .70f to .33f,
    .27f to .57f, .73f to .58f,
    .32f to .85f, .68f to .84f,
)

/** Each friend strolls, rests, returns and rests; easing keeps turns and cycle seams continuous. */
internal fun plazaWanderPose(index: Int, seconds: Float, compact: Boolean): PlazaWanderPose {
    val slot = Math.floorMod(index, 6)
    val (anchorX, anchorY) = (if (compact) compactPlazaAnchors else widePlazaAnchors)[slot]
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
