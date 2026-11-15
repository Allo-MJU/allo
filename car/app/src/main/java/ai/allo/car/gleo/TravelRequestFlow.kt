package ai.allo.car.gleo

import ai.allo.car.model.TravelRequest
import ai.allo.car.navi.Guidance
import ai.allo.car.vehicle.GeoPoint

/**
 * Explicit phone travel requests, separate from collection recommendations.
 * No location, offer or SDK result is treated as a completed visit or published as an event.
 * Call [update] on context transitions, including disconnect/reconnect, even while the screen is hidden.
 */
class TravelRequestFlow(
    private val now: () -> Long = System::currentTimeMillis,
    private val ttlMs: Long = 120_000L,
) {
    data class Context(
        val sessionId: String?,
        val connected: Boolean,
        val ended: Boolean,
        val hasV2Contract: Boolean,
        val request: TravelRequest?,
        val currentRegion: String?,
        val parked: Boolean,
    )

    enum class Reason {
        UNAVAILABLE, UNSUPPORTED_CONTRACT, NO_REQUEST, INVALID_REQUEST, PARK_REQUIRED,
        CONFIRM_VISIT_ON_PHONE, NONE_NEARBY,
    }

    sealed interface Offer {
        data class Made(val token: Long, val suggestions: List<Suggestion>) : Offer
        data class None(val reason: Reason) : Offer
    }

    private data class Pending(val token: Long, val suggestions: List<Suggestion>, val at: Long)
    private var context: Context? = null
    private var pending: Pending? = null
    private var nextToken = 0L

    /** A return to the same context does not resurrect an earlier proposal. */
    @Synchronized
    fun update(context: Context) {
        if (this.context != context) pending = null
        this.context = context
    }

    @Synchronized
    fun reset() {
        context = null
        pending = null
    }

    @Synchronized
    fun offer(context: Context, here: GeoPoint?): Offer {
        update(context)
        pending = null
        unavailableReason(context)?.let { return Offer.None(it) }
        val target = context.request!!.targetRegion
        // Reuse the fixed POIs and the same straight-line distance calculation/limit.
        // Collection history deliberately does not participate in this selection.
        val pool = DestinationSuggester.CANDIDATES.filter { it.region == target && (context.request.targetPlaceId == null || it.placeId == context.request.targetPlaceId) }
        val suggestions = if (here == null) {
            pool.take(3).map { Suggestion(it, uncollected = false) }
        } else {
            pool.map { it to here.kmTo(it.point) }
                .filter { (_, km) -> km.isFinite() && km <= DestinationSuggester.MAX_KM }
                .sortedBy { (_, km) -> km }.take(3)
                .map { (destination, km) -> Suggestion(destination, uncollected = false, distanceKm = km) }
        }
        if (suggestions.isEmpty()) return Offer.None(Reason.NONE_NEARBY)
        val token = ++nextToken
        pending = Pending(token, suggestions.toList(), now())
        return Offer.Made(token, suggestions.toList())
    }

    /**
     * Pass the current session/request/vehicle snapshot immediately before the SDK call.
     * [AcceptResult.Started] is shared with legacy recommendations: here it means only
     * routeRequestAccepted, never confirmed guidance, arrival, or wish completion.
     */
    @Synchronized
    fun accept(
        token: Long,
        index: Int,
        context: Context,
        guidance: Guidance,
        request: (Destination) -> Boolean,
    ): AcceptResult {
        update(context)
        if (unavailableReason(context) != null) { pending = null; return AcceptResult.NoOffer }
        val offered = pending ?: return AcceptResult.NoOffer
        val age = now() - offered.at
        if (age < 0 || age > ttlMs) { pending = null; return AcceptResult.NoOffer }
        if (offered.token != token) return AcceptResult.NoOffer
        val destination = offered.suggestions.getOrNull(index)?.destination ?: return AcceptResult.NoOffer
        if (destination.region != context.request?.targetRegion) { pending = null; return AcceptResult.NoOffer }
        when (guidance) {
            Guidance.GUIDING -> return AcceptResult.RouteActive
            Guidance.UNKNOWN -> return AcceptResult.NaviNotReady
            Guidance.IDLE -> Unit
        }
        val accepted = try { request(destination) } catch (_: Exception) { false }
        if (!accepted) return AcceptResult.NaviNotReady
        // Do not erase a newer offer if a synchronous SDK callback updated the flow.
        if (pending?.token == offered.token) pending = null
        return AcceptResult.Started(destination)
    }

    private fun unavailableReason(context: Context): Reason? = when {
        context.sessionId.isNullOrBlank() || !context.connected || context.ended -> Reason.UNAVAILABLE
        !context.hasV2Contract -> Reason.UNSUPPORTED_CONTRACT
        context.request == null -> Reason.NO_REQUEST
        context.request.wishId.isBlank() || context.request.targetRegion !in DestinationSuggester.ORDER -> Reason.INVALID_REQUEST
        !context.parked -> Reason.PARK_REQUIRED
        context.request.targetPlaceId == null && context.currentRegion == context.request.targetRegion -> Reason.CONFIRM_VISIT_ON_PHONE
        else -> null
    }
}
