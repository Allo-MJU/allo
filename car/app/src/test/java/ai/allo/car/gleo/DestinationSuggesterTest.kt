package ai.allo.car.gleo

import ai.allo.car.vehicle.GeoPoint
import ai.allo.car.vehicle.RegionTagger
import kotlin.test.*

class DestinationSuggesterTest {
    private val pangyo = GeoPoint(37.40, 127.11)       // 에뮬레이터 내비 고정 위치
    private val gangneung = GeoPoint(37.75, 128.88)

    @Test fun `every candidate is classified into its own region`() {
        for (d in DestinationSuggester.CANDIDATES) assertEquals(d.region, RegionTagger.classify(d.point), d.name)
    }

    @Test fun `nearest first and nothing beyond limit`() {
        val r = DestinationSuggester.rank(pangyo, "city")
        assertEquals("북한산 국립공원", r.first().destination.name)
        assertTrue(r.zipWithNext().all { (a, b) -> a.distanceKm!! <= b.distanceKm!! })
        assertTrue(r.all { it.distanceKm!! <= DestinationSuggester.MAX_KM })
        assertTrue(r.none { it.destination.name == "해운대해수욕장" })   // 판교에서 300km 넘음
        assertTrue(r.none { it.destination.region == "city" })        // 지금 지역은 제안 안 함
    }

    @Test fun `near gangneung suggests local mountain not far coast`() {
        val r = DestinationSuggester.rank(gangneung, "coast")
        assertEquals("mountain", r.first().destination.region)
        assertTrue(r.none { it.destination.region == "coast" })
    }

    @Test fun `without position falls back to order`() {
        val r = DestinationSuggester.rank(null, "city")
        assertEquals("coast", r.first().destination.region)
        assertNull(r.first().distanceKm)
        assertFalse(r.first().unvisited)
    }

    @Test fun `unvisited list limits regions`() {
        val r = DestinationSuggester.rank(pangyo, "city", listOf("coast"))
        assertTrue(r.all { it.destination.region == "coast" && it.unvisited })
        assertEquals(NoSuggestion.ALL_VISITED, DestinationSuggester.why(pangyo, "city", emptyList()))
    }

    @Test fun `far from everything means none nearby`() {
        val dokdo = GeoPoint(37.24, 131.86)
        assertTrue(DestinationSuggester.rank(dokdo, null).isEmpty())
        assertEquals(NoSuggestion.NONE_NEARBY, DestinationSuggester.why(dokdo, null, null))
    }

    @Test fun `asking again offers next candidate then exhausts`() {
        val flow = DestinationFlow(now = { 0L })
        val total = DestinationSuggester.rank(pangyo, "city").size
        val first = flow.offer(pangyo, "city") as DestinationFlow.Offer.Made
        assertFalse(first.suggestion.alternative)
        val second = flow.offer(pangyo, "city") as DestinationFlow.Offer.Made
        assertTrue(second.suggestion.alternative)
        assertNotEquals(first.suggestion.destination, second.suggestion.destination)
        repeat(total - 2) { assertIs<DestinationFlow.Offer.Made>(flow.offer(pangyo, "city")) }
        assertEquals(DestinationFlow.Offer.None(NoSuggestion.EXHAUSTED), flow.offer(pangyo, "city"))
    }

    @Test fun `accept returns the latest offered destination once`() {
        val flow = DestinationFlow(now = { 0L })
        flow.offer(pangyo, "city")
        val second = (flow.offer(pangyo, "city") as DestinationFlow.Offer.Made).suggestion.destination
        assertEquals(second, flow.accept())
        assertNull(flow.accept())
    }

    @Test fun `accept keeps the offer when navi fails or a route is active`() {
        val flow = DestinationFlow(now = { 0L })
        val offered = (flow.offer(pangyo, "city") as DestinationFlow.Offer.Made).suggestion.destination
        assertEquals(AcceptResult.NaviNotReady, flow.accept(routeActive = false) { false })
        assertEquals(AcceptResult.RouteActive, flow.accept(routeActive = true) { error("내비를 부르면 안 된다") })
        assertEquals(AcceptResult.Started(offered), flow.accept(routeActive = false) { true })   // 남아 있던 제안
        assertEquals(AcceptResult.NoOffer, flow.accept(routeActive = false) { true })            // 한 번만
    }

    @Test fun `forged accept without a prior offer never reaches navi`() {
        val flow = DestinationFlow(now = { 0L })
        assertEquals(AcceptResult.NoOffer, flow.accept(routeActive = false) { error("내비를 부르면 안 된다") })
    }

    @Test fun `accept without offer or after ttl is rejected and ttl restarts ranking`() {
        assertNull(DestinationFlow().accept())
        var t = 0L
        val flow = DestinationFlow(now = { t }, ttlMs = 1_000)
        val first = (flow.offer(pangyo, "city") as DestinationFlow.Offer.Made).suggestion
        t = 1_001
        assertNull(flow.accept())
        t = 5_000
        val again = (flow.offer(pangyo, "city") as DestinationFlow.Offer.Made).suggestion
        assertEquals(first.destination, again.destination)
        assertFalse(again.alternative)
    }
}
