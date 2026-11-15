package ai.allo.car.ui

import ai.allo.car.dialogue.DialogueBank
import ai.allo.car.model.CompanionDialogue
import ai.allo.car.model.DialogueAnswer
import ai.allo.car.model.GameState
import ai.allo.car.model.PlazaPopulation
import androidx.compose.runtime.saveable.rememberSaveable
import ai.allo.car.voice.DialogueVoiceState
import ai.allo.car.voice.characterDialogueVoice
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.LineBreak
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
    minHeight: androidx.compose.ui.unit.Dp = 0.dp,
) {
    val dialogue = remember(bank) { CompanionDialogue(bank) }
    val catalog = rememberSpeciesCatalog()
    var guestSpeciesId by rememberSaveable { mutableStateOf<String?>(null) }
    var pickerOpen by remember { mutableStateOf(false) }
    val available = PlazaPopulation.residents(game).filter { it in SuppliedCharacters.ids && catalog[it] != null }
    val subject = dialogue.subject(game, connected, guestSpeciesId)?.takeIf { catalog[it.speciesId] != null }
    val latestGuestSpeciesId by rememberUpdatedState(guestSpeciesId)
    val displayedSpecies = subject?.let { catalog[it.speciesId] }
    val displayedName = displayedSpecies?.name ?: companionName
    val latestGame by rememberUpdatedState(game)
    val latestConnected by rememberUpdatedState(connected)
    var answer by remember(subject?.key, connected) { mutableStateOf<DialogueAnswer?>(null) }
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val voice = remember(context, subject?.key) {
        subject?.let { characterDialogueVoice(context, it.speciesId) }
    }
    val voiceState = voice?.state?.collectAsState()?.value ?: DialogueVoiceState()
    DisposableEffect(voice, lifecycleOwner) {
        voice?.start()
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE) voice?.stop()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            voice?.release()
        }
    }
    LaunchedEffect(subject?.key, connected) { voice?.stop() }
    if (pickerOpen) StoryFriendPicker(available, guestSpeciesId, catalog, connected,
        onSelect = { id ->
            // Check current ownership again, including if the dialog was open during a sync.
            if (id == null || (latestConnected && dialogue.subject(latestGame, true, id) != null)) {
                voice?.stop()
                answer = null
                guestSpeciesId = id
                pickerOpen = false
            }
        }, onDismiss = { pickerOpen = false })
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        if (subject == null) {
            ToyButton("대화할 친구 바꾸기", { pickerOpen = true }, enabled = connected)
            ParkedInfoCard("대화 준비 중", if (!connected) "폰 연결을 확인해 주세요." else "대화할 친구 바꾸기에서 수집한 친구를 불러 주세요.")
        } else {
            NotebookSpread(minHeight = minHeight, scene = {
            Column(Modifier.fillMaxWidth().padding(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
                val bubbleColor = if (dark) Color(0xFFE8DFC5) else Color(0xFFFFFBE9)
                val ink = Color(0xFF304729)
                val accent = if (dark) Color(0xFF83996B) else Color(0xFFD8E4BB)
                Surface(onClick = {
                    if (dialogue.subject(latestGame, latestConnected, latestGuestSpeciesId)?.key == subject.key) {
                        answer?.let { voice?.speak(it.text) }
                    }
                }, enabled = answer != null && voiceState.ready,
                    modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth()
                        .padding(end = 8.dp, bottom = 8.dp)
                        .drawBehind {
                            val tail = 28.dp.toPx()
                            val h = size.height - tail
                            val r = 42.dp.toPx()
                            val w = size.width
                            val outline = Path().apply {
                                moveTo(r, 0f); lineTo(w - r, 0f)
                                quadraticBezierTo(w, 0f, w, r)
                                lineTo(w, h - r); quadraticBezierTo(w, h, w - r, h)
                                lineTo(w * 0.56f, h)
                                quadraticBezierTo(w * .52f, h + tail * .6f, w * .47f, size.height)
                                quadraticBezierTo(w * .49f, h + tail * .45f, w * .49f, h)
                                lineTo(r, h); quadraticBezierTo(0f, h, 0f, h - r)
                                lineTo(0f, r); quadraticBezierTo(0f, 0f, r, 0f); close()
                            }
                            translate(3.dp.toPx(), 3.dp.toPx()) { drawPath(outline, accent) }
                            drawPath(outline, bubbleColor)
                            drawPath(outline, ink, style = Stroke(1.5.dp.toPx()))

                        }
                        .semantics { contentDescription = if (voiceState.speaking) "답변 읽기 중지" else "답변 읽기" },
                    shape = RoundedCornerShape(42.dp), color = Color.Transparent) {
                    Column(Modifier.padding(start = 28.dp, top = 20.dp, end = 28.dp, bottom = 50.dp), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(displayedName, style = MaterialTheme.typography.labelSmall,
                            color = Color(0xFF657256), textAlign = TextAlign.Center)
                        Text(answer?.text ?: "어떤 이야기가 궁금해요? 질문을 골라 주세요.",
                            style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold, lineBreak = LineBreak.Heading),
                            color = ink, textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite })
                        if (answer != null) Text(
                            voiceState.error ?: when {
                                voiceState.speaking -> "읽는 중 · 말풍선을 누르면 멈춰요"
                                voiceState.ready -> "말풍선을 누르면 소리로 읽어줘요"
                                else -> "음성을 준비하고 있어요"
                            }, style = MaterialTheme.typography.labelSmall,
                            color = Color(0xFF657256), textAlign = TextAlign.Center)
                    }
                }
                BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    PlazaPetArt(PetSummary(displayedName, "이야기 친구", displayedSpecies, false, 0f),
                        size = (maxWidth * 0.9f).coerceIn(180.dp, 340.dp),
                        modifier = Modifier, connected = connected, moving = false)
                }
                ToyButton("대화할 친구 바꾸기", { pickerOpen = true }, enabled = connected)
            }
            }, page = {
            NotebookPaper("친구와 이야기", "오늘은 어떤 이야기를 나눌까요?") {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            CompanionDialogue.QUESTIONS.forEach { question ->
                val chosen = answer?.questionId == question.id
                ToyButton(question.label, onClick = {
                    // Revalidate the live subject; an old tap cannot answer for a replacement.
                    if (dialogue.subject(latestGame, latestConnected, latestGuestSpeciesId)?.key == subject.key) {
                        voice?.stop()
                        answer = dialogue.answer(question.id, latestGame, latestConnected, latestGuestSpeciesId)
                    }
                }, primary = chosen, modifier = Modifier.fillMaxWidth())
            }
            }
            Text(if (unreviewedPreview) "개발용 미리보기 · 검수 전 대사가 포함될 수 있어요."
                else "준비된 대사로 답해요. 답변이 없는 질문은 준비 중으로 안내해요.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            })
        }
    }
}
