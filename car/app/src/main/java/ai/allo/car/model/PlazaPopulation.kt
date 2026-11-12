package ai.allo.car.model

/** Species-level display only: the phone does not publish individual collection records. */
object PlazaPopulation {
    const val LIMIT = 6
    fun residents(game: GameState): List<String> {
        if (!game.hasV2Contract || "collectionSummary" in game.invalidBlocks) return emptyList()
        val ids = game.collectionSummary?.speciesIds?.distinct() ?: return emptyList()
        val companion = game.companion.takeUnless { "companion" in game.invalidBlocks }
            ?.takeIf { it.location == "car" }?.speciesId
        return if (companion in ids) listOf(companion!!) + ids.filter { it != companion } else ids
    }
    fun page(ids: List<String>, page: Int): List<String> =
        ids.distinct().chunked(LIMIT).let { pages -> pages.getOrNull(page.coerceAtLeast(0)) ?: pages.firstOrNull().orEmpty() }
}
