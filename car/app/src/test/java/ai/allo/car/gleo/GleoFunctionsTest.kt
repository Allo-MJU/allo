package ai.allo.car.gleo

import ai.allo.car.model.GameState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GleoFunctionsTest {
    @Test fun `report while incubating mentions progress`() {
        val cb = GleoFunctions.respond(GleoFunctions.REPORT_EGG_STATUS, GameState(stage = "incubating", eggTier = "mid", progress = 0.62))
        assertEquals("success", cb.status)
        assertTrue("62" in cb.message && "중간" in cb.message)
    }

    @Test fun `unknown function fails`() {
        assertEquals("fail", GleoFunctions.respond("NOPE", GameState()).status)
    }

    @Test fun `destination suggestion without region is graceful`() {
        val cb = GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(), null)
        assertEquals("fail", cb.status)   // 제안할 곳이 없으면 fail (Pleos Callback Schema)
        assertTrue(cb.message.isNotBlank())
    }

    private fun made(region: String, name: String, unvisited: Boolean, km: Double? = null, alt: Boolean = false) =
        DestinationFlow.Offer.Made(Suggestion(DestinationSuggester.CANDIDATES.first { it.name == name }.also { assertEquals(region, it.region) }, unvisited, km, alt))

    @Test fun `fallback suggestion does not claim unvisited`() {
        val msg = GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(), made("coast", "경포해변", false)).message
        assertFalse("안 가보셨" in msg)
        assertTrue("바다" in msg && "경포해변까지" in msg && "같은 바다라면" in msg)
    }

    @Test fun `known unvisited suggestion says so with distance`() {
        val msg = GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(), made("mountain", "북한산 국립공원", true, 28.4)).message
        assertTrue("산 쪽은 아직 안 가보셨네요" in msg)
        assertTrue("직선으로 약 30km" in msg)
        assertTrue("같은 산이라면" in msg)
    }

    @Test fun `alternative offer is short`() {
        val msg = GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(), made("coast", "을왕리해수욕장", false, 67.0, alt = true)).message
        assertTrue(msg.startsWith("바다 쪽 을왕리해수욕장도 있어요."))
    }

    @Test fun `none reasons have distinct messages`() {
        val msgs = NoSuggestion.values().map { GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(), DestinationFlow.Offer.None(it)).message }
        assertEquals(msgs.size, msgs.toSet().size)
    }

    @Test fun `km rounding`() {
        assertEquals(5, GleoFunctions.roundKm(1.0))
        assertEquals(30, GleoFunctions.roundKm(28.4))
        assertEquals(65, GleoFunctions.roundKm(66.0))
    }

    @Test fun `accept results map to callback status and only success is silent`() {
        val ok = GleoFunctions.respondAccept(AcceptResult.Started(DestinationSuggester.CANDIDATES.first()))
        assertEquals("success", ok.status)
        assertNull(ok.mode)   // 기본은 Gleo 가 말한다
        // 차량 앱 TTS 가 말했으면 silent, 못 했으면(미준비·실패) Gleo 음성 유지 — 경로는 설정됐는데 아무도 안 알리는 일이 없게
        assertEquals("silent", GleoFunctions.selfVoiced(ok, spoke = true).mode)
        assertEquals(ok, GleoFunctions.selfVoiced(ok, spoke = false))
        for (r in listOf(AcceptResult.NoOffer, AcceptResult.RouteActive, AcceptResult.NaviNotReady)) {
            val cb = GleoFunctions.respondAccept(r)
            assertEquals("fail", cb.status, r.toString())
            assertNull(cb.mode)
        }
    }

    @Test fun `suggestion asks for confirmation, no suggestion fails`() {
        val d = DestinationSuggester.CANDIDATES.first()
        assertEquals("asking", GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(),
            DestinationFlow.Offer.Made(Suggestion(d, false, 30.0))).status)
        for (why in NoSuggestion.values()) {
            val cb = GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(), DestinationFlow.Offer.None(why))
            assertEquals("fail", cb.status)
            assertTrue(cb.message.isNotBlank())
        }
    }

    @Test fun `ACTION_PARAM parses plain, quoted and string-wrapped json`() {
        assertEquals(true, GleoReceiver.parseParams("""{"confirm":true}""")?.get("confirm")?.let { GleoReceiver.parseConfirm(it) })
        assertEquals(true, GleoReceiver.parseParams(""""{"confirm":"true"}"""")?.get("confirm")?.let { GleoReceiver.parseConfirm(it) })   // 문서 예시 형태
        assertEquals(true, GleoReceiver.parseParams(""""{\"confirm\":true}"""")?.get("confirm")?.let { GleoReceiver.parseConfirm(it) }) // JSON 문자열 안의 JSON
        assertEquals(0, GleoReceiver.parseParams("{}")?.size)
        assertNull(GleoReceiver.parseParams(null))
        assertNull(GleoReceiver.parseParams("not json"))
        assertNull(GleoReceiver.parseParams("[1,2]"))
    }

    @Test fun `confirm extra accepts boolean and string`() {
        assertTrue(GleoReceiver.parseConfirm(true))
        assertTrue(GleoReceiver.parseConfirm("TRUE"))
        assertFalse(GleoReceiver.parseConfirm("yes"))
        assertFalse(GleoReceiver.parseConfirm(null))
        assertTrue(GleoReceiver.parseConfirm(kotlinx.serialization.json.JsonPrimitive(true)))
        assertFalse(GleoReceiver.parseConfirm(kotlinx.serialization.json.JsonPrimitive(false)))
    }
}
