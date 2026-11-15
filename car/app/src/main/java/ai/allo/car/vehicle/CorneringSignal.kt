package ai.allo.car.vehicle

import ai.allo.car.model.Cornering
import kotlin.math.abs

/** Display-only steering cue, not physical road curvature. No raw angle leaves the car. */
class CorneringSignal(private val clock: () -> Long = System::currentTimeMillis) {
    data class Read(val sequence: Long, val epoch: Long, val startedAtMs: Long)
    private var epoch = 0L
    private var sequence = 0L
    private var completed = 0L
    private var angle: Double? = null
    private var receivedAt = 0L

    @Synchronized
    fun accept(degrees: Double?, receivedAtMs: Long) {
        if (degrees == null || !degrees.isFinite() || abs(degrees) > 1080.0 || receivedAtMs <= 0) {
            invalidate()
            return
        }
        angle = degrees
        receivedAt = receivedAtMs
    }

    @Synchronized
    fun invalidate() { epoch++; angle = null; receivedAt = 0 }

    @Synchronized
    fun receive(degrees: Double?) {
        epoch++ // Listener observations supersede all outstanding getter requests.
        accept(degrees, clock())
    }

    @Synchronized
    fun beginRead(): Read = Read(++sequence, epoch, clock())

    @Synchronized
    fun completeRead(read: Read, degrees: Double?) {
        val now = clock()
        if (read.epoch != epoch || read.sequence <= completed || now < read.startedAtMs ||
            now - read.startedAtMs > 2500L) return
        completed = read.sequence
        accept(degrees, now)
    }

    @Synchronized
    fun failRead(read: Read) {
        if (read.epoch == epoch && read.sequence > completed) invalidate()
    }

    @Synchronized
    fun snapshotCurrent(gear: String, speedKph: Double, supported: Boolean, speedFresh: Boolean): Cornering? =
        snapshot(clock(), gear, speedKph, supported, speedFresh)

    @Synchronized
    fun snapshot(nowMs: Long, gear: String, speedKph: Double, supported: Boolean,
                 speedFresh: Boolean): Cornering? {
        val degrees = angle ?: return null
        if (!supported || !speedFresh || gear != "D" || !speedKph.isFinite() ||
            speedKph <= 2.0 || speedKph > 400.0 || nowMs < receivedAt || nowMs - receivedAt > 2500L) return null
        // VC +120 was observed as SDK -120. Real-vehicle left/right calibration is unverified.
        val bend = if (abs(degrees) <= 3.0) 0.0 else (-degrees / 120.0).coerceIn(-1.0, 1.0)
        return Cornering(bend = bend, receivedAtMs = receivedAt)
    }
}
