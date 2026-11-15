package ai.allo.car.ui

import ai.allo.car.model.*
import java.io.File
import kotlin.test.*

class PlazaResidentsTest {
    @Test fun `selected tide keeper remains visible with supplied and other collected species`() {
        val catalog = SpeciesCatalog.parse(File("../../data/species.json").readText())
            .withDisplayOverrides(SpeciesCatalog.parse(File("../../data/characters.json").readText()))
        val game = GameState(contractVersion = 2, gameRevision = 1,
            collectionSummary = CollectionSummary(wood = 0, stone = 0, ingredient = 0,
                speciesIds = listOf("road_sprout", "tide_keeper", "bridge_hopper", "unknown")),
            companion = CompanionDisplay("selected", 1, "tide_keeper", "car"))
        assertEquals(listOf("tide_keeper", "road_sprout", "bridge_hopper"), catalog.plazaResidents(game))
        assertEquals(listOf("tide_keeper"), catalog.plazaResidents(game.copy(
            collectionSummary = game.collectionSummary!!.copy(villageSpeciesIds = listOf("tide_keeper")))))
        assertEquals(emptyList(), catalog.plazaResidents(game.copy(invalidBlocks = setOf("collectionSummary"))))
        assertEquals(emptyList(), catalog.plazaResidents(game.copy(collectionSummary = null)))
    }
}
