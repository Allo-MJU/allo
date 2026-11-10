package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.allo.car.model.GameState

/** The caller provides sharing only after the real parking/UX gate allows it. */
@Composable
fun ParkedScreen(
    game: GameState,
    connected: Boolean = true,
    onShare: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val summary = PetSummary.from(game, connected, rememberSpeciesCatalog())
    BoxWithConstraints(modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        val narrow = maxWidth < 560.dp
        Column(
            Modifier.widthIn(max = 760.dp).verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("알로 · 주차 중", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 18.sp)
            if (narrow) {
                PetArt(summary, 100.dp)
                SummaryText(summary, centered = true)
            } else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                    PetArt(summary, 132.dp)
                    SummaryText(summary, centered = false)
                }
            }
            Text("주차 중에는 폰 화면을 함께 볼 수 있어요.", fontSize = 18.sp, lineHeight = 26.sp,
                textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (onShare != null) {
                Button(onClick = onShare, modifier = Modifier.heightIn(min = 56.dp)) {
                    Text("폰 화면 공유", fontSize = 22.sp)
                }
                Text("폰에서 공유를 시작하면 화면이 표시돼요.", fontSize = 16.sp, lineHeight = 24.sp,
                    textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Text("화면 공유 연결을 준비하고 있어요.", fontSize = 16.sp, lineHeight = 24.sp,
                    textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
