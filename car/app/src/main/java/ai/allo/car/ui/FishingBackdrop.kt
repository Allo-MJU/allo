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

/** Quiet, static waterside scenery. All coordinates follow the available app pane. */
@Composable
internal fun FishingBackdrop(modifier: Modifier = Modifier) {
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

        // Broad silhouettes leave the central character area visually quiet.
        val distant = Path().apply {
            moveTo(0f, h * .44f)
            cubicTo(w * .12f, h * .24f, w * .24f, h * .28f, w * .37f, h * .40f)
            cubicTo(w * .52f, h * .51f, w * .66f, h * .22f, w * .81f, h * .34f)
            cubicTo(w * .90f, h * .40f, w * .96f, h * .34f, w, h * .37f)
            lineTo(w, h * .59f); lineTo(0f, h * .59f); close()
        }
        drawPath(distant, farHill)
        val bank = Path().apply {
            moveTo(0f, h * .51f)
            cubicTo(w * .14f, h * .38f, w * .29f, h * .52f, w * .46f, h * .50f)
            cubicTo(w * .64f, h * .46f, w * .83f, h * .43f, w, h * .51f)
            lineTo(w, h * .60f); lineTo(0f, h * .60f); close()
        }
        drawPath(bank, nearHill)
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

        // Original fishing art casts left; keep water there and the pier beneath its feet on the right.
        withTransform({ scale(-1f, 1f, pivot = Offset(w / 2f, 0f)) }) {
        val deck = Path().apply {
            moveTo(0f, h * .70f); lineTo(w * .36f, h * .70f)
            lineTo(w * .53f, h * .82f); lineTo(0f, h * .82f); close()
        }
        val fascia = Path().apply {
            moveTo(0f, h * .82f); lineTo(w * .53f, h * .82f)
            lineTo(w * .53f, h * .85f); lineTo(0f, h * .85f); close()
        }
        drawRect(timberEdge, Offset(w * .08f, h * .83f), Size(w * .025f, h * .12f))
        drawRect(timberEdge, Offset(w * .43f, h * .83f), Size(w * .025f, h * .10f))
        drawPath(fascia, timberEdge)
        drawPath(deck, timber)
        for (i in 1..4) {
            val t = i / 5f
            drawLine(timberEdge.copy(alpha = .50f), Offset(0f, h * (.70f + .12f * t)),
                Offset(w * (.36f + .17f * t), h * (.70f + .12f * t)), strokeWidth = unit * .003f)
        }
        }
    }
}
