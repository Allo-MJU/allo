package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** A single conversation guest; does not write companion or plaza display settings. */
@Composable
internal fun StoryFriendPicker(
    available: List<String>, selected: String?, catalog: SpeciesCatalog, connected: Boolean,
    onSelect: (String?) -> Unit, onDismiss: () -> Unit,
) {
    AlertDialog(onDismissRequest = onDismiss,
        title = { Text("이야기할 친구 부르기") },
        text = {
            Column(Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("수집한 친구와 이야기해요. 광장 표시와 차량 동행은 바뀌지 않아요.",
                    style = MaterialTheme.typography.bodyMedium)
                ToyButton("차량 동행과 이야기", { onSelect(null) }, Modifier.fillMaxWidth())
                if (available.isEmpty()) Text("폰에서 수집한 친구 정보를 기다리고 있어요.")
                available.forEach { id ->
                    val species = catalog[id] ?: return@forEach
                    Surface(onClick = { onSelect(id) }, enabled = connected, selected = selected == id,
                        color = if (selected == id) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerLow,
                        modifier = Modifier.fillMaxWidth()) {
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            PlazaPetArt(PetSummary(species.name, "이야기 친구", species, false, 0f), 64.dp, Modifier, connected, false)
                            Text(species.name, Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
                            RadioButton(selected = selected == id, onClick = null)
                        }
                    }
                }
            }
        },
        confirmButton = { ToyButton("닫기", onDismiss) })
}
