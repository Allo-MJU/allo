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

    @Test fun `fallback suggestion does not claim unvisited`() {
        val s = DestinationSuggester.pick(currentRegion = "city")!!
        val msg = GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(), s).message
        assertFalse("안 가보셨" in msg)
        assertTrue("바다" in msg && "경포해변까지" in msg)
    }

    @Test fun `known unvisited suggestion says so`() {
        val s = DestinationSuggester.pick(currentRegion = "city", unvisitedRegions = listOf("mountain"))!!
        val msg = GleoFunctions.respond(GleoFunctions.SUGGEST_DESTINATION, GameState(), s).message
        assertTrue("산 쪽은 아직 안 가보셨네요" in msg)
    }

    @Test fun `accept without suggestion fails`() {
        assertEquals("fail", GleoFunctions.respondAccept(null).status)
        assertEquals("success", GleoFunctions.respondAccept(DestinationSuggester.DESTINATIONS.getValue("coast")).status)
    }

    @Test fun `confirm extra accepts boolean and string`() {
        assertTrue(GleoReceiver.parseConfirm(true))
        assertTrue(GleoReceiver.parseConfirm("TRUE"))
        assertFalse(GleoReceiver.parseConfirm("yes"))
        assertFalse(GleoReceiver.parseConfirm(null))
    }
}
