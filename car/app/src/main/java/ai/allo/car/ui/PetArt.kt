package ai.allo.car.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp

@Composable
fun rememberSpeciesCatalog(): SpeciesCatalog {
    val assets = LocalContext.current.assets
    return remember(assets) {
        runCatching { assets.open("species.json").bufferedReader().use { SpeciesCatalog.parse(it.readText()) } }
            .getOrDefault(SpeciesCatalog.EMPTY)
    }
}

/** Static image only. Missing artist assets use an explicitly labelled placeholder. */
@Composable
fun PetArt(summary: PetSummary, size: Dp, modifier: Modifier = Modifier) {
    if (summary.showEgg) {
        EggMark(size = size, fill = summary.eggFill, modifier = modifier.semantics { contentDescription = "알" })
        return
    }
    val assets = LocalContext.current.assets
    val sprite = summary.species?.sprite
    val bitmap = remember(assets, sprite) {
        sprite?.let { path -> runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            assets.open(path).use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth !in 1..2048 || bounds.outHeight !in 1..2048) return@runCatching null
            assets.open(path).use { BitmapFactory.decodeStream(it)?.asImageBitmap() }
        }.getOrNull() }
    }
    if (bitmap != null) {
        Image(bitmap, contentDescription = summary.title, modifier = modifier.size(size))
        return
    }
    val color = when (summary.species?.attribute) {
        "water" -> Color(0xFF7CCEDB)
        "dark" -> Color(0xFFC5ABEC)
        else -> Color(0xFF95D5BC)
    }
    Canvas(modifier.size(size).semantics { contentDescription = "${summary.title} · 임시 펫 아이콘" }) {
        val w = this.size.width
        val h = this.size.height
        drawOval(color.copy(alpha = 0.12f), Offset(w * .08f, h * .86f), Size(w * .84f, h * .1f))
        drawOval(color, Offset(w * .18f, h * .08f), Size(w * .22f, h * .42f))
        drawOval(color, Offset(w * .60f, h * .08f), Size(w * .22f, h * .42f))
        drawOval(color, Offset(w * .10f, h * .28f), Size(w * .80f, h * .60f))
        drawCircle(AlloColors.Night, w * .035f, Offset(w * .35f, h * .55f))
        drawCircle(AlloColors.Night, w * .035f, Offset(w * .65f, h * .55f))
        drawArc(AlloColors.Night, 15f, 150f, false, Offset(w * .43f, h * .60f), Size(w * .14f, h * .10f), style = Stroke(w * .025f))
        drawCircle(Color(0xFFE99EA9), w * .055f, Offset(w * .25f, h * .66f))
        drawCircle(Color(0xFFE99EA9), w * .055f, Offset(w * .75f, h * .66f))
    }
}
