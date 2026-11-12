package ai.allo.car.model

/** Paired phone liveness from advancing full snapshot revisions, never cross-device clocks. */
class FishingFreshness(private val ttlMs: Long = 5_000) {
    private var highestRevision = -1L
    private var receivedAt = -1L
    private var connected = false

    fun observe(revision: Long?, nowMs: Long): Boolean {
        if (revision == null || revision < 0 || nowMs < 0 || revision < highestRevision) {
            connected = false
            return false
        }
        if (revision > highestRevision) {
            highestRevision = revision
            receivedAt = nowMs
            connected = true
        }
        return isFresh(nowMs)
    }
    fun isFresh(nowMs: Long): Boolean = connected && receivedAt >= 0 && nowMs >= receivedAt &&
        nowMs - receivedAt < ttlMs
    fun disconnect() { connected = false }
}
