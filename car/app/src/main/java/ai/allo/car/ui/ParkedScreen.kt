package ai.allo.car.ui

import ai.allo.car.dialogue.DialogueBank
import ai.allo.car.model.GameState
import ai.allo.car.model.PlazaPopulation
import androidx.activity.compose.BackHandler
import androidx.compose.ui.platform.LocalContext
import android.content.Context
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance

/** Parked review of phone-owned information. Every mutation remains a supplied callback. */
@Composable
fun ParkedScreen(
    game: GameState, connected: Boolean = true, onShare: (() -> Unit)? = null,
    modifier: Modifier = Modifier, transferMessage: String? = null,
    onCallCompanion: (() -> Unit)? = null, onRetryTransfer: (() -> Unit)? = null,
    exitSerial: Long = 0, travelContent: (@Composable () -> Unit)? = null,
    dialogueBank: DialogueBank = DialogueBank.EMPTY, unreviewedDialoguePreview: Boolean = false,
) {
    val catalog = rememberSpeciesCatalog()
    val summary = PetSummary.from(game, connected, catalog)
    val companionValid = "companion" !in game.invalidBlocks
    val hasCarPet = if (game.hasV2Contract) companionValid && game.companion?.location == "car"
        else summary.showArt && !summary.showEgg
    var tab by rememberSaveable(game.companion?.displayId, game.companion?.displayRevision, game.companion?.location, connected) { mutableStateOf("광장") }
    val context = LocalContext.current
    val plazaPreferences = remember(context) { context.getSharedPreferences("plaza_display", Context.MODE_PRIVATE) }
    var chosenFriends by rememberSaveable {
        mutableStateOf(plazaPreferences.getString("species_ids", null)?.let { ArrayList(it.split(",").filter(String::isNotBlank)) })
    }
    val availableFriends = PlazaPopulation.residents(game).filter { it in SuppliedCharacters.ids && catalog[it] != null }
    val visibleFriends = PlazaPopulation.selected(availableFriends, chosenFriends)
    BackHandler(enabled = tab != "광장") { tab = "광장" }
    var materialsOpen by remember { mutableStateOf(false) }
    val dark = MaterialTheme.colorScheme.surface.luminance() < .35f
    val paper = if (dark) MaterialTheme.colorScheme.surface else Color(0xFFFAF7EE)
    Surface(modifier.fillMaxSize(), color = paper) {
        BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
            val compact = maxWidth < 700.dp
            Column(Modifier.fillMaxSize().padding(if (compact) 12.dp else 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    AlloWordmark(Modifier.width(if (compact) 88.dp else 132.dp).height(64.dp))
                    Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("광장", "이야기", "여행").forEach { name ->
                            FilterChip(selected = tab == name, onClick = { tab = name },
                                label = { Text(name, style = MaterialTheme.typography.titleSmall) },
                                modifier = Modifier.heightIn(min = 56.dp), shape = RoundedCornerShape(50))
                        }
                    }
                    if (!compact) Text(if (connected) "친구 상태 연결됨" else "마지막으로 받은 상태",
                        style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (tab !in listOf("광장", "이야기", "여행")) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        OutlinedButton(onClick = { tab = "광장" }, modifier = Modifier.heightIn(min = 64.dp)) { Text("‹ 광장으로") }
                        Text(tab, style = MaterialTheme.typography.titleLarge)
                    }
                }
                if (tab == "광장") {
                    BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                        val availableHeight = maxHeight
                        Column(Modifier.verticalScroll(rememberScrollState())) {
                        // Keep the scene usable in short windows; scroll instead of squeezing touch targets.
                        PlazaScene(game, connected, sceneHeightOverride = availableHeight, selectedResidents = visibleFriends) {
                            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.SpaceEvenly) {
                                listOf("친구들" to "친구들", "모은 재료" to "재료", "거점" to "거점").forEach { (label, destination) ->
                                    TextButton(onClick = { if (destination == "재료") materialsOpen = true else tab = destination }, modifier = Modifier.heightIn(min = 64.dp)) {
                                        Text(label, style = MaterialTheme.typography.titleSmall)
                                    }
                                }
                            }
                        }
                        }
                    }
                } else key(tab) {
                    BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                    val pageHeight = maxHeight
                    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        when (tab) {
                            "친구들" -> PlazaFriends(availableFriends, visibleFriends, catalog, connected,
                                onToggle = { id ->
                                    val next = PlazaPopulation.toggle(availableFriends, chosenFriends, id)
                                    chosenFriends = ArrayList(next)
                                    plazaPreferences.edit().putString("species_ids", next.joinToString(",")).apply()
                                },
                                onDone = { tab = "광장" })
                            "이야기" -> CompanionDialoguePanel(game, connected, dialogueBank, summary.title, unreviewedDialoguePreview, pageHeight)
                            "거점" -> {
                                ParkedSectionTitle("우리 거점", "건설·요리·훈련 조작은 폰에서 진행해 주세요.")
                                MaterialInventory(game)
                                val lines = FeatureStatus.from(game, catalog).baseLines
                                if (lines.isEmpty()) ParkedInfoCard("거점 연결 대기", "폰에서 거점 활동을 확인해 주세요.")
                                else ParkedCardGrid(lines) { line ->
                                    val pieces = line.split(" · ", limit = 2)
                                    ParkedInfoCard(pieces.first(), pieces.getOrElse(1) { "폰에 저장된 상태" })
                                }
                            }
                            "여행" -> TravelNotebook(game, connected, pageHeight) {
                                if (travelContent != null) travelContent() else ParkedInfoCard("여행 부탁 대기", "폰에서 여행 부탁을 보내 주세요.")
                            }
                            "폰 공유" -> {
                                ParkedSectionTitle("폰 화면 함께 보기", "주차 중에 폰에서 화면 공유를 시작해 주세요.")
                                if (onShare != null) ScreenAction("폰 화면 공유", onShare, enabled = connected)
                                else Text("이 버전에서는 화면 공유를 지원하지 않아요.")
                                if (hasCarPet) {
                                    onCallCompanion?.let { ScreenAction("폰으로 친구 부르기", it, enabled = connected, secondary = true) }
                                    onRetryTransfer?.let { ScreenAction("이동 상태 다시 확인", it, enabled = connected, secondary = true) }
                                }
                                transferMessage?.let { Text(it, style = MaterialTheme.typography.bodyLarge) }
                            }
                        }
                    }
                }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = { tab = "폰 공유" }) { Text("폰 연결 · 공유") }
                }
            }
        }
    }
    if (materialsOpen) AlertDialog(onDismissRequest = { materialsOpen = false },
        title = { Text("모은 재료") }, text = { Column(Modifier.verticalScroll(rememberScrollState())) { MaterialInventory(game) } },
        confirmButton = { TextButton(onClick = { materialsOpen = false }) { Text("닫기") } })

}
