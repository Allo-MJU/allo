package ai.allo.car.model

/** Species-level display only: the phone does not publish individual collection records. */
object PlazaPopulation {
    const val LIMIT = 6
    fun residents(game: GameState): List<String> {
        if (!game.hasV2Contract || "collectionSummary" in game.invalidBlocks) return emptyList()
        val ids = game.collectionSummary?.speciesIds?.distinct() ?: return emptyList()
        // A phone choice is authoritative, including an explicitly empty choice.
        game.collectionSummary?.villageSpeciesIds?.let { chosen ->
            return chosen.distinct().filter { it in ids }.take(4)
        }
        val companion = game.companion.takeUnless { "companion" in game.invalidBlocks }
            ?.takeIf { it.location == "car" }?.speciesId
        return if (companion in ids) listOf(companion!!) + ids.filter { it != companion } else ids
    }
    /** Null means initial defaults; an explicit empty selection stays empty. */
    fun selected(available: List<String>, chosen: List<String>?): List<String> =
        (chosen ?: available).distinct().filter { it in available }.take(LIMIT)

    fun toggle(available: List<String>, chosen: List<String>?, id: String): List<String> {
        val current = selected(available, chosen)
        return when {
            id in current -> current - id
            id !in available || current.size >= LIMIT -> current
            else -> current + id
        }
    }

    fun page(ids: List<String>, page: Int): List<String> =
        ids.distinct().chunked(LIMIT).let { pages -> pages.getOrNull(page.coerceAtLeast(0)) ?: pages.firstOrNull().orEmpty() }
}
