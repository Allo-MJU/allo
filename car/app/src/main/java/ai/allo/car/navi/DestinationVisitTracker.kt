package ai.allo.car.navi

import ai.allo.car.gleo.DestinationSuggester
import ai.allo.car.gleo.Destination
import ai.allo.car.vehicle.GeoPoint
import kotlinx.serialization.Serializable
import java.security.MessageDigest
import java.util.UUID

private fun digest(s: String) = MessageDigest.getInstance("SHA-256").digest(s.toByteArray(Charsets.UTF_8))
    .take(8).joinToString("") { "%02x".format(it) }

@Serializable
data class DestinationVisit(val sessionId: String, val visitId: String, val routeRevision: String,
    val placeId: String, val placeName: String, val regionTag: String, val arrivedAtMs: Long,
    val companionIds: List<String>)

/** Keeps correlation only in memory: after restart an uncorrelated arrival cannot become a visit. */
class DestinationVisitTracker(private val elapsedMs: () -> Long = { System.nanoTime() / 1_000_000 },
    private val newRevision: () -> String = { "route_" + UUID.randomUUID().toString().replace("-", "") }) {
    private data class Route(val session: String, val revision: String, val name: String, val key: String, val placeId: String, val region: String)
    private var session: String? = null
    private var revision: String? = null
    private var route: Route? = null
    private var requested: Destination? = null
    private var candidate: Destination? = null
    private var endedAt: Long? = null
    @Synchronized fun expect(destination: Destination) { requested = destination }
    @Synchronized fun start(sessionId: String) {
        session = sessionId; revision = newRevision(); route = null; endedAt = null
        candidate = requested; requested = null
    }
    @Synchronized fun end() { if (route != null && endedAt == null) endedAt = elapsedMs() }
    @Synchronized fun cancel() { session = null; revision = null; route = null; requested = null; candidate = null; endedAt = null }
    @Synchronized fun destination(sessionId: String, name: String?, provider: String?, poi: String?, sub: String?, lat: Double, lon: Double) {
        if (session != sessionId || name.isNullOrBlank() || endedAt != null) return
        val key = listOf(name, provider.orEmpty(), poi.orEmpty(), sub.orEmpty(), lat.toString(), lon.toString()).joinToString("\n")
        if (route?.key == key) return
        if (route != null) { revision = newRevision(); candidate = null }
        val rev = revision ?: return
        val requestedMatch = candidate?.takeIf {
            it.name == name && lat.isFinite() && lon.isFinite() && GeoPoint(lat, lon).kmTo(it.point) < 0.5
        }
        candidate = null
        val catalog = requestedMatch ?: DestinationSuggester.CANDIDATES.singleOrNull {
            it.name == name && lat.isFinite() && lon.isFinite() && GeoPoint(lat, lon).kmTo(it.point) < 0.1
        }
        val place = catalog?.placeId ?: if (!provider.isNullOrBlank() && !poi.isNullOrBlank())
            "poi_" + digest(listOf(provider, poi, sub.orEmpty()).joinToString("\n")) else "unknown_" + digest("$sessionId\n$rev")
        route = Route(sessionId, rev, name, key, place, catalog?.region ?: "unknown")
    }
    @Synchronized fun arrive(sessionId: String, name: String?, at: Long, companions: List<String>): DestinationVisit? {
        val r = route ?: return null
        if (r.session != sessionId || name.isNullOrBlank() || name != r.name || at <= 0) return null
        val ended = endedAt
        if (ended != null && elapsedMs() - ended !in 0..30_000) { cancel(); return null }
        cancel()
        return DestinationVisit(sessionId, "visit_" + digest("$sessionId\n${r.revision}"), r.revision,
            r.placeId, r.name, r.region, at, companions)
    }
}
