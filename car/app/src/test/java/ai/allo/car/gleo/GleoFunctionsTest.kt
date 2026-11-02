package ai.allo.car.gleo

import ai.allo.car.model.GameState
import kotlin.test.Test
import kotlin.test.assertEquals
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
}
