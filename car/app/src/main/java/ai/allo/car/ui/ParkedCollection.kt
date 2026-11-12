package ai.allo.car.ui

import ai.allo.car.model.GameState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp

@Composable
internal fun ParkedSectionTitle(title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.headlineMedium)
        Text(subtitle, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun ParkedInfoCard(title: String, value: String) {
    Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Column(Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleLarge)
        }
    }
}

/** Eager rows share the parent scroll: no nested lazy grids or fixed text heights. */
@Composable
internal fun <T> ParkedCardGrid(items: List<T>, maxColumns: Int = 3, content: @Composable (T) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val columns = (maxWidth.value / (240f * LocalDensity.current.fontScale.coerceAtLeast(1f))).toInt().coerceIn(1, maxColumns)
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            items.chunked(columns).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    row.forEach { item -> Box(Modifier.weight(1f)) { content(item) } }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
internal fun MaterialInventory(game: GameState) {
    val collection = game.collectionSummary.takeIf { game.hasV2Contract && "collectionSummary" !in game.invalidBlocks }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("모은 재료", style = MaterialTheme.typography.titleLarge)
        Text("폰에 저장된 보유량 · 주행·활동으로 모은 재료", style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (collection == null) {
            ParkedInfoCard("재료 정보", if ("collectionSummary" in game.invalidBlocks) "재료 정보를 다시 확인하고 있어요." else "폰의 재료 정보 대기 중")
        } else ParkedCardGrid(listOf("목재" to collection.wood, "돌" to collection.stone, "식재료" to collection.ingredient)) { (name, count) ->
            ParkedInfoCard(name, "${count}개")
        }
    }
}

@Composable
internal fun CollectionDex(game: GameState, catalog: SpeciesCatalog) {
    val collection = game.collectionSummary.takeIf { game.hasV2Contract && "collectionSummary" !in game.invalidBlocks }
    Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
        ParkedSectionTitle("우리 도감", "폰에 저장된 수집 친구 · 함께한 여행의 기록")
        if (collection == null) {
            ParkedInfoCard("도감 정보", if ("collectionSummary" in game.invalidBlocks) "도감 정보를 다시 확인하고 있어요." else "폰의 도감 정보 대기 중")
        } else if (collection.speciesIds.isEmpty()) {
            ParkedInfoCard("첫 만남을 기다려요", "아직 수집한 친구가 없어요.")
        } else {
            Text("수집한 친구 ${collection.speciesIds.size}종", style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.primary)
            ParkedCardGrid(collection.speciesIds) { id ->
                val species = catalog[id]
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                    Column(Modifier.fillMaxWidth().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (species != null) {
                            PetArt(PetSummary(species.name, "수집한 친구", species, false, 0f), 120.dp, connected = false)
                        } else AlloWordmark(Modifier.width(120.dp).height(120.dp))
                        Text(species?.name ?: "이름 확인 중인 친구", style = MaterialTheme.typography.titleLarge)
                        if (species != null) Text(when (species.attribute) { "water" -> "물 속성"; "dark" -> "어둠 속성"; else -> "일반 속성" },
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}
