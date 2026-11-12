package ai.allo.car.model

import kotlin.test.*

class PleosFlowTest {
    private val companion = CompanionDisplay("pet-a", 3, "road_sprout", "car")
    private val game = GameState(ts = 1, stage = "hatched", contractVersion = 2, gameRevision = 4, companion = companion)
    private fun terminal(status: TransferStatus) = TransferUiState(status,
        subjectDisplayId = companion.displayId, subjectDisplayRevision = companion.displayRevision)
    private val pending = TransferUiState(TransferStatus.Waiting, pending = TransferRequest("request-a", "pet-a", 3))

    private fun route(
        checked: Boolean = true, parked: Boolean = true, notice: Boolean = false,
        paired: Boolean = true, connected: Boolean = true, ended: Boolean = false,
        snapshot: GameState = game, transfer: TransferUiState = TransferUiState(), dismissed: Boolean = false,
    ) = PleosFlow.route(checked, parked, notice, paired, connected, ended, snapshot, transfer, dismissed)

    @Test fun `unverified startup never exposes pairing or activity controls`() {
        assertEquals(PleosRoute.Starting, route(checked = false, parked = false, paired = false, notice = true))
        assertEquals(PleosRoute.Driving, route(parked = false, paired = false, notice = true))
    }

    @Test fun `driving wins over terminal disconnected and pending states`() {
        assertEquals(PleosRoute.Driving, route(parked = false, ended = true, connected = false, transfer = pending))
        assertEquals(PleosRoute.Driving, route(parked = false, transfer = terminal(TransferStatus.Accepted)))
    }

    @Test fun `parking permission loss immediately hides home base and all fishing controls`() {
        for (state in listOf("ready", "running", "paused", "saving", "saveFailed", "reward")) {
            val snapshot = game.copy(fishing = FishingSnapshot(1, "lease", "pet-a", 3,
                "activity", 0, state, 35000, 60000, 1, "record"))
            assertNotEquals(PleosRoute.Driving, route(snapshot = snapshot))
            assertEquals(PleosRoute.Driving, route(parked = false, snapshot = snapshot))
            assertEquals(PleosRoute.Starting, route(checked = false, parked = false, snapshot = snapshot))
            assertEquals(PleosRoute.Driving, route(parked = false, connected = false, snapshot = snapshot))
            assertNull(FishingController().request("session", snapshot, false, "start", 0))
        }
        assertEquals(PleosRoute.Home, route())
        assertEquals(PleosRoute.Driving, route(parked = false))
        assertEquals(PleosRoute.Home, route())
    }

    @Test fun `parking after session end cannot resume the previous request`() {
        assertEquals(PleosRoute.Ended, route(ended = true, notice = true, connected = false, transfer = pending))
        assertEquals(PleosRoute.Disconnected, route(connected = false, notice = true, transfer = pending))
        assertEquals(PleosRoute.TransferPending, route(transfer = pending))
    }

    @Test fun `permission and pairing apply only after parking and lifecycle gates`() {
        assertEquals(PleosRoute.Permission, route(paired = false, connected = false, notice = true))
        assertEquals(PleosRoute.Pairing, route(paired = false, connected = false))
        assertEquals(PleosRoute.Home, route())
    }

    @Test fun `known absence differs from disconnected invalid legacy or incubating data`() {
        assertEquals(PleosRoute.Empty, route(snapshot = game.copy(companion = null)))
        assertEquals(PleosRoute.Empty, route(snapshot = game.copy(companion = companion.copy(location = "phone"))))
        assertEquals(PleosRoute.Disconnected, route(connected = false, snapshot = game.copy(companion = null)))
        assertEquals(PleosRoute.Home, route(snapshot = game.copy(companion = null, invalidBlocks = setOf("companion"))))
        assertEquals(PleosRoute.Home, route(snapshot = game.copy(companion = null, stage = "incubating")))
        assertEquals(PleosRoute.Home, route(snapshot = GameState()))
    }

    @Test fun `late accepted response never replaces a newly selected car companion`() {
        val accepted = terminal(TransferStatus.Accepted).copy(exitSerial = 1)
        assertEquals(PleosRoute.Home, route(snapshot = game.copy(companion = companion.copy(displayId = "pet-b")), transfer = accepted))
        assertEquals(PleosRoute.TransferComplete, route(snapshot = game.copy(companion = null), transfer = accepted))
        assertEquals(PleosRoute.Home, route(snapshot = game.copy(companion = null, invalidBlocks = setOf("companion")), transfer = accepted))
    }

