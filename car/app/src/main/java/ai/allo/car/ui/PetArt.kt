package ai.allo.car.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Box
import androidx.compose.animation.core.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.graphicsLayer
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import android.provider.Settings
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

/** Driving poses remain static. Only verified parking callers opt into ambient motion. */
@Composable
fun PetArt(
    summary: PetSummary,
    size: Dp,
    modifier: Modifier = Modifier,
    pose: PetPose = PetPose.Idle,
    parked: Boolean = false,
    connected: Boolean = true,
) {
    if (summary.showEgg) {
        EggMark(size = size, fill = summary.eggFill, modifier = modifier.semantics { contentDescription = "알" })
        return
    }
    val assets = LocalContext.current.assets
    val sprite = PetPoses.assetPath(summary.species?.id, pose) ?: summary.species?.sprite
    val bitmap = remember(assets, sprite) {
        sprite?.let { path -> runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            assets.open(path).use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth !in 1..2048 || bounds.outHeight !in 1..2048) return@runCatching null
            assets.open(path).use { BitmapFactory.decodeStream(it)?.asImageBitmap() }
        }.getOrNull() }
    }
    val animate = ambientMotionAllowed(pose, parked, connected)
    val phase = if (animate) {
        val transition = rememberInfiniteTransition(label = "parked pet")
        val value by transition.animateFloat(0f, 1f,
            infiniteRepeatable(tween(2400, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "breathing")
        value
    } else 0f
    val artModifier = Modifier.size(size).graphicsLayer {
        if (pose == PetPose.Sleep) {
            scaleY = 1f + phase * .025f
            scaleX = 1f + phase * .012f
        } else if (pose == PetPose.Fishing) {
            rotationZ = phase * 1.5f
        }
    }
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        if (bitmap != null) {
            Image(bitmap, contentDescription = "${summary.title} · ${pose.label}", modifier = artModifier)
        } else {
            PlaceholderPet(summary, size, artModifier, pose)
        }
        if (pose == PetPose.Sleep || pose == PetPose.Fishing) {
            RestScene(pose, phase, size)
        }
    }
}

@Composable
private fun ambientMotionAllowed(pose: PetPose, parked: Boolean, connected: Boolean): Boolean {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val resolver = LocalContext.current.contentResolver
    var resumed by remember(lifecycle) { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    var motionEnabled by remember { mutableStateOf(true) }
    DisposableEffect(lifecycle, resolver) {
        fun refresh() {
            resumed = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
            motionEnabled = runCatching { Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f }.getOrDefault(false)
        }
        val observer = LifecycleEventObserver { _, _ -> refresh() }
        lifecycle.addObserver(observer)
        refresh()
        onDispose { lifecycle.removeObserver(observer) }
    }
    return PetPoses.animates(pose, parked, connected, resumed, motionEnabled)
}

@Composable
private fun PlaceholderPet(summary: PetSummary, size: Dp, modifier: Modifier, pose: PetPose) {
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
        if (pose == PetPose.Sleep) {
            drawLine(AlloColors.Night, Offset(w * .30f, h * .56f), Offset(w * .40f, h * .56f), w * .025f)
            drawLine(AlloColors.Night, Offset(w * .60f, h * .56f), Offset(w * .70f, h * .56f), w * .025f)
        } else {
            drawCircle(AlloColors.Night, w * .035f, Offset(w * .35f, h * .55f))
            drawCircle(AlloColors.Night, w * .035f, Offset(w * .65f, h * .55f))
        }
        drawArc(AlloColors.Night, 15f, 150f, false, Offset(w * .43f, h * .60f), Size(w * .14f, h * .10f), style = Stroke(w * .025f))
        drawCircle(Color(0xFFE99EA9), w * .055f, Offset(w * .25f, h * .66f))
        drawCircle(Color(0xFFE99EA9), w * .055f, Offset(w * .75f, h * .66f))
    }
}


/** Small vector props around existing art; no fishing sprite is implied. */
@Composable
private fun RestScene(pose: PetPose, phase: Float, size: Dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.width
        val h = this.size.height
        if (pose == PetPose.Fishing) {
            val tip = Offset(w * .87f, h * (.16f + phase * .015f))
            val bob = Offset(w * .91f, h * (.82f + phase * .025f))
            drawOval(Color(0xFF7CCEDB).copy(alpha = .24f), Offset(w * .69f, h * .82f), Size(w * .30f, h * .10f))
            drawLine(Color(0xFFD3AC76), Offset(w * .57f, h * .64f), tip, w * .023f)
            drawLine(Color(0xFFE5E6EF), tip, bob, w * .007f)
            drawCircle(Color(0xFFFFCC55), w * .025f, bob)
        } else {
            // Quiet sleep mark, with no blinking or textual game-state claim.
            val x = w * .77f
            val y = h * (.18f - phase * .025f)
            val c = Color(0xFFB8BCD5).copy(alpha = .7f)
            drawLine(c, Offset(x, y), Offset(x + w * .1f, y), w * .015f)
            drawLine(c, Offset(x + w * .1f, y), Offset(x, y + h * .1f), w * .015f)
            drawLine(c, Offset(x, y + h * .1f), Offset(x + w * .1f, y + h * .1f), w * .015f)
        }
    }
}
