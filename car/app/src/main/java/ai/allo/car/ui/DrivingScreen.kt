package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.allo.car.model.GameState
import ai.allo.car.model.DrivingMotionState

/** Driving has no actions. Existing run frames animate while connected, resumed and system motion is enabled. */
@Composable
fun DrivingScreen(
    game: GameState,
    connected: Boolean = true,
    modifier: Modifier = Modifier,
    runningMotion: Boolean = true,
    statusMessage: String? = null,
    drivingMotion: DrivingMotionState? = null,
) {
    val summary = PetSummary.from(game, connected, rememberSpeciesCatalog())
    ScreenFrame("주행 · 제한", statusMessage ?: if (connected) "폰 상태 연결됨" else "폰 상태 확인 중", modifier) {
        BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            val layout = DrivingWindowLayout.forContent(maxWidth.value, maxHeight.value, LocalDensity.current.fontScale)
            val artSize = layout.artSizeDp.dp
            val displayedSummary = if (statusMessage != null) summary.copy(status = statusMessage) else summary
            val art: @Composable () -> Unit = {
                if (summary.showArt && artSize > 0.dp) {
                    if (drivingMotion != null) DrivingPetArt(summary, artSize, drivingMotion, connected, runningMotion)
                    else PetArt(summary, artSize, pose = PetPose.Move,
                        connected = connected, runningMotion = runningMotion)
                }
            }
            val details: @Composable () -> Unit = {
                Column(horizontalAlignment = if (layout.horizontal) Alignment.Start else Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SummaryText(displayedSummary, centered = !layout.horizontal)
                    if (layout.showFootnote) Text("자세한 내용은 주차 후 확인해 주세요.", style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = if (layout.horizontal) TextAlign.Start else TextAlign.Center,
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
            if (layout.horizontal) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    art()
                    Box(Modifier.weight(1f)) { details() }
                }
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    art()
                    details()
                }
            }
        }
    }
}

@Composable
internal fun SummaryText(summary: PetSummary, centered: Boolean) {
    Column(horizontalAlignment = if (centered) Alignment.CenterHorizontally else Alignment.Start) {
        Text(summary.title, fontSize = 30.sp, lineHeight = 38.sp, fontWeight = FontWeight.SemiBold,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(8.dp))
        Text(summary.status, fontSize = 22.sp, lineHeight = 30.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = if (centered) TextAlign.Center else TextAlign.Start,
            maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}
