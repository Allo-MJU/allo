package ai.allo.car.ui

import ai.allo.car.model.DrivingMotionState
import kotlin.math.exp

/** Visual-only state: never writes vehicle signals or the phone's game state. */
data class DrivingPetFrame(val pose: PetPose = PetPose.Idle, val elapsedMs: Long = 0)

class DrivingPetTimeline {
    private var previousMs: Long? = null
    private var observedBrake = 0L
    private var fallStartedMs: Long? = null
    private var runElapsed = 0.0
    private var rate = 0.0

    fun frame(nowMs: Long, motion: DrivingMotionState, enabled: Boolean): DrivingPetFrame {
        if (!enabled || !motion.fresh) {
            previousMs = null
            observedBrake = motion.brakeSerial
            fallStartedMs = null
            runElapsed = 0.0
            rate = 0.0
            return DrivingPetFrame()
        }
        val previous = previousMs
        previousMs = nowMs
        if (previous == null) observedBrake = motion.brakeSerial
        if (motion.brakeSerial != observedBrake) {
            observedBrake = motion.brakeSerial
            motion.brakeAtMs?.takeIf { nowMs - it in 0..300 }?.let { fallStartedMs = it }
        }
        fallStartedMs?.let { start ->
            val elapsed = (nowMs - start).coerceAtLeast(0)
            if (elapsed < PetSpriteSheets.fall.durationMs) return DrivingPetFrame(PetPose.Fall, elapsed)
            fallStartedMs = null
            runElapsed = 0.0
            rate = 0.0
        }
        val target = motion.playbackRate.takeIf { it.isFinite() }?.coerceIn(0f, 1.8f)?.toDouble() ?: 0.0
        if (target <= 0.0) {
            rate = 0.0
            return DrivingPetFrame()
        }
        val dt = if (previous == null) 0L else (nowMs - previous).coerceIn(0, 100)
        rate += (target - rate) * (1.0 - exp(-dt / 200.0))
        runElapsed += dt * rate
        return DrivingPetFrame(PetPose.Move, runElapsed.toLong())
    }
}
