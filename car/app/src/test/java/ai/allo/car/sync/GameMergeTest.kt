package ai.allo.car.sync

import ai.allo.car.gleo.RegionSummary
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals

class GameMergeTest {
    private fun o(raw: String) = Json.parseToJsonElement(raw).jsonObject
    private val full = o("""{"stage":"incubating","progress":0.4,"regionCollectionKnown":true,"uncollectedRegions":["coast"]}""")

    @Test fun `root put replaces everything`() {
        val next = GameMerge.apply(full, "put", "/", o("""{"stage":"idle"}"""))
        assertEquals(o("""{"stage":"idle"}"""), next)
        assertEquals(RegionSummary.Unknown, RegionSummary.parse(next))   // 새 set 에 요약이 없으면 이전 요약을 쓰지 않는다
    }

    @Test fun `root null or corrupt drops the previous summary`() {
        assertEquals(JsonObject(emptyMap()), GameMerge.apply(full, "put", "/", JsonNull))
        assertEquals(JsonObject(emptyMap()), GameMerge.apply(full, "put", "/", JsonPrimitive("broken")))
        assertEquals(RegionSummary.Unknown, RegionSummary.parse(GameMerge.apply(full, "put", "/", JsonNull)))
    }

    @Test fun `root patch merges children and removes nulls`() {
        val next = GameMerge.apply(full, "patch", "/", o("""{"progress":0.5,"uncollectedRegions":null}"""))
        assertEquals(o("""{"stage":"incubating","progress":0.5,"regionCollectionKnown":true}"""), next)
        assertEquals(RegionSummary.Known(emptySet()), RegionSummary.parse(next))
    }

    @Test fun `shallow put sets or removes one key`() {
        assertEquals(0.9, GameMerge.apply(full, "put", "/progress", JsonPrimitive(0.9))["progress"].toString().toDouble())
        assertEquals(false, "progress" in GameMerge.apply(full, "put", "/progress", JsonNull))
    }

    @Test fun `deep region update makes the summary unknown until the next full set`() {
        val next = GameMerge.apply(full, "put", "/uncollectedRegions/0", JsonPrimitive("mountain"))
        assertEquals(RegionSummary.Unknown, RegionSummary.parse(next))
        assertEquals("incubating", next["stage"]?.toString()?.trim('"'))
    }
}
