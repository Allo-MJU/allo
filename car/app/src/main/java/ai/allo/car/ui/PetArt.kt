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
import androidx.compose.ui.graphics.Path
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

/** Driving and parked poses share the same connection, lifecycle and motion-setting gates. */
@Composable
fun PetArt(
    summary: PetSummary,
    size: Dp,
    modifier: Modifier = Modifier,
    pose: PetPose = PetPose.Idle,
    parked: Boolean = false,
    connected: Boolean = true,
    runningMotion: Boolean = false,
) {
    if (summary.showEgg) {
        EggMark(size = size, fill = summary.eggFill, modifier = modifier.semantics { contentDescription = "알" })
        return
    }
    val animate = ambientMotionAllowed(pose, parked, connected, runningMotion)
    val sheetSpec = PetSpriteSheets.forDisplay(summary.species?.id, pose, parked, runningMotion)
    val sheet = rememberPetSpriteSheet(sheetSpec)
    if (sheet != null && sheetSpec != null) {
        PetSpriteSheet(sheet, sheetSpec, animate, "${summary.title} · ${pose.label}", size, modifier)
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
    val phase = if (animate) {
        val transition = rememberInfiniteTransition(label = "parked pet")
        val duration = when (pose) { PetPose.Move -> 800; PetPose.Fishing -> 7600; else -> 3200 }
        val value by transition.animateFloat(0f, 1f,
            infiniteRepeatable(tween(duration, easing = LinearEasing), RepeatMode.Restart), label = "ambient action")
        value
    } else 0f
    val motion = petMotion(phase, animate)
    val artModifier = Modifier.size(size).graphicsLayer {
        when (pose) {
            PetPose.Sleep -> {
                scaleY = 1f + motion.breathe * .075f
                scaleX = 1f + motion.breathe * .025f
                translationY = -this.size.height * .025f * motion.breathe
                rotationZ = -2f * motion.breathe
            }
            PetPose.Fishing -> {
                scaleX = .83f
                scaleY = .83f
                translationX = -this.size.width * .09f
                translationY = this.size.height * .06f
                rotationZ = -7f * motion.lift + if (motion.stage == FishingStage.Caught) kotlin.math.sin(phase * 80f) * 2f else 0f
            }
            PetPose.Move -> if (animate) {
                translationY = -this.size.height * .13f * motion.bounce
                rotationZ = -5f + kotlin.math.sin(phase * 2f * Math.PI.toFloat()) * 5f
                scaleX = 1.06f - .08f * motion.bounce
                scaleY = .93f + .11f * motion.bounce
            }
            else -> Unit
        }
    }
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        if (bitmap != null) {
            Image(bitmap, contentDescription = "${summary.title} · ${pose.label}", modifier = artModifier)
        } else {
            PlaceholderPet(summary, size, artModifier, pose)
        }
        if (pose == PetPose.Sleep || pose == PetPose.Fishing || runningMotion) {
            RestScene(pose, phase, motion, size, animate)
        }
    }
}

@Composable
private fun ambientMotionAllowed(pose: PetPose, parked: Boolean, connected: Boolean, runningMotion: Boolean): Boolean {
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
    return PetPoses.animates(pose, parked, connected, resumed, motionEnabled, runningMotion)
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


/** Illustrated props animate around the supplied PNG poses; the character art is preserved. */
@Composable
private fun RestScene(pose: PetPose, phase: Float, motion: PetMotion, size: Dp, animate: Boolean) {
    Canvas(Modifier.size(size)) {
        val w = this.size.width
        val h = this.size.height
        if (pose == PetPose.Fishing) {
            val pond = Color(0xFF7CCEDB)
            val tip = Offset(w * (.87f - .11f * motion.lift), h * (.23f - .13f * motion.lift))
            val bob = Offset(w * (.89f - .04f * motion.lift), h * (.81f - .45f * motion.lift))
            drawOval(pond.copy(alpha = .32f), Offset(w * .63f, h * .80f), Size(w * .36f, h * .15f))
            drawOval(pond.copy(alpha = .6f), Offset(w * .68f, h * .83f), Size(w * .26f, h * .07f), style = Stroke(w * .01f))
            drawLine(Color(0xFFD3AC76), Offset(w * .49f, h * .63f), tip, w * .025f)
            drawLine(Color(0xFFE5E6EF), tip, bob, w * .008f)
            drawCircle(Color(0xFFFFCC55), w * .025f, bob)
            if (motion.fish) {
                val wiggle = kotlin.math.sin(phase * 95f) * .018f
                val escape = motion.escape
                val center = Offset(bob.x + w * (wiggle + escape * .09f), bob.y + h * (.08f + escape * .39f))
                val fishColor = Color(0xFFFFBA70)
                val tail = Path().apply {
                    moveTo(center.x - w * .045f, center.y)
                    lineTo(center.x - w * .10f, center.y - h * .045f)
                    lineTo(center.x - w * .10f, center.y + h * .045f)
                    close()
                }
                drawPath(tail, fishColor)
                drawOval(fishColor, Offset(center.x - w * .055f, center.y - h * .035f), Size(w * .13f, h * .075f))
                drawCircle(AlloColors.Night, w * .009f, Offset(center.x + w * .04f, center.y - h * .008f))
            }
            if (motion.stage == FishingStage.Splash) {
                val splash = motion.splash
                val fade = (1f - splash).coerceIn(0f, 1f)
                repeat(5) { i ->
                    val spread = (i - 2) * .04f
                    val y = .85f - kotlin.math.sin(splash * Math.PI).toFloat() * (.12f - kotlin.math.abs(spread) * .3f)
                    drawCircle(pond.copy(alpha = fade), w * .013f,
                        Offset(w * (.87f + spread * (1f + splash)), h * y))
                }
                drawOval(pond.copy(alpha = fade), Offset(w * (.77f - .1f * splash), h * .85f),
                    Size(w * (.20f + .2f * splash), h * .07f), style = Stroke(w * .009f))
            }
        } else if (pose == PetPose.Sleep) {
            repeat(3) { i ->
                val drift = if (animate) (phase + i / 3f) % 1f else i / 3f
                val x = w * (.64f + drift * .20f)
                val y = h * (.34f - drift * .30f)
                val length = w * (.045f + drift * .04f)
                val alpha = if (animate) kotlin.math.sin(drift * Math.PI).toFloat().coerceIn(0f, 1f) else .6f
                val c = Color(0xFFCCD6F6).copy(alpha = alpha)
                drawLine(c, Offset(x, y), Offset(x + length, y), w * .012f)
                drawLine(c, Offset(x + length, y), Offset(x, y + length), w * .012f)
                drawLine(c, Offset(x, y + length), Offset(x + length, y + length), w * .012f)
            }
        } else if (pose == PetPose.Move && animate) {
            val ground = Color(0xFFB5DCCD)
            drawOval(ground.copy(alpha = .16f), Offset(w * (.22f + .05f * motion.bounce), h * .91f),
                Size(w * (.56f - .10f * motion.bounce), h * .07f))
            repeat(3) { i ->
                val travel = (phase + i / 3f) % 1f
                drawCircle(ground.copy(alpha = (1f - travel) * .45f), w * (.015f + travel * .025f),
                    Offset(w * (.35f - travel * .28f), h * (.91f - travel * .09f)))
                drawLine(ground.copy(alpha = .26f), Offset(w * (1f - travel), h * .985f),
                    Offset(w * (1f - travel) - w * .1f, h * .985f), w * .008f)
            }
        }
    }
}
