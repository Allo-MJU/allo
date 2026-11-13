package ai.allo.car.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp

/** Literal copies of Desktop/assets. These IDs are artwork identities, not gameplay aliases. */
object SuppliedCharacters {
    val ids = setOf("road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist",
        "breeze_wyrm", "cloud_strider", "dewcap", "dune_roller", "ember_crab", "pebble_orbit")
    fun path(id: String?, pose: PetPose): String? {
        if (id !in ids) return null
        val file = when (pose.name) {
            "Sleep" -> "sleep"
            "Move" -> "move"
            "Fall" -> "surprised"
            else -> "idle" // No supplied fishing animation: keep the original idle drawing.
        }
        return "poses/$id/$file.png"
    }
}

@Composable
internal fun SuppliedCharacterArt(summary: PetSummary, size: Dp, modifier: Modifier, pose: PetPose) {
    val assets = LocalContext.current.assets
    val path = SuppliedCharacters.path(summary.species?.id, pose)
    val bitmap = remember(assets, path) {
        path?.let { runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            assets.open(it).use { input -> BitmapFactory.decodeStream(input, null, bounds) }
            if (bounds.outWidth !in 1..2048 || bounds.outHeight !in 1..2048) return@runCatching null
            assets.open(it).use { input -> BitmapFactory.decodeStream(input)?.asImageBitmap() }
        }.getOrNull() }
    }
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        if (bitmap != null) Image(bitmap, contentDescription = "${summary.title} · ${pose.label}", modifier = Modifier.size(size))
        else Text("원본 이미지 미연결")
    }
}
