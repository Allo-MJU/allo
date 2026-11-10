package ai.allo.car.ui

import ai.allo.car.model.GameState

/** Small, factual driving display. No mood/hunger inference or gameplay controls. */
data class PetSummary(
    val title: String, val status: String, val species: PetSpecies?,
    val showEgg: Boolean, val eggFill: Float,
) {
    companion object {
        fun from(game: GameState, connected: Boolean, catalog: SpeciesCatalog): PetSummary {
            val hatched = game.stage == "hatched"
            val species = if (hatched) catalog[game.speciesId] else null
            val progress = game.progress.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 0.0
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
