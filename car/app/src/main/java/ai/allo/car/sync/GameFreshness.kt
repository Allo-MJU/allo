package ai.allo.car.sync

/** Advancing phone timestamps establish liveness; replayed snapshots never renew it. */
class GameFreshness(
    private val ttlMs: Long = 15_000,
    private val futureSkewMs: Long = 5_000,
) {
    private var highestSourceTs = 0L
    private var receivedAt = -1L
    private var connected = false

    @Synchronized fun observe(sourceTs: Long, wallNow: Long, monotonicNow: Long): Boolean {
        if (sourceTs <= 0 || monotonicNow < 0 ||
            sourceTs > wallNow && sourceTs - wallNow > futureSkewMs ||
            sourceTs <= wallNow && wallNow - sourceTs >= ttlMs || sourceTs < highestSourceTs) {
            connected = false
            return false
        }
        if (sourceTs > highestSourceTs) {
            highestSourceTs = sourceTs
            receivedAt = monotonicNow
            connected = true
        }
        return isFresh(monotonicNow)
    }

    @Synchronized fun isFresh(monotonicNow: Long): Boolean = connected && receivedAt >= 0 &&
        monotonicNow >= receivedAt && monotonicNow - receivedAt < ttlMs

    @Synchronized fun disconnect() { connected = false }
}
