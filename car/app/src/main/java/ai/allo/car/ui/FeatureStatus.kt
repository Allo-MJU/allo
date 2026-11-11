package ai.allo.car.ui

import ai.allo.car.model.GameState
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Display only facts supplied by the phone; no local affinity or activity simulation. */
internal data class FeatureStatus(val incubation: String?, val affinity: String?, val baseLines: List<String>) {
    companion object {
        fun from(game: GameState, catalog: SpeciesCatalog): FeatureStatus {
            if (!game.hasV2Contract) return FeatureStatus(null, null, emptyList())
            val progress = game.progress.takeIf { it.isFinite() }?.coerceIn(0.0,1.0) ?: 0.0
            val incubation = when(game.stage) {
                "incubating" -> "알 품기 진행 · ${(progress*100).toInt()}%"
                "failed" -> "이번 알 품기는 마무리됐어요. 다음 알과 다시 함께해요."
                "hatched" -> "알 품기 결과 · 부화 완료"
                else -> null
            }
            val affinity = game.affinity.takeUnless { "affinity" in game.invalidBlocks }?.let {
                "호감도 · ${it.score} / ${it.target} · ${if(it.ready) "준비 완료" else "함께 쌓는 중"}"
            }
            val base = game.baseSummary.takeUnless { "baseSummary" in game.invalidBlocks }
            val lines = if (base == null) emptyList() else buildList {
                fun role(label:String, id:String?) { if(id!=null) add("$label · ${catalog[id]?.name ?: "등록된 친구"}") }
                role("건축가", base.builderSpeciesId)
                role("요리사", base.cookSpeciesId)
                role("훈련사", base.trainerSpeciesId)
                if(base.structureIds.isNotEmpty()) add("시설 · ${base.structureIds.joinToString(", ")}")
                base.lastMealId?.let { add("최근 식사 · $it") }
                base.activeTaskKind?.let { add("진행 중 활동 · $it") }
                if(isEmpty()) add("아직 등록된 거점 활동이 없어요")
            }
            return FeatureStatus(incubation, affinity, lines)
        }
    }
}

@Composable internal fun FeatureStatusCards(game:GameState, catalog:SpeciesCatalog) {
    val status = FeatureStatus.from(game,catalog)
    if(status.incubation!=null || status.affinity!=null) Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement=Arrangement.spacedBy(8.dp)) {
            status.incubation?.let { Text(it) }
            status.affinity?.let { Text(it) }
            if(game.affinity?.ready==true && game.stage=="incubating" && status.affinity!=null)
                Text("준비 완료는 부화 결과가 아니에요. 폰의 결과를 기다려요.",style=MaterialTheme.typography.bodySmall)
        }
    }
    if(status.baseLines.isNotEmpty()) Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text("우리 거점", style=MaterialTheme.typography.titleMedium)
            status.baseLines.forEach { Text(it) }
        }
    }
    if(game.invalidBlocks.isNotEmpty()) Text("일부 상태를 읽지 못했어요. 폰의 다음 업데이트를 기다려요.",style=MaterialTheme.typography.bodySmall)
}
