package ai.allo.car.model

import ai.allo.car.gleo.TravelRequestFlow
import ai.allo.car.gleo.AcceptResult
import ai.allo.car.navi.Guidance
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

/** Whole phone snapshots through parsing and vehicle consumers, without Firebase or SDK claims. */
class VehicleContractIntegrationTest {
    private fun snapshot(revision: Int, tail: String) = Json.parseToJsonElement("""{"ts":1,"stage":"incubating","contractVersion":2,"gameRevision":$revision,$tail}""").jsonObject
    private val companion = """"companion":{"displayId":"d","displayRevision":4,"speciesId":"road_sprout","location":"car"}"""
    @Test fun transferWaitsForMatchingNewSnapshotAndDoesNotReplayAfterReconnect() {
        val reducer = GameSnapshotReducer()
        val transfer = CompanionTransferController { "r" }
        assertTrue(reducer.apply(snapshot(1, companion), true))
        transfer.request("s", reducer.game, reducer.connected, 0)
        assertEquals(TransferStatus.Waiting, transfer.state.status)
        val accepted = snapshot(2, """"transferResult":{"requestId":"r","displayId":"d","requestRevision":4,"status":"accepted","resultLocation":"phone"}""")
        assertTrue(reducer.apply(accepted, true))
        transfer.observe("s", reducer.game, reducer.connected)
        assertEquals(1L, transfer.state.exitSerial)
        reducer.disconnect(); transfer.disconnect()
        assertTrue(reducer.apply(accepted, true))
        transfer.observe("s", reducer.game, reducer.connected)
        assertEquals(1L, transfer.state.exitSerial)
    }
    @Test fun changedPhoneWishInvalidatesPreviouslyOfferedRoute() {
        val reducer = GameSnapshotReducer()
        val travel = TravelRequestFlow()
        fun context() = TravelRequestFlow.Context("s", reducer.connected, false, reducer.game.hasV2Contract,
            reducer.game.travelRequest, null, true)
        assertTrue(reducer.apply(snapshot(1, """"travelRequest":{"wishId":"w1","targetRegion":"coast"}"""), true))
        val offer = travel.offer(context(), null) as TravelRequestFlow.Offer.Made
        assertTrue(reducer.apply(snapshot(2, """"travelRequest":{"wishId":"w2","targetRegion":"mountain"}"""), true))
        var sdkCalls = 0
        assertEquals(AcceptResult.NoOffer, travel.accept(offer.token, 0, context(), Guidance.IDLE) { sdkCalls++; true })
        assertEquals(0, sdkCalls)
    }
}
