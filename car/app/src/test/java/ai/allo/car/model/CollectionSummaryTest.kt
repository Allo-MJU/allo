package ai.allo.car.model

import kotlinx.serialization.json.*
import kotlin.test.*

class CollectionSummaryTest {
    private fun raw(block: String = """{"version":1,"wood":12,"stone":8,"ingredient":5,"speciesIds":["road_sprout","puddle_pip"]}""") =
        Json.parseToJsonElement("""{"ts":1,"contractVersion":2,"gameRevision":1,"collectionSummary":$block,"baseSummary":{"builderSpeciesId":"road_sprout"}}""").jsonObject

    @Test fun `saved quantities and dex are read without granting rewards`() {
        val game = assertNotNull(GameSnapshotReader.parse(raw()))
        assertEquals(CollectionSummary(wood = 12, stone = 8, ingredient = 5,
            speciesIds = listOf("road_sprout", "puddle_pip")), game.collectionSummary)
        assertNull(game.fishing)
    }
    @Test fun `missing differs from an explicitly empty saved inventory`() {
        assertNull(GameSnapshotReader.parse(JsonObject(raw() - "collectionSummary"))!!.collectionSummary)
        val game = GameSnapshotReader.parse(raw("""{"version":1,"wood":0,"stone":0,"ingredient":0,"speciesIds":[]}"""))!!
        assertEquals(0, game.collectionSummary!!.speciesIds.size)
        assertEquals(0L, game.collectionSummary!!.wood)
    }
    @Test fun `invalid or unsupported collection hides only collection and never becomes zero`() {
        for (change in listOf("\"wood\":-1", "\"wood\":1.5", "\"wood\":\"12\"", "\"version\":2",
            "\"speciesIds\":[\"road_sprout\",\"road_sprout\"]", "\"speciesIds\":[\"../bad\"]")) {
            val key = change.substringBefore(':').trim('"')
            val block = raw()["collectionSummary"]!!.jsonObject.toMutableMap()
            block[key] = Json.parseToJsonElement("{$change}").jsonObject[key]!!
            val game = GameSnapshotReader.parse(raw(JsonObject(block).toString()))!!
            assertNull(game.collectionSummary)
            assertTrue("collectionSummary" in game.invalidBlocks)
            assertNotNull(game.baseSummary)
        }
        val legacy = GameSnapshotReader.parse(JsonObject(raw() - "contractVersion"))!!
        assertNull(legacy.collectionSummary)
    }
    @Test fun `RTDB empty lists are accepted only with explicit zero count`() {
        val empty = """{"version":1,"wood":0,"stone":0,"ingredient":0,"speciesCount":0}"""
        assertEquals(emptyList(), GameSnapshotReader.parse(raw(empty))!!.collectionSummary!!.speciesIds)
        assertNull(GameSnapshotReader.parse(raw(empty.replace("speciesCount\":0", "speciesCount\":2")))!!.collectionSummary)
        val base = Json.parseToJsonElement("""{"ts":1,"contractVersion":2,"gameRevision":1,
            "baseSummary":{"facilityLevels":{"workshop":1,"kitchen":0,"training":0}}}""").jsonObject
        assertEquals(1, GameSnapshotReader.parse(base)!!.baseSummary!!.facilityLevels["workshop"])
        assertNull(GameSnapshotReader.parse(Json.parseToJsonElement(base.toString().replace("workshop\":1", "workshop\":4")).jsonObject)!!.baseSummary)
    }

    @Test fun `phone village choice distinguishes legacy explicit empty and ordered selection`() {
        val original = raw()["collectionSummary"]!!.jsonObject
        fun read(fields: String) = GameSnapshotReader.parse(raw(JsonObject(original +
            Json.parseToJsonElement(fields).jsonObject).toString()))!!
        assertNull(read("{}").collectionSummary!!.villageSpeciesIds)
        assertEquals(emptyList(), read("""{"villageSpeciesCount":0}""").collectionSummary!!.villageSpeciesIds)
        assertEquals(emptyList(), read("""{"villageSpeciesCount":0,"villageSpeciesIds":[]}""").collectionSummary!!.villageSpeciesIds)
        assertEquals(listOf("puddle_pip", "road_sprout"), read("""{"villageSpeciesCount":2,"villageSpeciesIds":["puddle_pip","road_sprout"]}""").collectionSummary!!.villageSpeciesIds)
        for (fields in listOf(
            """{"villageSpeciesIds":["road_sprout"]}""",
            """{"villageSpeciesCount":1}""",
            """{"villageSpeciesCount":-1}""",
            """{"villageSpeciesCount":5}""",
            """{"villageSpeciesCount":"1","villageSpeciesIds":["road_sprout"]}""",
            """{"villageSpeciesCount":1,"villageSpeciesIds":["unknown"]}""",
            """{"villageSpeciesCount":2,"villageSpeciesIds":["road_sprout","road_sprout"]}""")) {
            val invalid = read(fields)
            assertNull(invalid.collectionSummary, fields)
            assertTrue("collectionSummary" in invalid.invalidBlocks, fields)
            assertNotNull(invalid.baseSummary)
        }
    }

    @Test fun `parking review ignores legacy fishing while driving still wins`() {
        val game = GameState(ts = 1, contractVersion = 2, gameRevision = 1,
            companion = CompanionDisplay("pet", 1, "road_sprout", "car"),
            fishing = FishingSnapshot(1, "lease", "pet", 1, "activity", 0, "running", 0, 60000, 0))
        assertEquals(PleosRoute.Home, PleosFlow.route(true, true, false, true, true, false, game, dismissFishing = true))
        assertEquals(PleosRoute.Driving, PleosFlow.route(true, false, false, true, true, false, game, dismissFishing = true))
    }
}
