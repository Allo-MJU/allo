package ai.allo.car.gleo

import ai.allo.car.navi.Guidance
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
        assertFalse(r.first().uncollected)
    }

    private fun known(vararg r: String) = RegionSummary.Known(r.toSet())

    @Test fun `uncollected summary limits regions`() {
        val r = DestinationSuggester.rank(pangyo, "city", known("coast"))
        assertTrue(r.isNotEmpty() && r.all { it.destination.region == "coast" && it.uncollected })
    }

    @Test fun `no suggestion reasons are distinguished`() {
        assertEquals(NoSuggestion.ALL_COLLECTED, DestinationSuggester.why("city", known()))
        assertTrue(DestinationSuggester.rank(pangyo, "city", known()).isEmpty())
        assertTrue(DestinationSuggester.rank(pangyo, "city", known("city")).isEmpty())
        assertEquals(NoSuggestion.ONLY_CURRENT_REGION, DestinationSuggester.why("city", known("city")))
        val dokdo = GeoPoint(37.2426, 131.8669)
        assertTrue(DestinationSuggester.rank(dokdo, null).isEmpty())
        assertEquals(NoSuggestion.NONE_NEARBY, DestinationSuggester.why(null, RegionSummary.Unknown))
        assertEquals(NoSuggestion.NONE_NEARBY, DestinationSuggester.why(null, known("coast")))
    }

    @Test fun `all collected is not turned back into a default suggestion`() {
        val flow = DestinationFlow()
        assertEquals(DestinationFlow.Offer.None(NoSuggestion.ALL_COLLECTED), flow.offer(pangyo, "city", known()))
    }

    @Test fun `accept rechecks the offer right before navi`() {
        val flow = DestinationFlow()
        flow.offer(pangyo, "city", known("coast"))
        assertEquals(AcceptResult.NoOffer, flow.accept(Guidance.IDLE, stillValid = { false }) { error("내비를 부르면 안 된다") })
        assertEquals(AcceptResult.NoOffer, flow.accept(Guidance.IDLE) { true })   // 무효가 된 제안은 버려진다
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
        assertEquals(AcceptResult.NaviNotReady, flow.accept(Guidance.IDLE) { false })
        assertEquals(AcceptResult.RouteActive, flow.accept(Guidance.GUIDING) { error("내비를 부르면 안 된다") })
        assertEquals(AcceptResult.NaviNotReady, flow.accept(Guidance.UNKNOWN) { error("내비를 부르면 안 된다") })   // 상태 미확인
        assertEquals(AcceptResult.Started(offered), flow.accept(Guidance.IDLE) { true })   // 남아 있던 제안
        assertEquals(AcceptResult.NoOffer, flow.accept(Guidance.IDLE) { true })            // 한 번만
    }

    @Test fun `ROUTE_DRIVE without ETA still blocks the route change`() {
        // 리뷰 사례: ROUTE_DRIVE 는 받았고 남은 시간(onDestinationInfo)은 아직 → ETA 는 null 이지만 안내 중
        assertNull(ai.allo.car.navi.NaviEta.etaSec("ROUTE_DRIVE", null))
        val g = Guidance.fromStatus("ROUTE_DRIVE")
        assertEquals(Guidance.GUIDING, g)
        val flow = DestinationFlow(now = { 0L })
        flow.offer(pangyo, "city")
        assertEquals(AcceptResult.RouteActive, flow.accept(g) { error("내비를 부르면 안 된다") })
    }

    @Test fun `same destination offered after reset still invalidates earlier voice reply`() {
        val flow = DestinationFlow(now = { 0L })
        val original = (flow.offer(pangyo, "city") as DestinationFlow.Offer.Made).suggestion.destination
        val capturedRevision = flow.revision
        flow.reset()
        val replacement = (flow.offer(pangyo, "city") as DestinationFlow.Offer.Made).suggestion.destination
        assertEquals(original, replacement)
        assertNotEquals(capturedRevision, flow.revision)
    }

    @Test fun `consumed or replaced offer invalidates recognition but failed route remains retryable`() {
        val flow = DestinationFlow(now = { 0L })
        flow.offer(pangyo, "city")
        val initial = flow.revision
        assertEquals(AcceptResult.NaviNotReady, flow.accept(Guidance.UNKNOWN) { error("No navigation") })
        assertEquals(initial, flow.revision)
        flow.offer(pangyo, "city")
        val alternative = flow.revision
        assertNotEquals(initial, alternative)
        assertIs<AcceptResult.Started>(flow.accept(Guidance.IDLE) { true })
        assertNotEquals(alternative, flow.revision)
        assertNull(flow.pending())
    }

    @Test fun `guidance mapping`() {
        assertEquals(Guidance.IDLE, Guidance.fromStatus("FREE_DRIVE"))
        assertEquals(Guidance.UNKNOWN, Guidance.fromStatus("INITIALIZING"))
        assertEquals(Guidance.UNKNOWN, Guidance.fromStatus("INACTIVE"))
        assertEquals(Guidance.UNKNOWN, Guidance.fromStatus(null))
        assertEquals(Guidance.GUIDING, Guidance.fromNaviMode("ROUTE_GUIDING"))
        assertEquals(Guidance.GUIDING, Guidance.fromNaviMode("SIMULATION_GUIDING"))
        assertEquals(Guidance.IDLE, Guidance.fromNaviMode("SAFE_GUIDING"))
        assertEquals(Guidance.IDLE, Guidance.fromNaviMode("NOT_WORKING"))
    }

    @Test fun `forged accept without a prior offer never reaches navi`() {
        val flow = DestinationFlow(now = { 0L })
        assertEquals(AcceptResult.NoOffer, flow.accept(Guidance.IDLE) { error("내비를 부르면 안 된다") })
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
