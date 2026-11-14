package ai.allo.car.ui

import ai.allo.car.R
import ai.allo.car.model.GameState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp

/** Decorative notebook framing; the supplied content remains the real travel request flow. */
@Composable
internal fun TravelNotebook(game: GameState, connected: Boolean, minHeight: androidx.compose.ui.unit.Dp = 0.dp, content: @Composable () -> Unit) {
    val summary = PetSummary.from(game, connected, rememberSpeciesCatalog())
    NotebookSpread(
        minHeight = minHeight,
        scene = {
            Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Surface(color = Color(0xFFFFF9E9), contentColor = Color(0xFF294637),
                    shape = RoundedCornerShape(28.dp), border = BorderStroke(1.dp, Color(0xFF72845B))) {
                    Text("다음 풍경도\n함께 만나러 가요", Modifier.padding(24.dp), style = MaterialTheme.typography.headlineSmall)
                }
                BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    if (summary.showArt) PlazaPetArt(summary, (maxWidth * .85f).coerceIn(160.dp, 340.dp), Modifier, connected, false)
                    else AlloWordmark(Modifier.width(180.dp).height(120.dp))
                }
            }
        },
        page = {
            NotebookPaper("함께 떠날 곳", "친구와 쌓아가는 작은 추억") {
                NotebookRoute()
                Text("함께 꿈꾸는 풍경", style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                content()
            }
        },
    )
}

/**
 * The garden behind every parked page, edge to edge under the system bars and navigation.
 * [paper] lays an almost opaque sheet over it for pages that are plain text rather than a scene.
 */
@Composable
internal fun GardenBackdrop(modifier: Modifier = Modifier, paper: Boolean = false) {
    val dark = MaterialTheme.colorScheme.surface.luminance() < .35f
    Box(modifier) {
        Image(painterResource(R.drawable.plaza_garden), null, Modifier.matchParentSize(), contentScale = ContentScale.Crop)
        Box(Modifier.matchParentSize().background(if (paper)
            Brush.verticalGradient(listOf(if (dark) Color(0xE622302A) else Color(0xE6FAF7EE), if (dark) Color(0xF522302A) else Color(0xF5FAF7EE)))
            else Brush.horizontalGradient(listOf(
                if (dark) Color(0xBB142E29) else Color(0x20487044),
                if (dark) Color(0xF022302A) else Color(0xEEFAF6E9)))))
    }
}

/** Scene beside paper. The backdrop is the caller's [GardenBackdrop], so nothing is boxed in here. */
@Composable
internal fun NotebookSpread(minHeight: androidx.compose.ui.unit.Dp = 0.dp, scene: @Composable () -> Unit, page: @Composable () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val wide = maxWidth >= 1000.dp && LocalDensity.current.fontScale <= 1.4f
        if (wide) Row(Modifier.fillMaxWidth().heightIn(min = minHeight).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            Box(Modifier.weight(.43f)) { scene() }
            Box(Modifier.weight(.57f)) { page() }
        } else Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            scene(); page()
        }
    }
}

@Composable
internal fun NotebookPaper(title: String, subtitle: String, content: @Composable ColumnScope.() -> Unit) {
    val dark = MaterialTheme.colorScheme.surface.luminance() < .35f
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp), shadowElevation = 5.dp,
        color = if (dark) Color(0xFF303B30) else Color(0xFFFFFBED),
        contentColor = if (dark) Color(0xFFF0EEDA) else Color(0xFF30492C),
        border = BorderStroke(1.dp, if (dark) Color(0xFF788467) else Color(0xFFD7C8A4))) {
        Column(Modifier.padding(10.dp).drawBehind {
            drawRoundRect(if (dark) Color(0xFF788467) else Color(0xFFC5BA92),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(6.dp.toPx()),
                style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 5.dp.toPx()))))
        }.padding(6.dp).clip(RoundedCornerShape(6.dp))
            .background(if (dark) Color(0xFF303B30) else Color(0xFFFFFBED))
            .padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("❧", style = MaterialTheme.typography.headlineLarge)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(title, style = MaterialTheme.typography.headlineSmall)
                    Text(subtitle, style = MaterialTheme.typography.bodyMedium)
                }
            }
            HorizontalDivider(color = if (dark) Color(0xFF66745C) else Color(0xFFD7C8A4))
            content()
        }
    }
}

/** A non-interactive landscape motif, not a map or a claim of completed travel. */
@Composable
private fun NotebookRoute() {
    val dark = MaterialTheme.colorScheme.surface.luminance() < .35f
    Image(painterResource(R.drawable.travel_postcard), null,
        Modifier.fillMaxWidth().aspectRatio(1.65f).clip(RoundedCornerShape(12.dp)),
        contentScale = ContentScale.Crop,
        colorFilter = if (dark) ColorFilter.colorMatrix(ColorMatrix(floatArrayOf(
            .65f,0f,0f,0f,0f, 0f,.67f,0f,0f,0f, 0f,0f,.66f,0f,0f, 0f,0f,0f,1f,0f))) else null)
}
