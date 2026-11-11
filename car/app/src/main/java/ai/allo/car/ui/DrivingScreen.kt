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

/** Production driving summary with running frames and shared interruption gates. */
@Composable
fun DrivingScreen(game: GameState, connected: Boolean = true, modifier: Modifier = Modifier, runningMotion: Boolean = true) {
    val summary = PetSummary.from(game, connected, rememberSpeciesCatalog())
    BoxWithConstraints(modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        val narrow = maxWidth < 560.dp
        val artSize = if (narrow) 112.dp else 156.dp
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Text("알로 · 주행 중", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 18.sp)
            Spacer(Modifier.height(20.dp))
            if (narrow) {
                if (summary.showArt) PetArt(summary, artSize, pose = PetPose.Move, connected = connected, runningMotion = runningMotion)
                Spacer(Modifier.height(16.dp))
                SummaryText(summary, centered = true)
            } else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(32.dp)) {
                    if (summary.showArt) PetArt(summary, artSize, pose = PetPose.Move, connected = connected, runningMotion = runningMotion)
                    SummaryText(summary, centered = false)
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
