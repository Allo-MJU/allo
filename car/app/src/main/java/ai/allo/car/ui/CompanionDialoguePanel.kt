package ai.allo.car.ui

import ai.allo.car.dialogue.DialogueBank
import ai.allo.car.model.CompanionDialogue
import ai.allo.car.model.DialogueAnswer
import ai.allo.car.model.GameState
import ai.allo.car.voice.DialogueVoice
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** One local question/answer, discarded on subject change or leaving the parked tab. */
@Composable
fun CompanionDialoguePanel(
    game: GameState,
    connected: Boolean,
    bank: DialogueBank,
    companionName: String,
    unreviewedPreview: Boolean = false,
) {
    val dialogue = remember(bank) { CompanionDialogue(bank) }
    val catalog = rememberSpeciesCatalog()
    val subject = dialogue.subject(game, connected)?.takeIf { catalog[it.speciesId] != null }
    val latestGame by rememberUpdatedState(game)
    val latestConnected by rememberUpdatedState(connected)
    var answer by remember(subject?.key, connected) { mutableStateOf<DialogueAnswer?>(null) }
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val voice = remember(context) { DialogueVoice(context) }
    val voiceState by voice.state.collectAsState()
    DisposableEffect(voice, lifecycleOwner) {
        voice.start()
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE) voice.stop()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            voice.release()
        }
    }
    LaunchedEffect(subject?.key, connected) { voice.stop() }
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        ParkedSectionTitle("친구와 이야기", "궁금한 질문을 골라 보세요.")
        if (subject == null) {
            ParkedInfoCard("대화 준비 중", if (!connected) "폰 연결을 확인해 주세요." else "폰에서 차량과 함께할 친구를 선택해 주세요.")
        } else {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
                val bubbleColor = if (dark) Color(0xFFFAE6AE) else Color(0xFFFFF9E9)
                val ink = Color(0xFF163C30)
                val accent = if (dark) Color(0xFF72C6A0) else Color(0xFFFFD34F)
                Surface(onClick = {
                    if (dialogue.subject(latestGame, latestConnected)?.key == subject.key) {
                        answer?.let { voice.speak(it.text) }
                    }
                }, enabled = answer != null && voiceState.ready,
                    modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth()
                        .padding(end = 8.dp, bottom = 8.dp)
                        .drawBehind {
                            val tail = 28.dp.toPx()
                            val h = size.height - tail
                            val r = 24.dp.toPx()
                            val w = size.width
                            val outline = Path().apply {
                                moveTo(r, 0f); lineTo(w - r, 0f)
                                quadraticBezierTo(w, 0f, w, r)
                                lineTo(w, h - r); quadraticBezierTo(w, h, w - r, h)
                                lineTo(w * 0.56f, h)
                                lineTo(w * 0.47f, size.height)
                                lineTo(w * 0.49f, h)
                                lineTo(r, h); quadraticBezierTo(0f, h, 0f, h - r)
                                lineTo(0f, r); quadraticBezierTo(0f, 0f, r, 0f); close()
                            }
                            translate(7.dp.toPx(), 7.dp.toPx()) { drawPath(outline, accent) }
                            drawPath(outline, bubbleColor)
                            drawPath(outline, ink, style = Stroke(3.dp.toPx()))
                            // Small halftone corner, kept clear of the dialogue text.
                            for (row in 0..2) for (col in 0..4) {
                                drawCircle(ink.copy(alpha = 0.22f), 1.5.dp.toPx(),
                                    Offset(w - 22.dp.toPx() - col * 9.dp.toPx(),
                                        19.dp.toPx() + row * 9.dp.toPx()))
                            }
                        }
                        .semantics { contentDescription = if (voiceState.speaking) "답변 읽기 중지" else "답변 읽기" },
                    shape = RoundedCornerShape(24.dp), color = Color.Transparent) {
                    Column(Modifier.padding(start = 24.dp, top = 20.dp, end = 24.dp, bottom = 50.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(companionName, style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.ExtraBold, color = ink,
                            modifier = Modifier.padding(end = 54.dp)
                                .background(accent, RoundedCornerShape(8.dp))
                                .border(BorderStroke(2.dp, ink), RoundedCornerShape(8.dp))
                                .padding(horizontal = 12.dp, vertical = 4.dp))
                        Text(answer?.text ?: "어떤 이야기가 궁금해요? 아래 질문을 골라 주세요.",
                            style = MaterialTheme.typography.headlineSmall,
                            color = ink,
                            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                        if (answer != null) Text(
                            voiceState.error ?: when {
                                voiceState.speaking -> "읽는 중 · 말풍선을 누르면 멈춰요"
                                voiceState.ready -> "말풍선을 누르면 소리로 읽어줘요"
                                else -> "음성을 준비하고 있어요"
                            }, style = MaterialTheme.typography.bodyMedium,
                            color = ink)
                    }
                }
                BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    PetArt(PetSummary.from(game, connected, catalog),
                        size = (maxWidth * 0.75f).coerceIn(180.dp, 340.dp),
                        parked = true, connected = connected)
                }
            }
            ParkedCardGrid(CompanionDialogue.QUESTIONS, maxColumns = 2) { question ->
                val chosen = answer?.questionId == question.id
                Surface(onClick = {
                    // Revalidate the live subject; an old tap cannot answer for a replacement.
                    if (dialogue.subject(latestGame, latestConnected)?.key == subject.key) {
                        voice.stop()
                        answer = dialogue.answer(question.id, latestGame, latestConnected)
                    }
                }, selected = chosen, modifier = Modifier.fillMaxWidth().heightIn(min = 88.dp),
                    shape = androidx.compose.foundation.shape.RoundedCornerShape(22.dp),
                    color = if (chosen) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerLow,
                    contentColor = if (chosen) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurface) {
                    Box(Modifier.padding(22.dp), contentAlignment = androidx.compose.ui.Alignment.CenterStart) {
                        Text(question.label, style = MaterialTheme.typography.titleLarge)
                    }
                }
            }
            Text(if (unreviewedPreview) "개발용 미리보기 · 검수 전 대사가 포함될 수 있어요."
                else "준비된 대사로 답해요. 답변이 없는 질문은 준비 중으로 안내해요.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
