package ai.allo.car.model

import ai.allo.car.dialogue.DialogueBank
import kotlin.test.*

class PlazaPopulationTest {
    private fun game(ids: List<String>) = GameState(contractVersion = 2, gameRevision = 1,
        collectionSummary = CollectionSummary(wood = 0, stone = 0, ingredient = 0, speciesIds = ids))
    @Test fun `pages never exceed six and cover every owned species without duplication`() {
        for (count in 0..12) {
            val ids = List(count) { "species-$it" }
            val pages = (0 until (count + 5) / 6).map { PlazaPopulation.page(ids, it) }
            assertTrue(pages.all { it.size <= 6 })
            assertEquals(ids, pages.flatten())
        }
    }
    @Test fun `selected car companion is first but never invented as collected`() {
        val input = game(listOf("a", "b", "c", "a"))
        val companion = CompanionDisplay("selected", 2, "c", "car")
        assertEquals(listOf("c", "a", "b"), PlazaPopulation.residents(input.copy(companion = companion)))
        assertEquals(listOf("a", "b", "c"), PlazaPopulation.residents(input.copy(companion = companion.copy(speciesId = "unknown"))))
        assertEquals(listOf("a", "b", "c"), PlazaPopulation.residents(input.copy(companion = companion, invalidBlocks = setOf("companion"))))
    }
    @Test fun `phone village choice preserves selected order and explicit empty over companion priority`() {
        val base = game(listOf("a", "b", "c"))
        val chosen = base.copy(collectionSummary = base.collectionSummary!!.copy(villageSpeciesIds = listOf("b", "a")),
            companion = CompanionDisplay("selected", 1, "a", "car"))
        assertEquals(listOf("b", "a"), PlazaPopulation.residents(chosen))
        assertEquals(emptyList(), PlazaPopulation.residents(chosen.copy(
            collectionSummary = chosen.collectionSummary!!.copy(villageSpeciesIds = emptyList()))))
    }
    @Test fun `missing invalid or legacy collections never invent a populated plaza`() {
        val input = game(listOf("a"))
        assertEquals(emptyList(), PlazaPopulation.residents(input.copy(collectionSummary = null)))
        assertEquals(emptyList(), PlazaPopulation.residents(input.copy(invalidBlocks = setOf("collectionSummary"))))
        assertEquals(emptyList(), PlazaPopulation.residents(input.copy(contractVersion = null)))
    }
    @Test fun `page resets safely when collection shrinks`() {
        assertEquals(listOf("a"), PlazaPopulation.page(listOf("a"), 9))
        assertEquals(emptyList(), PlazaPopulation.page(emptyList(), 2))
    }
    @Test fun `species lines alternate without bypassing the dialogue review policy`() {
        val json = """{"entries":[{"key":"ask_like|road_sprout|hatched","reviewedBy":null,"lines":["신기해!","새로운 길이 좋아."]}]}"""
        val release = DialogueBank.parse(json, null, false)
        assertNull(release.line("ask_like", "road_sprout", null, "hatched"))
        val debug = DialogueBank.parse(json, null, true)
        val first = debug.line("ask_like", "road_sprout", null, "hatched")
        val second = debug.line("ask_like", "road_sprout", null, "hatched")
        assertNotEquals(first, second)
        assertEquals(first, debug.line("ask_like", "road_sprout", null, "hatched"))
    }
}
