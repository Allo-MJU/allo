package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.allo.car.model.GameState

/** Driving has no actions. Static run pose is the #92 design default; motion remains opt-in. */
@Composable
fun DrivingScreen(
    game: GameState,
    connected: Boolean = true,
    modifier: Modifier = Modifier,
    runningMotion: Boolean = false,
    statusMessage: String? = null,
) {
    val summary = PetSummary.from(game, connected, rememberSpeciesCatalog())
    ScreenFrame("주행 · 제한", statusMessage ?: if (connected) "폰 상태 연결됨" else "폰 상태 확인 중", modifier) {
        BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            val compact = maxWidth < 560.dp || maxHeight < 300.dp
            val artSize = if (compact) 112.dp else 220.dp
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (summary.showArt) PetArt(summary, artSize, pose = PetPose.Move,
                    connected = connected, runningMotion = runningMotion)
                SummaryText(if (statusMessage != null) summary.copy(status = statusMessage) else summary, centered = true)
                Text("자세한 내용은 주차 후 확인해 주세요.", style = MaterialTheme.typography.bodyMedium,
                    color = AlloColors.MistDim, textAlign = TextAlign.Center)
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
