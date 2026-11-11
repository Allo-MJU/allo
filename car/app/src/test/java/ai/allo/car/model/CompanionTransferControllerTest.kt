package ai.allo.car.model

import org.junit.Assert.*
import org.junit.Test

class CompanionTransferControllerTest {
    private fun game(revision: Long = 1, companion: CompanionDisplay? = CompanionDisplay("pet-1", 3, "road_sprout", "car"), result: TransferResult? = null) =
        GameState(contractVersion = 2, gameRevision = revision, companion = companion, transferResult = result)
    private fun controller() = CompanionTransferController { "request-1" }
    private fun result(status: String = "accepted", request: String = "request-1", display: String = "pet-1", revision: Long = 3, location: String? = "phone") =
        TransferResult(request, display, revision, status, location)

    @Test fun requestPreservesDisplayAndAllowsOnlyOnePendingRequest() {
        val c = controller()
        val request = c.request("session-1", game(), true, 100)!!
        assertEquals(TransferRequest("request-1", "pet-1", 3), request)
        assertEquals(request, c.state.pending)
        assertEquals(0L, c.state.exitSerial)
        assertEquals(TransferStatus.Waiting, c.state.status)
        assertNull(c.request("session-1", game(), true, 200))
    }
    @Test fun rejectedPreconditionsNeverCreateRequests() {
        val c = controller()
        assertNull(c.request("session-1", game(), false, 0))
        assertNull(c.request("session-1", GameState(), true, 0))
        assertNull(c.request("session-1", game(companion = null), true, 0))
        assertNull(c.request("session-1", game(companion = CompanionDisplay("pet-1", 3, "road_sprout", "phone")), true, 0))
        assertEquals(TransferStatus.AlreadyOnPhone, c.state.status)
    }
    @Test fun mismatchedIndependentResultsCannotCompletePending() {
        val c = controller()
        c.request("session-1", game(), true, 0)
        listOf(result(request = "other"), result(display = "other"), result(revision = 2), result(location = "car"), result(status = "unknown")).forEachIndexed { i, r ->
            c.observe("session-1", game(i + 2L, result = r), true)
            assertNotNull(c.state.pending)
            assertEquals(0L, c.state.exitSerial)
        }
    }
    @Test fun acceptedAfterCompanionDisappearsExitsExactlyOnce() {
        val c = controller()
        c.request("session-1", game(), true, 0)
        val accepted = game(2, companion = null, result = result())
        c.observe("session-1", accepted, true)
        assertEquals(TransferStatus.Accepted, c.state.status)
        assertNull(c.state.pending)
        assertEquals(1L, c.state.exitSerial)
        c.observe("session-1", accepted, true)
        assertEquals(1L, c.state.exitSerial)
    }
    @Test fun previousSelectionResultDoesNotAnimateNewCompanion() {
        val c = controller()
        c.request("session-1", game(), true, 0)
        c.observe("session-1", game(2, CompanionDisplay("pet-2", 4, "lamp_moth", "car"), result()), true)
        assertNull(c.state.pending)
        assertEquals(TransferStatus.Accepted, c.state.status)
        assertEquals(0L, c.state.exitSerial)
    }
    @Test fun reselectedSamePetDoesNotExitButConfirmedPhoneLocationDoes() {
        val c = controller()
        c.request("session-1", game(), true, 0)
        c.observe("session-1", game(2, CompanionDisplay("pet-1", 5, "road_sprout", "car"), result()), true)
        assertEquals(0L, c.state.exitSerial)
        val moved = controller()
        moved.request("session-1", game(), true, 0)
        moved.observe("session-1", game(2, CompanionDisplay("pet-1", 4, "road_sprout", "phone"), result()), true)
        assertEquals(1L, moved.state.exitSerial)
    }
    @Test fun terminalReasonsAreDistinctAndNeverTriggerExit() {
        listOf("alreadyOnPhone" to TransferStatus.AlreadyOnPhone, "busy" to TransferStatus.Busy, "staleSelection" to TransferStatus.StaleSelection).forEach { (status, expected) ->
            val c = controller()
            c.request("session-1", game(), true, 0)
            c.observe("session-1", game(2, result = result(status)), true)
            assertEquals(expected, c.state.status)
            assertTrue(c.state.message.isNotBlank())
            assertNull(c.state.pending)
            assertEquals(0L, c.state.exitSerial)
        }
    }
    @Test fun timeoutRequestsOneRefreshAndLateResultStillCompletes() {
        val c = controller()
        val request = c.request("session-1", game(), true, 100)!!
        assertFalse(c.checkTimeout(10099))
        assertTrue(c.checkTimeout(10100))
        assertFalse(c.checkTimeout(20100))
        assertEquals(TransferStatus.Unconfirmed, c.state.status)
        assertEquals(request, c.state.pending)
        c.observe("session-1", game(2, result = result()), true)
        assertEquals(TransferStatus.Accepted, c.state.status)
    }
    @Test fun explicitRetryKeepsOriginalIdsAfterSelectionChanges() {
        val c = controller()
        val request = c.request("session-1", game(), true, 0)
        c.checkTimeout(10000)
        assertEquals(request, c.retry("session-1", game(2, CompanionDisplay("pet-2", 4, "lamp_moth", "car")), true, 11000))
        assertEquals(TransferStatus.Waiting, c.state.status)
    }
    @Test fun disconnectAndSessionReplacementInvalidatePendingWithoutReplay() {
        val c = controller()
        c.request("session-1", game(), true, 0)
        c.disconnect()
        assertNull(c.state.pending)
        assertNull(c.retry("session-1", game(), true, 11000))
        c.observe("session-1", game(2, result = result()), true)
        assertEquals(0L, c.state.exitSerial)
        c.request("session-1", game(3), true, 12000)
        c.observe("session-2", game(result = result()), true)
        assertNull(c.state.pending)
        assertEquals(0L, c.state.exitSerial)
    }
    @Test fun endingSessionWinsOverResultAndRequiresNewSession() {
        val c = controller()
        c.request("session-1", game(), true, 0)
        c.observe("session-1", game(2, result = result()), true, ended = true)
        assertEquals(TransferStatus.Ended, c.state.status)
        assertEquals(0L, c.state.exitSerial)
        assertNull(c.request("session-1", game(3), true, 12000))
        assertNotNull(c.request("session-2", game(), true, 13000))
        c.endSession()
        assertNull(c.state.pending)
        assertFalse(c.checkTimeout(30000))
    }
    @Test fun staleRevisionCannotResolvePending() {
        val c = controller()
        c.request("session-1", game(5), true, 0)
        c.observe("session-1", game(4, result = result()), true)
        assertNotNull(c.state.pending)
        c.observe("session-1", game(6, result = result()), true)
        assertEquals(TransferStatus.Accepted, c.state.status)
    }
}
