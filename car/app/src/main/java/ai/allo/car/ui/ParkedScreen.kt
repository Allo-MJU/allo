package ai.allo.car.ui

import ai.allo.car.dialogue.DialogueBank
import ai.allo.car.model.GameState
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp

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
    val emptyCompanion = game.hasV2Contract && companionValid &&
        (game.companion == null || game.companion?.location == "phone")
    val hasCarPet = if (game.hasV2Contract) companionValid && game.companion?.location == "car"
        else summary.showArt && !summary.showEgg
    var tab by rememberSaveable(game.companion?.displayId, game.companion?.displayRevision, game.companion?.location, connected) { mutableStateOf("홈") }
    val tabs = listOf("홈", "도감", "이야기", "거점", "여행", "폰 공유")
    ScreenFrame("함께 쉬어가는 시간", if (connected) "폰 상태 연결됨" else "마지막으로 받은 상태", modifier) {
        BoxWithConstraints(Modifier.fillMaxWidth().weight(1f)) {
            val rail = maxWidth >= 880.dp && LocalDensity.current.fontScale <= 1.4f
            val menu: @Composable (String) -> Unit = { name ->
                val selected = tab == name
                Surface(onClick = { tab = name }, selected = selected,
                    shape = RoundedCornerShape(18.dp),
                    color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
                    contentColor = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = (if (rail) Modifier.fillMaxWidth() else Modifier.widthIn(min = 100.dp)).heightIn(min = 64.dp)) {
                    Box(Modifier.padding(horizontal = 20.dp, vertical = 16.dp), contentAlignment = Alignment.CenterStart) {
                        Text(name, style = MaterialTheme.typography.titleMedium)
                    }
                }
            }
            val content: @Composable (Modifier) -> Unit = { paneModifier ->
                key(tab) {
                    Column(paneModifier.verticalScroll(rememberScrollState()).padding(4.dp),
                        verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        when (tab) {
                            "홈" -> {
                                ParkedHero(summary, connected, false,
                                    if (emptyCompanion) "함께할 친구를 골라 주세요" else summary.title,
                                    when {
                                        !companionValid -> "친구 상태를 다시 확인하고 있어요."
                                        emptyCompanion -> "폰의 보유 친구 목록에서 차량과 함께할 친구를 선택해 주세요."
                                        summary.showEgg -> summary.status
                                        else -> "폰에서 선택한 친구가 함께해요."
                                    })
                                MaterialInventory(game)
                                ParkedCardGrid(listOf("도감 확인", "친구와 이야기", "거점 확인")) { label ->
                                    ScreenAction(label, { tab = when (label) { "도감 확인" -> "도감"; "친구와 이야기" -> "이야기"; else -> "거점" } }, secondary = true)
                                }
                                if (hasCarPet) {
                                    onCallCompanion?.let { ScreenAction("폰으로 친구 부르기", it, enabled = connected, secondary = true) }
                                    onRetryTransfer?.let { ScreenAction("이동 상태 다시 확인", it, enabled = connected, secondary = true) }
                                }
                                transferMessage?.let { Text(it, style = MaterialTheme.typography.bodyLarge) }
                                Text("친구 변경은 폰의 보유 친구 목록에서", style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            "도감" -> CollectionDex(game, catalog)
                            "이야기" -> {
                                CompanionDialoguePanel(game, connected, dialogueBank, summary.title, unreviewedDialoguePreview)
                            }
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
                            "여행" -> {
                                ParkedSectionTitle("함께 떠날 곳", "다음 여행의 목적지를 함께 골라요.")
                                if (travelContent != null) travelContent() else ParkedInfoCard("여행 부탁 대기", "폰에서 여행 부탁을 보내 주세요.")
                            }
                            "폰 공유" -> {
                                ParkedSectionTitle("폰 화면 함께 보기", "주차 중에 폰에서 화면 공유를 시작해 주세요.")
                                ParkedInfoCard("큰 화면으로 함께", "연결된 폰의 화면을 차량에서 확인할 수 있어요.")
                                if (onShare != null) ScreenAction("폰 화면 공유", onShare, enabled = connected)
                                else Text("이 버전에서는 화면 공유를 지원하지 않아요.")
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                    }
                }
            }
            if (rail) Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Column(Modifier.width(152.dp).fillMaxHeight().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("둘러보기", Modifier.padding(16.dp), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    tabs.forEach { menu(it) }
                }
                content(Modifier.weight(1f).fillMaxHeight())
            } else Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) { tabs.forEach { menu(it) } }
                content(Modifier.fillMaxWidth().weight(1f))
            }
        }
    }
}

@Composable
private fun ParkedHero(summary: PetSummary, connected: Boolean, talking: Boolean, title: String, subtitle: String) {
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(28.dp)) {
        BoxWithConstraints(Modifier.fillMaxWidth().padding(24.dp)) {
            val horizontal = maxWidth >= 500.dp && LocalDensity.current.fontScale < 1.6f
            val art: @Composable () -> Unit = {
                if (summary.showArt) PetArt(summary, if (talking) 112.dp else if (horizontal) 220.dp else 160.dp,
                    pose = if (talking) PetPose.Idle else PetPose.Sleep, parked = true, connected = connected)
                else AlloWordmark(Modifier.width(140.dp).height(80.dp))
            }
            val words: @Composable () -> Unit = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(if (talking) "오늘의 이야기 친구" else "나의 동행", style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSecondaryContainer)
                    Text(title, style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.onSecondaryContainer)
                    Text(subtitle, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSecondaryContainer)
                }
            }
            if (horizontal) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                art(); Box(Modifier.weight(1f)) { words() }
            } else Column(verticalArrangement = Arrangement.spacedBy(16.dp)) { art(); words() }
        }
    }
}
