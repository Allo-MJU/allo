package ai.allo.car.ui

import ai.allo.car.model.PlazaPopulation
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp

/** Local presentation choices only; never changes the phone's companion or collection. */
@Composable
internal fun PlazaFriends(available: List<String>, selected: List<String>, catalog: SpeciesCatalog,
    connected: Boolean, onToggle: (String) -> Unit, onDone: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
        ParkedSectionTitle("광장에서 만날 친구", "광장에 나올 친구를 최대 6마리 골라 주세요. 차량 동행은 바뀌지 않아요.")
        Text("${selected.size} / ${PlazaPopulation.LIMIT}마리 선택" +
            if (selected.size == PlazaPopulation.LIMIT) " · 다른 친구를 고르려면 체크를 먼저 해제해 주세요." else "",
            style = MaterialTheme.typography.bodyLarge)
        if (available.isEmpty()) ParkedInfoCard("친구 정보 대기", "폰에서 수집한 친구 정보를 확인해 주세요.")
        ParkedCardGrid(available) { id ->
            val species = catalog[id]!!
            val checked = id in selected
            val enabled = checked || selected.size < PlazaPopulation.LIMIT
            Surface(Modifier.fillMaxWidth().toggleable(value = checked, enabled = enabled, role = Role.Checkbox,
                onValueChange = { onToggle(id) }), shape = RoundedCornerShape(24.dp),
                color = if (checked) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerLow) {
                Column(Modifier.fillMaxWidth().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    PlazaPetArt(PetSummary(species.name, "광장 친구", species, false, 0f), 120.dp, Modifier, connected, false)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = checked, onCheckedChange = null, enabled = enabled)
                        Text(species.name, style = MaterialTheme.typography.titleMedium)
                    }
                    Text(if (checked) "광장에서 함께 놀아요" else if (!enabled) "선택한 친구를 먼저 해제해 주세요" else "눌러서 광장에 초대해요",
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        ScreenAction("선택 완료 · 광장으로", onDone)
    }
}
