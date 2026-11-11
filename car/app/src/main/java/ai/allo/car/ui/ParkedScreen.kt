package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.material3.FilterChip
import androidx.compose.runtime.saveable.rememberSaveable
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
    transferMessage: String? = null,
    onCallCompanion: (() -> Unit)? = null,
    onRetryTransfer: (() -> Unit)? = null,
    exitSerial: Long = 0,
    travelContent: (@Composable () -> Unit)? = null,
) {
    val catalog = rememberSpeciesCatalog()
    val summary = PetSummary.from(game, connected, catalog)
    var previousCarPet by remember { mutableStateOf<PetSummary?>(null) }
    var departing by remember { mutableStateOf<PetSummary?>(null) }
    val exit = remember { Animatable(0f) }
    var observedExit by remember { mutableLongStateOf(exitSerial) }
    // Capture the previous rendered companion before SideEffect caches this snapshot.
    // An accepted transfer may arrive together with a different companion selection.
    val departureCandidate = remember(exitSerial) { previousCarPet }
    LaunchedEffect(exitSerial, connected) {
        if (exitSerial != observedExit) {
            observedExit = exitSerial
            if (connected && departureCandidate != null) {
                departing = departureCandidate
                exit.snapTo(0f)
                exit.animateTo(1f, tween(900))
                departing = null
                previousCarPet = null
            }
        }
        if (!connected) departing = null
    }
    SideEffect { if (summary.showArt && !summary.showEgg) previousCarPet = summary }
    val displayed = departing ?: summary
    var fishing by rememberSaveable { mutableStateOf(true) }
    val pose = if (fishing) PetPose.Fishing else PetPose.Sleep
    BoxWithConstraints(modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        val narrow = maxWidth < 560.dp
        Column(
            Modifier.widthIn(max = 760.dp).verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("알로 · 주차 중", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 18.sp)
            if (narrow) {
                if (displayed.showArt) PetArt(displayed, 140.dp,
                    modifier = Modifier.graphicsLayer { translationX = if(departing != null) exit.value * 180f * density else 0f; alpha = if (departing != null) 1f-exit.value else 1f },
                    pose = if(departing != null) PetPose.Move else pose, parked = departing == null, connected = connected, runningMotion = departing != null)
                SummaryText(if (departing != null) displayed.copy(status = "폰으로 이동하는 중") else summary, centered = true)
            } else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                    if (displayed.showArt) PetArt(displayed, 180.dp,
                        modifier = Modifier.graphicsLayer { translationX = if(departing != null) exit.value * 200f * density else 0f; alpha = if(departing != null) 1f-exit.value else 1f },
                        pose = if(departing != null) PetPose.Move else pose, parked = departing == null, connected = connected, runningMotion = departing != null)
                    SummaryText(if (departing != null) displayed.copy(status = "폰으로 이동하는 중") else summary, centered = false)
                }
            }
            if (summary.showArt && !summary.showEgg && departing == null) {
                Text("쉬는 모습 고르기", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    FilterChip(selected = !fishing, onClick = { fishing = false }, label = { Text("잠자기") })
                    FilterChip(selected = fishing, onClick = { fishing = true }, label = { Text("낚시") })
                }
            }
            transferMessage?.let { Text(it, textAlign = TextAlign.Center) }
            onCallCompanion?.let { Button(onClick = it, enabled = connected) { Text("폰으로 친구 부르기") } }
            onRetryTransfer?.let { Button(onClick = it, enabled = connected) { Text("이동 상태 다시 확인") } }
            FeatureStatusCards(game, catalog)
            travelContent?.invoke()
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
