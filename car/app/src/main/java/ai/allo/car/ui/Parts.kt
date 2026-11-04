package ai.allo.car.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * 알 모양 표시. [fill] 0~1 만큼 아래에서부터 노랗게 찬다 (진행도).
 * D 아트가 나오기 전 임시 그래픽.
 */
@Composable
fun EggMark(size: Dp, fill: Float = 1f, modifier: Modifier = Modifier) {
    Canvas(modifier.size(width = size * 0.78f, height = size)) {
        val w = this.size.width; val h = this.size.height
        // 위가 좁고 아래가 넓은 알 윤곽
        val egg = Path().apply {
            moveTo(w / 2, 0f)
            cubicTo(w * 0.92f, 0f, w, h * 0.62f, w, h * 0.68f)
            cubicTo(w, h * 0.9f, w * 0.78f, h, w / 2, h)
            cubicTo(w * 0.22f, h, 0f, h * 0.9f, 0f, h * 0.68f)
            cubicTo(0f, h * 0.62f, w * 0.08f, 0f, w / 2, 0f)
            close()
        }
        drawPath(egg, AlloColors.Track)
        val f = fill.coerceIn(0f, 1f)
        clipPath(egg) { drawRect(AlloColors.Egg, topLeft = Offset(0f, h * (1 - f)), size = Size(w, h * f)) }
        drawPath(egg, AlloColors.EggDeep, style = Stroke(width = w * 0.04f))
    }
}

/** 두꺼운 둥근 진행바. Material 기본 진행바보다 멀리서 잘 보인다. */
@Composable
fun ThickProgress(progress: Float, modifier: Modifier = Modifier, height: Dp = 28.dp) {
    val shape = RoundedCornerShape(height / 2)
    Box(modifier.height(height).clip(shape).background(AlloColors.Track)) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(progress.coerceIn(0f, 1f)).clip(shape).background(AlloColors.Egg))
    }
}
