package ai.allo.car.ui

/** Visual poses only; these never change the phone's game state. */
enum class PetPose(val label: String, val asset: String) {
    Idle("쉬는 모습", "idle"),
    Move("함께 달리는 모습", "move"),
    Fall("넘어졌다 일어나는 모습", "idle"),
    Sleep("잠자는 모습", "sleep"),
    Fishing("낚시하는 모습", "idle"),
}

object PetPoses {
    // The other six design characters do not match the current game catalog yet.
    private val supplied = setOf("road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist")
    fun assetPath(speciesId: String?, pose: PetPose): String? =
        speciesId?.takeIf { it in supplied }?.let { "poses/$it/${pose.asset}.png" }

    fun animates(pose: PetPose, parked: Boolean, connected: Boolean, resumed: Boolean, motionEnabled: Boolean, runningMotion: Boolean = false): Boolean =
        connected && resumed && motionEnabled && (
            parked && pose in setOf(PetPose.Sleep, PetPose.Fishing) || !parked && runningMotion && pose in setOf(PetPose.Move, PetPose.Fall)
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
