package ai.allo.car.sync

import ai.allo.car.model.SessionMeta

internal suspend fun FirebaseSessionApi.renewOrCheckExpired(
    sessionId: String, meta: SessionMeta, requestId: String, now: Long,
): SessionMeta? = try {
    renew(sessionId, meta.carAppVersion, requestId)
} catch (unavailable: SessionUnavailableException) {
    if (meta.paired || !pairingSessionExpired(meta, now)) throw unavailable
    // Idempotent create reads authoritative pairing state before replacing a locally expired session.
    val current = try { create(sessionId, meta.carAppVersion) }
    catch (_: SessionUnavailableException) { null }
    if (current != null && !current.paired) throw unavailable
    current
}

internal fun canReplaceExpiredPairing(
    requestedId: String, currentId: String, meta: SessionMeta, now: Long, parked: Boolean, ended: Boolean,
): Boolean = requestedId == currentId && !meta.paired && parked && !ended && pairingSessionExpired(meta, now)

private fun pairingSessionExpired(meta: SessionMeta, now: Long): Boolean =
    meta.createdAt > 0 && now >= meta.createdAt && now - meta.createdAt >= 24 * 60 * 60 * 1_000L
