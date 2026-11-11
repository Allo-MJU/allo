package ai.allo.car.ui

import ai.allo.car.model.GameState

/** Small, factual driving display. No mood/hunger inference or gameplay controls. */
data class PetSummary(
    val title: String, val status: String, val species: PetSpecies?,
    val showEgg: Boolean, val eggFill: Float, val showArt: Boolean = true,
) {
    companion object {
        fun from(game: GameState, connected: Boolean, catalog: SpeciesCatalog): PetSummary {
            val progress = game.progress.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 0.0
            if (game.hasV2Contract) {
                val companion = game.companion.takeUnless { "companion" in game.invalidBlocks }
                val species = companion?.let { catalog[it.speciesId] }
                val hasEgg = companion == null && game.stage == "incubating"
                val status = when {
                    !connected && game.ts > 0 -> "마지막으로 받은 상태"
                    !connected -> "폰 연결을 기다리고 있어요"
                    "companion" in game.invalidBlocks -> "친구 상태를 다시 확인하고 있어요"
                    companion?.location == "phone" -> "폰에서 함께하고 있어요"
                    companion?.location == "car" -> "함께 가는 중"
                    hasEgg -> "알을 품는 중 · ${(progress * 100).toInt()}%"
                    game.stage == "failed" -> "이번 알 품기는 마무리됐어요"
                    else -> "아직 부를 친구가 없어요"
                }
                return PetSummary(
                    species?.name ?: if (hasEgg) "알로의 알" else "함께하는 친구",
                    status, species, hasEgg, progress.toFloat(),
                    hasEgg || companion?.location == "car",
                )
            }
            val hatched = game.stage == "hatched"
            val species = if (hatched) catalog[game.speciesId] else null
            val title = if (hatched) species?.name ?: "함께하는 친구" else "알로의 알"
            val status = when {
                !connected && game.ts > 0 -> "마지막으로 받은 상태"
                !connected -> "폰 연결을 기다리고 있어요"
                hatched -> "함께 가는 중"
                game.stage == "incubating" -> "알을 품는 중 · ${(progress * 100).toInt()}%"
                else -> "폰에서 시작을 기다려요"
            }
            return PetSummary(title, status, species, !hatched, progress.toFloat())
        }
    }
}
