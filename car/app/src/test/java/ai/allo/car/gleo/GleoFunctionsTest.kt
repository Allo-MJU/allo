package ai.allo.car.gleo

import ai.allo.car.model.GameState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
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
        assertEquals("success", cb.status)
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

    @Test fun `accept without suggestion fails`() {
        assertEquals("fail", GleoFunctions.respondAccept(null).status)
        assertEquals("success", GleoFunctions.respondAccept(DestinationSuggester.CANDIDATES.first()).status)
    }

    @Test fun `confirm extra accepts boolean and string`() {
        assertTrue(GleoReceiver.parseConfirm(true))
        assertTrue(GleoReceiver.parseConfirm("TRUE"))
        assertFalse(GleoReceiver.parseConfirm("yes"))
        assertFalse(GleoReceiver.parseConfirm(null))
    }
}
