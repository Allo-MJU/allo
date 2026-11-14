package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Surface
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.runtime.*
import androidx.compose.animation.core.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.layout.onSizeChanged
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
    fishingElapsedMs: Long? = null,
) {
    val summary = PetSummary.from(game, connected, rememberSpeciesCatalog())
    val fishingActive = connected && drivingSignalFresh && summary.showArt && !summary.showEgg
    val animate = ambientMotionAllowed(PetPose.Fishing, false, fishingActive, false, fishingMotion)
    val sceneElapsed = fishingElapsedMs ?: if (animate) {
        val transition = rememberInfiniteTransition(label = "fishing scene")
        val elapsed by transition.animateFloat(0f, PetSpriteSheets.fish.durationMs.toFloat(),
            infiniteRepeatable(tween(PetSpriteSheets.fish.durationMs, easing = LinearEasing), RepeatMode.Restart),
            label = "shared fishing frame")
        elapsed.toLong()
    } else 0L
    val sceneFrame = PetSpriteSheets.fish.frameAt(sceneElapsed, animate)
    // The pond owns the whole window; the header and status card sit on top of it.
    Surface(modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val windowWidth = maxWidth
            val windowHeight = maxHeight
            val short = windowHeight < 400.dp
            val compact = windowWidth < 600.dp
            val edge = if (short) 12.dp else if (compact) 20.dp else 28.dp
            val gap = if (short) 12.dp else 24.dp
            val safe = WindowInsets.safeDrawing.asPaddingValues()
            val direction = LocalLayoutDirection.current
            val left = safe.calculateLeftPadding(direction) + edge
            val right = safe.calculateRightPadding(direction) + edge
            val bottom = safe.calculateBottomPadding() + edge
            var headerHeight by remember { mutableStateOf(if (short) 44.dp else 64.dp) }
            var cardHeight by remember { mutableStateOf(0.dp) }
            val density = LocalDensity.current
            val contentTop = safe.calculateTopPadding() + edge + headerHeight + gap
            val contentWidth = (windowWidth - left - right).coerceAtLeast(0.dp)
            val contentHeight = (windowHeight - contentTop - bottom).coerceAtLeast(0.dp)
            val layout = DrivingWindowLayout.forContent(contentWidth.value, contentHeight.value, density.fontScale)
            // Horizontal: the character owns the middle of the pond under a small name tag.
            // Stacked: the character stands just above the card at the bottom.
            val centerX = left + contentWidth / 2
            val baselineY = if (layout.horizontal) windowHeight * .90f
                else windowHeight - bottom - cardHeight - 16.dp - contentHeight * .04f
            val artTop = if (layout.horizontal) contentTop + cardHeight + 8.dp else contentTop
            val artSize = minOf(if (layout.horizontal) 720.dp else layout.artSizeDp.dp, baselineY - artTop, contentWidth - 24.dp).coerceAtLeast(0.dp)
            val showCharacter = summary.showArt && artSize > 0.dp
            FishingBackdrop(Modifier.fillMaxSize(), artSize, summary.species?.id, summary.showArt && !summary.showEgg, sceneFrame,
                centerX = if (windowWidth > 0.dp) centerX / windowWidth else .5f,
                baseline = if (windowHeight > 0.dp) baselineY / windowHeight else .9f)
            // Keep the entire sprite sheet visible, including the fishing rod and catch.
            if (showCharacter) Box(Modifier.offset(centerX - artSize / 2, baselineY - artSize).size(artSize),
                contentAlignment = Alignment.BottomCenter) {
                PetArt(summary, artSize,
                    pose = PetPoses.forRoute(PleosRoute.Driving, connected, drivingSignalFresh),
                    connected = connected && drivingSignalFresh, drivingFishing = fishingMotion, elapsedMs = sceneElapsed)
            }
            val displayedSummary = summary.copy(status = statusMessage ?:
                if (fishingActive) "주행 재료 수집 · 자동 낚시" else summary.status)
            Column(Modifier.fillMaxSize().safeDrawingPadding().padding(edge)) {
                ScreenHeader(if (fishingActive) "주행 · 자동 낚시" else "주행 · 상태 확인",
                    statusMessage ?: if (connected) "폰 상태 연결됨" else "연결 확인 필요", compact, short,
                    Modifier.onSizeChanged { headerHeight = with(density) { it.height.toDp() } })
                Box(Modifier.weight(1f).fillMaxWidth().padding(top = gap),
                    contentAlignment = if (layout.horizontal) Alignment.TopCenter else Alignment.BottomCenter) {
                    if (layout.horizontal) Surface(Modifier.onSizeChanged { cardHeight = with(density) { it.height.toDp() } },
                        shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = .9f)) {
                        Row(Modifier.padding(horizontal = 28.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            Text(displayedSummary.title, fontSize = 28.sp, lineHeight = 36.sp, fontWeight = FontWeight.SemiBold,
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(displayedSummary.status, Modifier.weight(1f, fill = false), fontSize = 22.sp, lineHeight = 30.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    } else Surface(Modifier.fillMaxWidth()
                        .onSizeChanged { cardHeight = with(density) { it.height.toDp() } },
                        shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = .94f)) {
                        Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SummaryText(displayedSummary, centered = false)
                            if (layout.showFootnote) Text("도감과 거점은 주차 후 확인해 주세요.", style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                    }
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
