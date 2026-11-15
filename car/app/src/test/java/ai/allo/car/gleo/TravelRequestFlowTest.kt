package ai.allo.car.gleo

import ai.allo.car.model.TravelRequest
import ai.allo.car.navi.Guidance
import ai.allo.car.vehicle.GeoPoint
import kotlin.test.*

class TravelRequestFlowTest {
    private val context = TravelRequestFlow.Context("session", true, false, true,
        TravelRequest("wish", "coast"), "city", true)
    private fun offered(flow: TravelRequestFlow, ctx: TravelRequestFlow.Context = context) =
        assertIs<TravelRequestFlow.Offer.Made>(flow.offer(ctx, null))

    @Test fun `target region candidates do not depend on collection and omit unknown distance`() {
        val offer = offered(TravelRequestFlow())
        assertEquals(3, offer.suggestions.size)
        assertTrue(offer.suggestions.all { it.destination.region == "coast" && !it.uncollected && it.distanceKm == null })
    }

    @Test fun `nearby candidates are sorted bounded and limited`() {
        val offer = assertIs<TravelRequestFlow.Offer.Made>(TravelRequestFlow().offer(context, GeoPoint(37.4, 127.11)))
        assertTrue(offer.suggestions.size in 1..3)
        assertTrue(offer.suggestions.all { it.distanceKm!! <= 120.0 })
        assertTrue(offer.suggestions.zipWithNext().all { (a,b) -> a.distanceKm!! <= b.distanceKm!! })
    }

    @Test fun `no nearby destination and already in region have distinct states`() {
        val flow = TravelRequestFlow()
        assertEquals(TravelRequestFlow.Offer.None(TravelRequestFlow.Reason.NONE_NEARBY), flow.offer(context, GeoPoint(0.0, 0.0)))
        assertEquals(TravelRequestFlow.Offer.None(TravelRequestFlow.Reason.CONFIRM_VISIT_ON_PHONE), flow.offer(context.copy(currentRegion = "coast"), null))
    }

    @Test fun `unsupported and malformed requests never make offers`() {
        for (ctx in listOf(context.copy(hasV2Contract = false), context.copy(request = null),
            context.copy(request = TravelRequest("", "coast")), context.copy(request = TravelRequest("wish", "invalid")),
            context.copy(sessionId = null), context.copy(connected = false), context.copy(ended = true), context.copy(parked = false))) {
            assertIs<TravelRequestFlow.Offer.None>(TravelRequestFlow().offer(ctx, null))
        }
    }

    @Test fun `latest token prevents an old index from accepting a different offer`() {
        val flow = TravelRequestFlow()
        val old = offered(flow)
        val latest = offered(flow)
        assertNotEquals(old.token, latest.token)
        assertEquals(AcceptResult.NoOffer, flow.accept(old.token, 0, context, Guidance.IDLE) { error("stale") })
        assertEquals(AcceptResult.Started(latest.suggestions[1].destination), flow.accept(latest.token, 1, context, Guidance.IDLE) { true })
        assertEquals(AcceptResult.NoOffer, flow.accept(latest.token, 1, context, Guidance.IDLE) { error("duplicate") })
    }

    @Test fun `every context change invalidates prior offer even when original context returns`() {
        for (changed in listOf(context.copy(sessionId = "new"), context.copy(connected = false), context.copy(ended = true),
            context.copy(request = null), context.copy(request = TravelRequest("new", "coast")),
            context.copy(request = TravelRequest("wish", "mountain")), context.copy(currentRegion = "mountain"),
            context.copy(parked = false), context.copy(hasV2Contract = false))) {
            val flow = TravelRequestFlow()
            val offer = offered(flow)
            flow.update(changed)
            flow.update(context)
            assertEquals(AcceptResult.NoOffer, flow.accept(offer.token, 0, context, Guidance.IDLE) { error("invalidated") })
        }
    }

    @Test fun `accept independently rechecks latest context`() {
        val flow = TravelRequestFlow()
        val offer = offered(flow)
        assertEquals(AcceptResult.NoOffer, flow.accept(offer.token, 0, context.copy(request = null), Guidance.IDLE) { error("closed") })
    }

    @Test fun `guiding and unknown guidance preserve route and permit later idle acceptance`() {
        val flow = TravelRequestFlow()
        val offer = offered(flow)
        assertEquals(AcceptResult.RouteActive, flow.accept(offer.token, 0, context, Guidance.GUIDING) { error("guiding") })
        assertEquals(AcceptResult.NaviNotReady, flow.accept(offer.token, 0, context, Guidance.UNKNOWN) { error("unknown") })
        assertEquals(AcceptResult.NaviNotReady, flow.accept(offer.token, 0, context, Guidance.IDLE) { false })
        assertEquals(AcceptResult.NaviNotReady, flow.accept(offer.token, 0, context, Guidance.IDLE) { throw IllegalStateException("SDK unavailable") })
        assertIs<AcceptResult.Started>(flow.accept(offer.token, 0, context, Guidance.IDLE) { true })
    }

    @Test fun `expiry clock rollback reset and invalid indices never invoke navigation`() {
        var time = 100L
        val flow = TravelRequestFlow(now = { time }, ttlMs = 1000L)
        var offer = offered(flow)
        for (index in listOf(-1, 3, Int.MAX_VALUE)) assertEquals(AcceptResult.NoOffer, flow.accept(offer.token, index, context, Guidance.IDLE) { error("index") })
        time = 1101L
        assertEquals(AcceptResult.NoOffer, flow.accept(offer.token, 0, context, Guidance.IDLE) { error("expired") })
        offer = offered(flow)
        time = 0L
        assertEquals(AcceptResult.NoOffer, flow.accept(offer.token, 0, context, Guidance.IDLE) { error("clock") })
        offer = offered(flow)
        flow.reset()
        assertEquals(AcceptResult.NoOffer, flow.accept(offer.token, 0, context, Guidance.IDLE) { error("reset") })
    }
    @Test fun `exact target only offers the requested place even in same region`() {
        val destination = DestinationSuggester.CANDIDATES.first { it.region == "coast" }
        val ctx = context.copy(request = TravelRequest("wish", "coast", destination.placeId), currentRegion = "coast")
        val offer = offered(TravelRequestFlow(), ctx)
        assertEquals(listOf(destination), offer.suggestions.map { it.destination })
        assertIs<TravelRequestFlow.Offer.None>(TravelRequestFlow().offer(ctx.copy(request = TravelRequest("wish", "coast", "place_0000000000000000")), null))
    }
}
