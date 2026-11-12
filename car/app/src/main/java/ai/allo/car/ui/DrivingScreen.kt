package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Surface
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
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
import ai.allo.car.model.PleosRoute

/** Automatic fishing visualizes phone-owned material collection; rendering never grants rewards. */
@Composable
fun DrivingScreen(
    game: GameState,
    connected: Boolean = true,
    modifier: Modifier = Modifier,
    fishingMotion: Boolean = true,
    drivingSignalFresh: Boolean = false,
    statusMessage: String? = null,
) {
    val summary = PetSummary.from(game, connected, rememberSpeciesCatalog())
    val fishingActive = connected && drivingSignalFresh && summary.showArt && !summary.showEgg
    ScreenFrame(if (fishingActive) "주행 · 자동 낚시" else "주행 · 상태 확인", statusMessage ?: if (connected) "폰 상태 연결됨" else "연결 확인 필요", modifier) {
        BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            val layout = DrivingWindowLayout.forContent(maxWidth.value, maxHeight.value, LocalDensity.current.fontScale)
            val artSize = layout.artSizeDp.dp
            val displayedSummary = summary.copy(status = statusMessage ?:
                if (fishingActive) "주행 재료 수집 · 자동 낚시" else summary.status)
            val art: @Composable (Modifier) -> Unit = { sceneModifier ->
                BoxWithConstraints(sceneModifier.clip(RoundedCornerShape(32.dp))) {
                    val fittedArtSize = minOf(artSize, maxHeight * .86f, (maxWidth - 24.dp).coerceAtLeast(0.dp))
                    FishingBackdrop(Modifier.fillMaxSize())
                    if (summary.showArt && artSize > 0.dp) {
                        // Keep the entire sprite sheet visible, including the fishing rod and catch.
                        Box(Modifier.fillMaxSize().padding(bottom = maxHeight * .10f), contentAlignment = Alignment.BottomCenter) {
                            PetArt(summary, fittedArtSize,
                                pose = PetPoses.forRoute(PleosRoute.Driving, connected, drivingSignalFresh),
                                connected = connected && drivingSignalFresh, drivingFishing = fishingMotion)
                        }
                    }
                }
            }
            val details: @Composable (Modifier) -> Unit = { detailsModifier ->
                Surface(detailsModifier, shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.surfaceContainerLow) {
                    Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SummaryText(displayedSummary, centered = false)
                        if (layout.showFootnote) Text("도감과 거점은 주차 후 확인해 주세요.", style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            if (layout.horizontal) {
                Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    art(Modifier.weight(.58f).fillMaxHeight())
                    details(Modifier.weight(.42f))
                }
            } else {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    art(Modifier.fillMaxWidth().weight(1f))
                    details(Modifier.fillMaxWidth())
                }
            }
        }
    }
}

@Composable
internal fun SummaryText(summary: PetSummary, centered: Boolean) {
    Column(horizontalAlignment = if (centered) Alignment.CenterHorizontally else Alignment.Start) {
        Text(summary.title, fontSize = 32.sp, lineHeight = 40.sp, fontWeight = FontWeight.SemiBold,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(8.dp))
        Text(summary.status, fontSize = 24.sp, lineHeight = 32.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = if (centered) TextAlign.Center else TextAlign.Start,
            maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}
