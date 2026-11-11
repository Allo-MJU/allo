package ai.allo.car.model

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class GameSnapshotReaderTest {
    private fun raw(extra: String = "", revision: Long = 1) = Json.parseToJsonElement(
        """{"ts":1,"stage":"incubating","progress":0.4,"contractVersion":2,"gameRevision":$revision$extra}""").jsonObject

    @Test fun v2ReadsIndependentCompanionAndResultWhileEggIncubates() {
        val game = GameSnapshotReader.parse(raw(""", "affinity":{"score":2,"target":3,"ready":false},"companion":{"displayId":"d","displayRevision":2,"speciesId":"road_sprout","location":"phone"},"transferResult":{"requestId":"r","displayId":"d","requestRevision":1,"status":"accepted","resultLocation":"phone"}"""))!!
        assertTrue(game.hasV2Contract); assertNull(game.speciesId)
        assertEquals("road_sprout", game.companion!!.speciesId)
        assertEquals(1L, game.transferResult!!.requestRevision)
    }
    @Test fun invalidOptionalBlockDoesNotHideOtherValidBlocks() {
        val g = GameSnapshotReader.parse(raw(""", "affinity":{"score":"2","target":3,"ready":true},"baseSummary":{"builderSpeciesId":"road_sprout"}"""))!!
        assertNull(g.affinity); assertTrue("affinity" in g.invalidBlocks)
        assertEquals(emptyList<String>(), g.baseSummary!!.structureIds)
    }
    @Test fun malformedBaseIsNotAnEmptyValidBase() {
        val g = GameSnapshotReader.parse(raw(""", "baseSummary":{"structureIds":"shelter"},"travelRequest":{"wishId":"w","targetRegion":"coast"}"""))!!
        assertNull(g.baseSummary); assertTrue("baseSummary" in g.invalidBlocks)
        assertEquals("coast", g.travelRequest!!.targetRegion)
    }
    @Test fun numericStringsAndFractionalRevisionsAreRejected() {
        for (revision in listOf("\"2\"", "2.5", "true", "-1")) {
            assertNull(GameSnapshotReader.parse(Json.parseToJsonElement("""{"ts":1,"contractVersion":2,"gameRevision":$revision}""").jsonObject))
        }
    }
    @Test fun failedIsNeverMappedToHatchedAndReadyIsNotComputed() {
        val g = GameSnapshotReader.parse(raw(""", "affinity":{"score":3,"target":3,"ready":false}""").toMutableMap().let { JsonObject(it + ("stage" to JsonPrimitive("failed"))) })!!
        assertEquals("failed", g.stage); assertFalse(g.affinity!!.ready)
    }
    @Test fun unknownOrMissingVersionDoesNotActivateNewBlocks() {
        for (version in listOf<JsonElement?>(null, JsonPrimitive(99), JsonPrimitive("2"))) {
            val m = raw(""", "companion":{"displayId":"d","displayRevision":1,"speciesId":"road_sprout","location":"car"}""").toMutableMap()
            if (version == null) m.remove("contractVersion") else m["contractVersion"] = version
            val g = GameSnapshotReader.parse(JsonObject(m))!!
            assertFalse(g.hasV2Contract); assertNull(g.companion)
        }
    }
    @Test fun invalidEnumsAndBooleanStringsHideOnlyTheirBlock() {
        val g = GameSnapshotReader.parse(raw(""", "affinity":{"score":1,"target":3,"ready":"false"},"travelRequest":{"wishId":"w","targetRegion":"moon"},"companion":{"displayId":"d","displayRevision":1,"speciesId":"road_sprout","location":"elsewhere"}"""))!!
        assertNull(g.affinity); assertNull(g.travelRequest); assertNull(g.companion)
    }
    @Test fun connectionWaitsForRootAndDoesNotUseGameTimestampAsHeartbeat() {
        val r = GameSnapshotReducer()
        assertFalse(r.apply(raw(), root = false)); assertFalse(r.connected)
        assertTrue(r.apply(raw(), root = true)); assertTrue(r.connected)
        r.disconnect(); assertFalse(r.connected)
        assertFalse(r.apply(raw(revision = 2), root = false))
        assertTrue(r.apply(raw(), root = true)); assertTrue(r.connected)
    }
    @Test fun rejectsRegressionsSameRevisionMutationAndV2Downgrade() {
        val r = GameSnapshotReducer(); assertTrue(r.apply(raw(revision=8), true))
        assertFalse(r.apply(raw(revision=7), true)); assertEquals(8L, r.game.gameRevision)
        assertFalse(r.apply(raw(""", "progress":0.9""", 8), true)); assertEquals(0.4, r.game.progress, 0.0)
        assertFalse(r.apply(Json.parseToJsonElement("""{"ts":999,"stage":"hatched"}""").jsonObject, true))
        r.reset(); assertTrue(r.apply(raw(revision=1), true)); assertEquals(1L,r.game.gameRevision)
    }
    @Test fun malformedOrDeletedRootDisablesActionsUntilValidRoot() {
        val r = GameSnapshotReducer()
        assertTrue(r.apply(raw(), true))
        assertFalse(r.apply(JsonObject(emptyMap()), true))
        assertFalse(r.connected)
        assertFalse(r.apply(raw(revision=2), false))
        assertTrue(r.apply(raw(revision=2), true))
        assertTrue(r.connected)
    }

    @Test fun phaseContractKeepsFractionalScoreAndIndependentCompanion() {
        val g = GameSnapshotReader.parse(raw(""", "affinity":{"score":12.345,"target":100,"phase":"incubating","photoCompleted":false},"companion":{"displayId":"d","displayRevision":2,"speciesId":"road_sprout","location":"car"}"""))!!
        assertEquals(12.345, g.affinity!!.score, 0.0)
        assertEquals("12.345", g.affinity!!.scoreText)
        assertFalse(g.affinity!!.ready)
        assertEquals("car", g.companion!!.location)
    }
    @Test fun phaseContractSeparatesPhotoAndPendingFromPersistedHatch() {
        for ((phase, stage) in listOf("photoRequired" to "incubating", "resultPending" to "incubating", "hatched" to "hatched", "failed" to "failed", "discarded" to "failed")) {
            val photo = phase in setOf("hatched", "resultPending")
            val score = if (photo) 100 else 50
            val body = raw(""", "affinity":{"score":$score,"target":100,"phase":"$phase","photoCompleted":$photo}""")
            val g = GameSnapshotReader.parse(JsonObject(body + ("stage" to JsonPrimitive(stage))))!!
            assertEquals(phase, g.affinity!!.phase)
            assertEquals(stage, g.stage)
            assertFalse(g.affinity!!.ready)
        }
    }
    @Test fun invalidPhaseOrContradictionHidesOnlyAffinity() {
        for (affinity in listOf(
            """{"score":100,"target":100,"phase":"hatched","photoCompleted":true}""",
            """{"score":50,"target":100,"phase":"photoRequired","photoCompleted":true}""",
            """{"score":100,"target":100,"phase":"resultPending","photoCompleted":false}""",
            """{"score":101,"target":100,"phase":"incubating","photoCompleted":false}""",
            """{"score":"10.5","target":100,"phase":"incubating","photoCompleted":false}""",
            """{"score":10,"target":100,"phase":"future","photoCompleted":false}""")) {
            val g = GameSnapshotReader.parse(raw(""", "affinity":$affinity,"companion":{"displayId":"d","displayRevision":1,"speciesId":"road_sprout","location":"car"}"""))!!
            assertNull(g.affinity); assertTrue("affinity" in g.invalidBlocks)
            assertEquals("d", g.companion!!.displayId)
        }
    }

}
