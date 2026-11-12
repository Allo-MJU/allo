package ai.allo.car.ui

import ai.allo.car.dialogue.DialogueBank
import ai.allo.car.model.CompanionDialogue
import ai.allo.car.model.DialogueAnswer
import ai.allo.car.model.GameState
import androidx.compose.foundation.layout.*
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
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        ParkedSectionTitle("친구와 이야기", "궁금한 질문을 골라 보세요.")
        if (subject == null) {
            ParkedInfoCard("대화 준비 중", if (!connected) "폰 연결을 확인해 주세요." else "폰에서 차량과 함께할 친구를 선택해 주세요.")
        } else {
            Surface(Modifier.fillMaxWidth(), shape = androidx.compose.foundation.shape.RoundedCornerShape(26.dp),
                color = MaterialTheme.colorScheme.primaryContainer) {
                Column(Modifier.padding(26.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text(companionName, style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onPrimaryContainer)
                    answer?.let { reply ->
                        Text(CompanionDialogue.QUESTIONS.first { it.id == reply.questionId }.label,
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
                    }
                    Text(answer?.text ?: "어떤 이야기가 궁금해요?",
                        style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                }
            }
            ParkedCardGrid(CompanionDialogue.QUESTIONS, maxColumns = 2) { question ->
                val chosen = answer?.questionId == question.id
                Surface(onClick = {
                    // Revalidate the live subject; an old tap cannot answer for a replacement.
                    if (dialogue.subject(latestGame, latestConnected)?.key == subject.key) {
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
