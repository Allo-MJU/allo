package ai.allo.car.ui

import ai.allo.car.model.GameState
import ai.allo.car.model.PleosRoute
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Actions are enabled only by the live, selected phone fishing capability. */
@Composable
fun ParkedScreen(
    game: GameState, connected: Boolean = true, onShare: (() -> Unit)? = null,
    modifier: Modifier = Modifier, transferMessage: String? = null,
    onCallCompanion: (() -> Unit)? = null, onRetryTransfer: (() -> Unit)? = null,
    exitSerial: Long = 0, travelContent: (@Composable () -> Unit)? = null,
    onStartFishing: (() -> Unit)? = null, fishingMessage: String? = null, onRetryFishing: (() -> Unit)? = null,
    fishingMotionAllowed: Boolean = false, onPauseFishing: (() -> Unit)? = null,
) {
    val catalog = rememberSpeciesCatalog()
    val summary = PetSummary.from(game, connected, catalog)
    val companionValid = "companion" !in game.invalidBlocks
    val emptyCompanion = game.hasV2Contract && companionValid &&
        (game.companion == null || game.companion?.location == "phone")
    val hasCarPet = if (game.hasV2Contract) companionValid && game.companion?.location == "car"
        else summary.showArt && !summary.showEgg
    // Selection/connection changes reset transient navigation and never auto-start an activity.
    var tab by remember(game.companion?.displayId, game.companion?.displayRevision, game.companion?.location, connected) { mutableStateOf("홈") }
    var resting by remember(game.companion?.displayId, game.companion?.displayRevision, game.companion?.location, connected) { mutableStateOf(false) }
    val fishingRunning = game.fishing?.takeIf { it.appliesTo(game) }?.state in setOf("running", "reward", "saving")
    if (resting && hasCarPet && connected && !fishingRunning) {
        PleosStatusScreen(PleosRoute.Paused, game, connected, onPrimary = { resting = false })
        return
    }
    ScreenFrame("주차 홈", if (connected) "폰 상태 연결됨" else "마지막으로 받은 상태", modifier) {
        ScreenColumns(art = {
            if (summary.showArt) PetArt(summary, 240.dp, pose = if (fishingRunning) PetPose.Fishing else PetPose.Sleep,
                parked = true, connected = connected && (!fishingRunning || fishingMotionAllowed && game.fishing?.state == "running"))
            else AlloWordmark(Modifier.width(180.dp))
        }, details = {
            when (tab) {
                "홈" -> {
                    Text(if (emptyCompanion) "함께할 친구를 골라 주세요" else summary.title,
                        style = MaterialTheme.typography.headlineMedium)
                    Text(when {
                        !companionValid -> "친구 상태를 다시 확인하고 있어요."
                        emptyCompanion -> "폰의 보유 친구 목록에서 차량과 함께할 친구를 선택해 주세요."
                        summary.showEgg -> summary.status
                        else -> "폰에서 선택한 친구가 함께해요."
                    }, style = MaterialTheme.typography.bodyLarge)
                    if (emptyCompanion) {
                        Text("선택과 차량 동행이 확인되면 친구를 보여드려요.", style = MaterialTheme.typography.bodyMedium)
                        ScreenAction("친구 선택 기다리는 중", {}, enabled = false)
                    }
                    val status = FeatureStatus.from(game, catalog)
                    if (status.incubation != null || status.affinity != null) Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            status.incubation?.let { Text(it) }; status.affinity?.let { Text(it) }
                        }
                    }
                    if (hasCarPet) {
                        ScreenAction("쉬는 시간", { if (fishingRunning) onPauseFishing?.invoke() else resting = true },
                            enabled = connected && (!fishingRunning || onPauseFishing != null && game.fishing?.state != "saving"), secondary = true)
                        ScreenAction(when (game.fishing?.state) {
                            "paused" -> "낚시 이어하기"; "saveFailed" -> "저장 다시 확인"
                            "running", "saving", "reward" -> "낚시 상태 보기"; else -> "낚시 시작"
                        }, { onStartFishing?.invoke() }, enabled = connected && onStartFishing != null)
                        onRetryFishing?.let { ScreenAction("낚시 요청 다시 확인", it, secondary = true) }
                        Text(fishingMessage ?: if (onStartFishing != null) "폰에서 진행과 관찰 기록을 저장해요." else "연결된 폰이 주차 낚시를 지원하면 시작할 수 있어요.", style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (hasCarPet) {
                        onCallCompanion?.let { ScreenAction("폰으로 친구 부르기", it, enabled = connected, secondary = true) }
                        onRetryTransfer?.let { ScreenAction("이동 상태 다시 확인", it, enabled = connected, secondary = true) }
                    }
                    transferMessage?.let { Text(it) }
                    Text("친구 변경은 폰의 보유 친구 목록에서", style = MaterialTheme.typography.bodyMedium)
                }
                "거점" -> {
                    Text("우리 거점", style = MaterialTheme.typography.headlineMedium)
                    val lines = FeatureStatus.from(game, catalog).baseLines
                    if (lines.isEmpty()) Text("폰에서 거점 활동을 확인해 주세요.")
                    else lines.forEach { Text(it, style = MaterialTheme.typography.bodyLarge) }
                }
                "여행" -> {
                    Text("함께 떠날 곳", style = MaterialTheme.typography.headlineMedium)
                    if (travelContent != null) travelContent() else Text("폰에서 여행 부탁을 보내 주세요.")
                }
                "폰 공유" -> {
                    Text("폰 화면 함께 보기", style = MaterialTheme.typography.headlineMedium)
                    Text("주차 중에 폰에서 화면 공유를 시작해 주세요.")
                    if (onShare != null) ScreenAction("폰 화면 공유", onShare, enabled = connected)
                    else Text("이 버전에서는 화면 공유를 지원하지 않아요.")
                }
            }
        }, modifier = Modifier.weight(1f))
        HorizontalDivider()
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            listOf("홈", "거점", "여행", "폰 공유").forEach { name ->
                FilterChip(selected = tab == name, onClick = { tab = name }, label = { Text(name) }, modifier = Modifier.heightIn(min = 56.dp))
            }
        }
    }
}
