package ai.allo.car.ui

import ai.allo.car.dialogue.DialogueBank
import ai.allo.car.model.GameState
import ai.allo.car.model.PlazaPopulation
import androidx.activity.compose.BackHandler
import androidx.compose.ui.platform.LocalContext
import android.content.Context
import androidx.compose.foundation.selection.selectableGroup
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
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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
    val availableFriends = catalog.plazaResidents(game)
    val phoneSelection = game.collectionSummary?.villageSpeciesIds != null && "collectionSummary" !in game.invalidBlocks
    val visibleFriends = PlazaPopulation.selected(availableFriends, if (phoneSelection) null else chosenFriends)
    BackHandler(enabled = tab != "광장") { tab = "광장" }
    var materialsOpen by remember { mutableStateOf(false) }
    val dark = MaterialTheme.colorScheme.surface.luminance() < .35f
    val paper = if (dark) MaterialTheme.colorScheme.surface else Color(0xFFFAF7EE)
    Surface(modifier.fillMaxSize(), color = paper) {
        // The scene owns the whole window; logo, navigation and actions sit on top of it.
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val compact = maxWidth < 700.dp
            val windowHeight = maxHeight
            val edge = if (compact) 12.dp else 20.dp
            val safe = WindowInsets.safeDrawing.asPaddingValues()
            val onPlaza = tab == "광장"
            if (onPlaza) {
                // Keep the scene usable in short windows; scroll instead of squeezing touch targets.
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    PlazaScene(game, connected, sceneHeightOverride = windowHeight, selectedResidents = visibleFriends,
                        topInset = safe.calculateTopPadding() + edge + 72.dp, bottomInset = safe.calculateBottomPadding()) {
                        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally)) {
                            listOf("친구들" to "친구들", "모은 재료" to "재료", "거점" to "거점", "폰 연결 · 공유" to "폰 공유").forEach { (label, destination) ->
                                ToyButton(label, { if (destination == "재료") materialsOpen = true else tab = destination }, Modifier.widthIn(min = 144.dp))
                            }
                        }
                    }
                }
            } else GardenBackdrop(Modifier.fillMaxSize(), paper = tab !in listOf("이야기", "여행"))
            Column((if (onPlaza) Modifier.fillMaxWidth() else Modifier.fillMaxSize()).safeDrawingPadding().padding(edge), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    AlloWordmark(Modifier.width(if (compact) 88.dp else 132.dp).height(64.dp))
                    Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()).selectableGroup(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("광장", "이야기", "여행").forEach { name ->
                            ToyNavigationButton(label = name, selected = tab == name,
                                dark = dark, onClick = { tab = name })
                        }
                    }
                    // Connected is the quiet default: a small light. Words appear only when it is lost.
                    if (connected) Box(Modifier.padding(end = 8.dp).size(18.dp).border(3.dp, Color.White.copy(alpha = .9f), CircleShape)
                        .padding(3.dp).background(Color(0xFF58B46A), CircleShape).semantics { contentDescription = "친구 상태 연결됨" })
                    else Surface(color = MaterialTheme.colorScheme.errorContainer, contentColor = MaterialTheme.colorScheme.onErrorContainer,
                        shape = RoundedCornerShape(20.dp)) {
                        Text(if (compact) "연결 끊김" else "마지막으로 받은 상태", Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                            style = MaterialTheme.typography.labelMedium)
                    }
                }
                if (tab !in listOf("광장", "이야기", "여행")) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        ToyButton("‹ 광장으로", { tab = "광장" })
                        Text(tab, style = MaterialTheme.typography.titleLarge)
                    }
                }
                if (!onPlaza) key(tab) {
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
                                onDone = { tab = "광장" }, phoneSelection = phoneSelection)
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
                        // Room to scroll the last lines clear of the floating button.
                        Spacer(Modifier.height(72.dp))
                    }
                }
                }
            }
            // Floats over the page so the content runs to the bottom edge instead of stopping above a bar.
            if (!onPlaza && tab != "폰 공유") ToyButton("폰 연결 · 공유", { tab = "폰 공유" },
                Modifier.align(Alignment.BottomEnd).safeDrawingPadding().padding(edge))
        }
    }
    if (materialsOpen) AlertDialog(onDismissRequest = { materialsOpen = false },
        title = { Text("모은 재료") }, text = { Column(Modifier.verticalScroll(rememberScrollState())) { MaterialInventory(game) } },
        confirmButton = { ToyButton("닫기", { materialsOpen = false }) })

}
