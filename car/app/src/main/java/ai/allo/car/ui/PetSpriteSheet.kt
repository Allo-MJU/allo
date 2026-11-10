package ai.allo.car.ui

import android.graphics.BitmapFactory
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import kotlin.math.roundToInt

@Composable
internal fun rememberPetSpriteSheet(spec: PetSpriteSpec?): ImageBitmap? {
    val assets = LocalContext.current.assets
    return remember(assets, spec) {
        spec?.let { runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            assets.open(spec.path).use { BitmapFactory.decodeStream(it, null, bounds) }
            if (!spec.validDimensions(bounds.outWidth, bounds.outHeight)) return@runCatching null
            assets.open(spec.path).use { BitmapFactory.decodeStream(it)?.asImageBitmap() }
        }.getOrNull() }
    }
}

/** No bounce/scale layer: all limb movement comes from the source frame's artwork. */
@Composable
internal fun PetSpriteSheet(
    bitmap: ImageBitmap,
    spec: PetSpriteSpec,
    enabled: Boolean,
    description: String,
    size: Dp,
    modifier: Modifier = Modifier,
) {
    val elapsed = if (enabled) {
        val transition = rememberInfiniteTransition(label = "pet sprite action")
        val value by transition.animateFloat(0f, spec.durationMs.toFloat(),
            infiniteRepeatable(tween(spec.durationMs, easing = LinearEasing), RepeatMode.Restart), label = "sprite frame")
        value.toLong()
    } else 0L
    val frame = spec.frameAt(elapsed, enabled)
    Canvas(modifier.size(size).semantics { contentDescription = description }) {
        // Average dimensions keep the destination stable when source cells differ by one pixel.
        val width = bitmap.width.toFloat() / spec.columns
        val height = bitmap.height.toFloat() / spec.rows
        val cell = spec.sourceRect(frame, bitmap.width, bitmap.height)
        val scale = minOf(this.size.width / width, this.size.height / height)
        val targetWidth = (width * scale).roundToInt()
        val targetHeight = (height * scale).roundToInt()
        drawImage(bitmap,
            srcOffset = IntOffset(cell.left, cell.top), srcSize = IntSize(cell.width, cell.height),
            dstOffset = IntOffset(((this.size.width - targetWidth) / 2).roundToInt(), ((this.size.height - targetHeight) / 2).roundToInt()),
            dstSize = IntSize(targetWidth, targetHeight), filterQuality = FilterQuality.High)
    }
}
