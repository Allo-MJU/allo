package ai.allo.car.mirror

/** Monotonic-clock policy, independent from Android/network/UI. All calls are on the UI thread. */
class MirrorDisplayPolicy {
    var generation = 0L
        private set
    private var verifiedAt = -1L
    private var safe = false

    fun update(connected: Boolean, foreground: Boolean, parked: Boolean?, uxAllowed: Boolean?, now: Long) {
        val next = connected && foreground && parked == true && uxAllowed == true
        if (!next || !safe) generation++
        safe = next
        verifiedAt = now
    }

    fun invalidate() { generation++ }

    fun allowed(now: Long): Boolean = safe && verifiedAt >= 0 &&
        now >= verifiedAt && now - verifiedAt < VEHICLE_MAX_AGE_MS

    fun accepts(ticket: Long, ageMs: Long, requestAt: Long, now: Long): Boolean =
        ticket == generation && allowed(now) && remainingMs(ageMs, requestAt, now) > 0

    companion object {
        const val VEHICLE_MAX_AGE_MS = 1000L
        const val FRAME_MAX_AGE_MS = 1500L

        fun remainingMs(ageMs: Long, requestAt: Long, now: Long): Long {
            if (ageMs < 0 || ageMs >= FRAME_MAX_AGE_MS || now < requestAt) return 0
            val elapsed = now - requestAt
            if (elapsed < 0 || elapsed >= FRAME_MAX_AGE_MS - ageMs) return 0
            return FRAME_MAX_AGE_MS - ageMs - elapsed
        }
    }
}
