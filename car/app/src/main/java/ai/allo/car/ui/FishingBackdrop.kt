package ai.allo.car.ui

import androidx.compose.foundation.Canvas
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Static scenery anchored to the exact square occupied by the original fishing sheet. */
@Composable
internal fun FishingBackdrop(
    modifier: Modifier = Modifier,
    spriteSize: Dp = 0.dp,
    speciesId: String? = null,
    showContact: Boolean = true,
    frame: Int = 0,
) {
    val dark = MaterialTheme.colorScheme.surface.luminance() < .35f
    val sky = if (dark) Color(0xFF1A292B) else Color(0xFFEAF2E9)
    val horizon = if (dark) Color(0xFF283B38) else Color(0xFFDDE9DC)
    val farHill = if (dark) Color(0xFF30443D) else Color(0xFFC9DACA)
    val nearHill = if (dark) Color(0xFF354B40) else Color(0xFFB9CFBC)
    val waterTop = if (dark) Color(0xFF263E40) else Color(0xFFC6DFD9)
    val waterBottom = if (dark) Color(0xFF1D3037) else Color(0xFFAECFCB)
    val ripple = if (dark) Color(0xFF57736D) else Color(0xFFE4EFDF)
    val reeds = if (dark) Color(0xFF53634A) else Color(0xFF92AB83)
    val timber = if (dark) Color(0xFF544A3C) else Color(0xFFBEAA86)
    val timberEdge = if (dark) Color(0xFF403B32) else Color(0xFFA58F6D)
    Canvas(modifier) {
        val w = size.width
        val h = size.height
        if (w <= 0f || h <= 0f) return@Canvas
        val unit = minOf(w, h)
        drawRect(Brush.verticalGradient(listOf(sky, horizon)))
        drawRect(Brush.radialGradient(
            listOf(Color(0xFFFFE9B0).copy(alpha = if (dark) .04f else .32f), Color.Transparent),
            center = Offset(w * .22f, h * .18f), radius = unit * .8f))

        // Broad silhouettes leave the central character area visually quiet.
        val distant = Path().apply {
            moveTo(0f, h * .44f)
            cubicTo(w * .12f, h * .24f, w * .24f, h * .28f, w * .37f, h * .40f)
            cubicTo(w * .52f, h * .51f, w * .66f, h * .22f, w * .81f, h * .34f)
            cubicTo(w * .90f, h * .40f, w * .96f, h * .34f, w, h * .37f)
            lineTo(w, h * .59f); lineTo(0f, h * .59f); close()
        }
        drawPath(distant, Brush.verticalGradient(listOf(farHill.copy(alpha = .55f), farHill), startY = h * .25f, endY = h * .59f))
        val bank = Path().apply {
            moveTo(0f, h * .51f)
            cubicTo(w * .14f, h * .38f, w * .29f, h * .52f, w * .46f, h * .50f)
            cubicTo(w * .64f, h * .46f, w * .83f, h * .43f, w, h * .51f)
            lineTo(w, h * .60f); lineTo(0f, h * .60f); close()
        }
        drawPath(bank, Brush.verticalGradient(listOf(nearHill, farHill), startY = h * .40f, endY = h * .60f))
        drawRect(Brush.verticalGradient(listOf(waterTop, waterBottom), startY = h * .55f, endY = h),
            topLeft = Offset(0f, h * .55f), size = Size(w, h * .45f))

        // Fixed short ripples, not animated shimmer.
        listOf(
            Triple(.62f, .62f, .13f), Triple(.81f, .69f, .09f),
            Triple(.49f, .77f, .12f), Triple(.73f, .86f, .16f),
            Triple(.20f, .91f, .11f), Triple(.91f, .95f, .06f),
        ).forEach { (x, y, length) ->
            drawLine(ripple.copy(alpha = .38f), Offset(w * x, h * y),
                Offset(w * (x + length), h * y), strokeWidth = unit * .004f, cap = StrokeCap.Round)
        }

        // Reeds frame the far shore, away from the main casting area.
        listOf(.025f, .045f, .068f, .93f, .95f, .975f).forEachIndexed { index, x ->
            val top = h * (.43f + (index % 3) * .025f)
            val stem = Path().apply {
                moveTo(w * x, h * .58f)
                quadraticBezierTo(w * (x - .008f), h * .51f, w * (x + .004f), top)
            }
            drawPath(stem, reeds, style = androidx.compose.ui.graphics.drawscope.Stroke(width = unit * .004f))
            drawLine(reeds, Offset(w * (x + .004f), top), Offset(w * (x + .005f), top - h * .022f),
                strokeWidth = unit * .010f, cap = StrokeCap.Round)
        }

        // Match DrivingScreen's BottomCenter placement and 10% bottom inset exactly.
        // Pier and contact shadows share the sprite scale instead of scaling to the viewport.
        val art = spriteSize.toPx()
        if (!showContact || art <= 0f) return@Canvas
        val profile = FishingSceneProfile.forSpecies(speciesId) ?: return@Canvas
        val sx = (w - art) / 2f
        val sy = h * .90f - art
        val rearY = sy + art * (profile.groundY - .11f)
        val frontY = sy + art * (profile.groundY + .06f)
        val rearX = sx + art * .35f
        val frontX = sx + art * .24f
        val depth = art * .035f
        val contactY = sy + art * profile.groundY
        // Mirror only the scenery; the authored character and fishing direction remain intact.
        withTransform({ if (profile.castsRight) scale(-1f, 1f, pivot = Offset(w / 2f, 0f)) }) {

        // Broad reflection beneath the pier, then the posts and bevelled timber edge.
        drawOval(Brush.radialGradient(listOf(Color(0xFF173C37).copy(alpha = .26f), Color.Transparent),
            center = Offset(sx + art * .65f, frontY + art * .07f), radius = art * .55f),
            Offset(frontX - art * .08f, frontY), Size(w - frontX + art * .12f, art * .14f))
        listOf(frontX + art * .07f, minOf(w - art * .08f, sx + art * .94f)).forEach { x ->
            drawRoundRect(Brush.horizontalGradient(listOf(timberEdge, timber)),
                Offset(x, frontY), Size(art * .035f, art * .15f),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(art * .008f))
        }
        val edge = Path().apply {
            moveTo(frontX, frontY); lineTo(w, frontY)
            lineTo(w, frontY + depth); lineTo(frontX, frontY + depth); close()
        }
        drawPath(edge, Brush.verticalGradient(listOf(timberEdge, timberEdge.copy(alpha = .75f)),
            startY = frontY, endY = frontY + depth))
        val deck = Path().apply {
            moveTo(rearX, rearY); lineTo(w, rearY)
            lineTo(w, frontY); lineTo(frontX, frontY); close()
        }
        drawPath(deck, Brush.verticalGradient(
            listOf(if (dark) Color(0xFF80705A) else Color(0xFFE1C593), timber),
            startY = rearY, endY = frontY))
        for (i in 1..5) {
            val t = i / 6f
            val y = rearY + (frontY - rearY) * t
            val x = rearX + (frontX - rearX) * t
            drawLine(timberEdge.copy(alpha = .65f), Offset(x, y), Offset(w, y), art * .003f)
            drawLine(Color(0xFFFFE8BD).copy(alpha = if (dark) .13f else .38f),
                Offset(x, y + art * .004f), Offset(w, y + art * .004f), art * .002f)
        }
        drawLine(timberEdge, Offset(frontX, frontY), Offset(w, frontY), art * .005f)
        // Soft layers keep the original feet seated on the deck without repainting the character.
        for (i in 8 downTo 1) {
            val spread = i / 8f
            drawOval(Color(0xFF28332A).copy(alpha = (if (profile.hovering) .010f else .018f) + (1f - spread) * .025f),
                Offset(sx + art * ((if (profile.castsRight) 1f - profile.bodyX else profile.bodyX) - profile.shadowWidth / 2f * spread), contactY - art * .035f * spread),
                Size(art * profile.shadowWidth * spread, art * .075f * spread))
        }
        }
        // Water contact follows the same animation frame as the unmodified sprite.
        // Lift/catch/escape frames have no resting contact ring.
        val contact = profile.contacts[frame] ?: return@Canvas
        val waterY = sy + art * contact.y
        val waterX = sx + art * contact.x
        for (i in 1..3) {
            val radius = art * (.025f + i * .018f)
            drawOval(ripple.copy(alpha = .65f / i),
                Offset(waterX - radius, waterY - radius * .24f),
                Size(radius * 2f, radius * .48f), style = Stroke(art * .003f))
        }
    }
}
