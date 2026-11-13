package ai.allo.car.ui

import ai.allo.car.model.PleosRoute

/** Visual poses only; these never change the phone's game state. */
enum class PetPose(val label: String, val asset: String) {
    Idle("쉬는 모습", "idle"),
    Move("함께 달리는 모습", "move"),
    Fall("넘어졌다 일어나는 모습", "idle"),
    Sleep("잠자는 모습", "sleep"),
    Fishing("낚시하는 모습", "idle"),
}

object PetPoses {
    /** A restricted Driving route alone is not proof of an active drive. */
    fun forRoute(route: PleosRoute, connected: Boolean, drivingSignalFresh: Boolean = false): PetPose = when {
        route == PleosRoute.Driving && connected && drivingSignalFresh -> PetPose.Fishing
        route in setOf(PleosRoute.Home, PleosRoute.Paused, PleosRoute.Ended) -> PetPose.Sleep
        else -> PetPose.Idle
    }

    fun assetPath(speciesId: String?, pose: PetPose): String? = SuppliedCharacters.path(speciesId, pose)

    fun animates(pose: PetPose, parked: Boolean, connected: Boolean, resumed: Boolean, motionEnabled: Boolean, runningMotion: Boolean = false, drivingFishing: Boolean = false): Boolean =
        connected && resumed && motionEnabled && (
            parked && pose in setOf(PetPose.Sleep, PetPose.Fishing) ||
                !parked && drivingFishing && pose == PetPose.Fishing ||
                !parked && runningMotion && pose in setOf(PetPose.Move, PetPose.Fall)
        )
}


enum class FishingStage { Waiting, Lifting, Caught, Escaping, Splash }

data class PetMotion(
    val breathe: Float = 0f,
    val bounce: Float = 0f,
    val stage: FishingStage = FishingStage.Waiting,
    val lift: Float = 0f,
    val fish: Boolean = false,
    val escape: Float = 0f,
    val splash: Float = 0f,
)

/** Normalized choreography: no random timers, no game-state mutation. */
fun petMotion(phase: Float, enabled: Boolean): PetMotion {
    if (!enabled) return PetMotion()
    val p = phase.takeIf { it.isFinite() }?.coerceIn(0f, 1f) ?: 0f
    val breath = ((1.0 - kotlin.math.cos(p * 2.0 * Math.PI)) * .5).toFloat()
    val bounce = kotlin.math.sin(p * Math.PI).toFloat().coerceAtLeast(0f)
    return when {
        p < .32f -> PetMotion(breath, bounce)
        p < .52f -> PetMotion(breath, bounce, FishingStage.Lifting, (p - .32f) / .20f, true)
        p < .68f -> PetMotion(breath, bounce, FishingStage.Caught, 1f, true)
        p < .85f -> PetMotion(breath, bounce, FishingStage.Escaping, 1f, true, (p - .68f) / .17f)
        else -> PetMotion(breath, bounce, FishingStage.Splash, (1f - p) / .15f, false, 1f, (p - .85f) / .15f)
    }
}
