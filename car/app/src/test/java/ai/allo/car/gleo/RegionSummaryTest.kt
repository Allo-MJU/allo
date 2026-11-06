package ai.allo.car.gleo

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlin.test.Test
import kotlin.test.assertEquals

/** docs/schema.md "지역 추천 요약" 표 */
class RegionSummaryTest {
    private fun p(raw: String) = RegionSummary.parse(Json.parseToJsonElement(raw))
    private fun known(vararg r: String) = RegionSummary.Known(r.toSet())

    @Test fun `known missing or false is unknown even with a list`() {
        assertEquals(RegionSummary.Unknown, p("""{"stage":"idle"}"""))
        assertEquals(RegionSummary.Unknown, p("""{"regionCollectionKnown":false,"uncollectedRegions":["coast"]}"""))
        assertEquals(RegionSummary.Unknown, p("""{"uncollectedRegions":["coast"]}"""))   // 구버전 폰
    }

    @Test fun `known true with a valid list uses it once per region`() {
        assertEquals(known("coast", "mountain"), p("""{"regionCollectionKnown":true,"uncollectedRegions":["coast","mountain","coast"]}"""))
        assertEquals(known("city"), p("""{"regionCollectionKnown":true,"uncollectedRegions":["city"]}"""))
    }

    @Test fun `known true with empty, missing or null list means all collected`() {
        assertEquals(known(), p("""{"regionCollectionKnown":true,"uncollectedRegions":[]}"""))
        assertEquals(known(), p("""{"regionCollectionKnown":true}"""))   // RTDB 가 빈 배열 키를 지운 경우
        assertEquals(known(), p("""{"regionCollectionKnown":true,"uncollectedRegions":null}"""))
    }

    @Test fun `broken values are unknown, not an emptied list`() {
        for (raw in listOf(
            """{"regionCollectionKnown":"true","uncollectedRegions":["coast"]}""",   // known 타입 오류
            """{"regionCollectionKnown":1,"uncollectedRegions":["coast"]}""",
            """{"regionCollectionKnown":true,"uncollectedRegions":"coast"}""",       // 목록 타입 오류
            """{"regionCollectionKnown":true,"uncollectedRegions":{"0":"coast"}}""",
            """{"regionCollectionKnown":true,"uncollectedRegions":["coast",1]}""",   // 원소 타입 오류
            """{"regionCollectionKnown":true,"uncollectedRegions":["coast","desert"]}""",   // 알 수 없는 지역
            """{"regionCollectionKnown":true,"uncollectedRegions":["none"]}""",
            """{"regionCollectionKnown":true,"uncollectedRegions":[null]}""",
        )) assertEquals(RegionSummary.Unknown, p(raw), raw)
    }

    @Test fun `null or non-object game is unknown`() {
        assertEquals(RegionSummary.Unknown, RegionSummary.parse(null))
        assertEquals(RegionSummary.Unknown, RegionSummary.parse(JsonNull))
        assertEquals(RegionSummary.Unknown, p("[1]"))
    }
}
