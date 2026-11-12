package ai.allo.car.model

/** Vehicle-local visual state. It never awards game progress or changes phone-owned state. */
data class DrivingMotionState(
    val speedKph: Double = 0.0,
    val playbackRate: Float = 0f,
    val brakeSerial: Long = 0,
    val brakeAtMs: Long? = null,
    val fresh: Boolean = false,
)

/** Sensor and receive times use Android's monotonic elapsed-realtime clock, in milliseconds. */
class DrivingMotionTracker {
    private var latestAt: Long? = null
    private var speed = 0.0
    private data class Sample(val timeMs: Long, val speedKph: Double)
    private val history = ArrayDeque<Sample>()
    private var sharpSince: Long? = null
    private var brakeSerial = 0L
    private var brakeAt: Long? = null
    private var lastBrakeAt: Long? = null
    private var braking = false
    private var settledAt: Long? = null

    @Synchronized
    fun accept(speedKph: Double, sampleTimeMs: Long, receivedAtMs: Long, gear: String): DrivingMotionState {
        // Old/duplicate delivery must neither rewind the character nor extend freshness.
        if (latestAt?.let { sampleTimeMs <= it } == true) return state(receivedAtMs, gear)
        if (gear != "D" || !speedKph.isFinite() || speedKph !in 0.0..400.0 ||
            receivedAtMs - sampleTimeMs !in 0 until STALE_MS) {
            invalidate()
            return state(receivedAtMs, gear)
        }
        if (latestAt?.let { sampleTimeMs - it >= STALE_MS } == true) invalidate()
        history.addLast(Sample(sampleTimeMs, speedKph))
        // Retain the predecessor of the 600ms horizon so 5Hz sampling still covers a
        // whole window; repeated/quantized speed values remain genuine observations.
        while (history.size > 2 && history.elementAt(1).timeMs <= sampleTimeMs - WINDOW_MS) history.removeFirst()
        val first = history.first()
        val span = sampleTimeMs - first.timeMs
        val decel = if (history.size >= 3 && span >= MIN_WINDOW_MS) {
            // Regression over the complete window suppresses bunched 1–2km/h steps.
            // A two-point derivative over 100ms mistakes ordinary quantized braking for a fall.
            val meanTime = history.sumOf { (it.timeMs - first.timeMs).toDouble() } / history.size
            val meanSpeed = history.sumOf { it.speedKph } / history.size
            val covariance = history.sumOf { ((it.timeMs - first.timeMs) - meanTime) * (it.speedKph - meanSpeed) }
            val variance = history.sumOf { val dt = (it.timeMs - first.timeMs) - meanTime; dt * dt }
            -covariance / variance * 1000.0
        } else null
        val sharp = decel != null && decel >= 12.0 - ROUNDING_EPSILON &&
            first.speedKph >= 10.0 && first.speedKph - speedKph >= 3.0 - ROUNDING_EPSILON
        if (sharp) {
            val since = sharpSince ?: sampleTimeMs.also { sharpSince = it }
            if (!braking && sampleTimeMs - since >= CONFIRM_MS &&
                (lastBrakeAt == null || receivedAtMs - lastBrakeAt!! >= COOLDOWN_MS)) {
                brakeSerial++
                brakeAt = receivedAtMs
                lastBrakeAt = receivedAtMs
                braking = true
                settledAt = null
            }
        } else sharpSince = null
        if (braking && decel != null) {
            if (decel <= 3.0) {
                val settled = settledAt ?: sampleTimeMs.also { settledAt = it }
                if (sampleTimeMs - settled >= SETTLE_MS) braking = false
            } else settledAt = null
        }
        latestAt = sampleTimeMs
        speed = speedKph
        return state(receivedAtMs, gear)
    }

    @Synchronized
    fun state(nowMs: Long, gear: String): DrivingMotionState {
        val sampleAt = latestAt
        if (gear != "D" || sampleAt == null || nowMs - sampleAt !in 0 until STALE_MS) {
            invalidate()
            return DrivingMotionState(brakeSerial = brakeSerial)
        }
        // A bounded cadence (0.55–1.8x); the renderer smooths rate changes without restarting a cycle.
        val rate = if (speed <= 0.8) 0f else (0.55 + speed / 80.0).coerceAtMost(1.8).toFloat()
        return DrivingMotionState(speed, rate, brakeSerial, brakeAt, fresh = true)
    }

    @Synchronized
    fun invalidate() {
        latestAt = null
        history.clear()
        sharpSince = null
        speed = 0.0
        brakeAt = null
        braking = false
        settledAt = null
        // Keep the serial and cooldown across disconnects so old events cannot replay.
    }

    companion object {
        const val STALE_MS = 1_500L
        private const val MIN_WINDOW_MS = 400L
        private const val WINDOW_MS = 600L
        private const val CONFIRM_MS = 100L
        // AAOS speed originates as Float m/s; tolerate its conversion error at inclusive bounds.
        private const val ROUNDING_EPSILON = 0.0001
        private const val COOLDOWN_MS = 2_000L
        private const val SETTLE_MS = 500L
    }
}