    @Test fun `dismissing a terminal result changes presentation without restoring the companion`() {
        val onPhone = game.copy(companion = companion.copy(location = "phone"))
        assertEquals(PleosRoute.TransferComplete, route(snapshot = onPhone, transfer = terminal(TransferStatus.Accepted)))
        assertEquals(PleosRoute.Empty, route(snapshot = onPhone, transfer = terminal(TransferStatus.Accepted), dismissed = true))
        assertEquals(PleosRoute.TransferRejected, route(transfer = terminal(TransferStatus.Busy)))
        assertEquals(PleosRoute.Home, route(transfer = terminal(TransferStatus.Busy), dismissed = true))
    }


    @Test fun `pending A is hidden immediately for B and new observation frees B to request`() {
        var nextId = 0
        val controller = CompanionTransferController { "request-${nextId++}" }
        controller.request("s", game, true, 0)
        val other = game.copy(gameRevision = 5, companion = companion.copy(displayId = "pet-b", displayRevision = 4))
        assertEquals(PleosRoute.Home, route(snapshot = other, transfer = controller.state))
        controller.observe("s", other, true)
        assertNull(controller.state.pending)
        assertEquals("pet-b", controller.request("s", other, true, 1)?.displayId)
    }

    @Test fun `accepted A cannot become a completion screen for B on phone`() {
        val controller = CompanionTransferController { "request-a" }
        controller.request("s", game, true, 0)
        val accepted = game.copy(gameRevision = 5, companion = null,
            transferResult = TransferResult("request-a", "pet-a", 3, "accepted", "phone"))
        controller.observe("s", accepted, true)
        assertEquals(PleosRoute.TransferComplete, route(snapshot = accepted, transfer = controller.state))
        val other = accepted.copy(gameRevision = 6,
            companion = CompanionDisplay("pet-b", 4, "lamp_moth", "phone"))
        assertEquals(PleosRoute.Empty, route(snapshot = other, transfer = controller.state))
        controller.observe("s", other, true)
        assertEquals(TransferStatus.Idle, controller.state.status)
        assertEquals(PleosRoute.Empty, route(snapshot = other.copy(companion = null), transfer = controller.state))
    }

    @Test fun `busy A cannot block B or a reselected revision of A`() {
        val controller = CompanionTransferController { "request-a" }
        controller.request("s", game, true, 0)
        val rejected = game.copy(gameRevision = 5,
            transferResult = TransferResult("request-a", "pet-a", 3, "busy", "car"))
        controller.observe("s", rejected, true)
        assertEquals(PleosRoute.TransferRejected, route(snapshot = rejected, transfer = controller.state))
        val other = rejected.copy(gameRevision = 6, companion = companion.copy(displayId = "pet-b", displayRevision = 4))
        assertEquals(PleosRoute.Home, route(snapshot = other, transfer = controller.state))
        assertEquals(PleosRoute.Home, route(snapshot = other.copy(companion = companion.copy(displayRevision = 4)), transfer = controller.state))
        controller.observe("s", other, true)
        assertEquals(TransferStatus.Idle, controller.state.status)
        assertNotNull(controller.request("s", other, true, 10))
    }

    @Test fun `matching completion remains valid when phone location precedes its receipt`() {
        val controller = CompanionTransferController { "request-a" }
        controller.request("s", game, true, 0)
        val onPhone = game.copy(gameRevision = 5, companion = companion.copy(displayRevision = 4, location = "phone"))
        controller.observe("s", onPhone, true)
        assertNotNull(controller.state.pending)
        val accepted = onPhone.copy(gameRevision = 6,
            transferResult = TransferResult("request-a", "pet-a", 3, "accepted", "phone"))
        controller.observe("s", accepted, true)
        assertEquals(PleosRoute.TransferComplete, route(snapshot = accepted, transfer = controller.state))
        assertEquals(1L, controller.state.exitSerial)
    }

    @Test fun `current wire contract cannot manufacture fishing or selection progress`() {
        val unsupportedRoutes = setOf(PleosRoute.Fishing, PleosRoute.Saving, PleosRoute.Reward,
            PleosRoute.Paused, PleosRoute.SaveFailed, PleosRoute.SelectionPending, PleosRoute.SelectionFailed)
        for (status in TransferStatus.entries) {
            assertFalse(route(transfer = TransferUiState(status)) in unsupportedRoutes)
        }
        assertEquals(0f, FishingDisplay(35, 0).progress)
        assertEquals(1f, FishingDisplay(70, 60).progress)
        assertEquals(0f, FishingDisplay(-1, 60).progress)
    }
}
