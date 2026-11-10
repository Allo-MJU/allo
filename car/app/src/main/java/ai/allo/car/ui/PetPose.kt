package ai.allo.car.ui

/** Visual poses only; these never change the phone's game state. */
enum class PetPose(val label: String, val asset: String) {
    Idle("쉬는 모습", "idle"),
    Move("함께 달리는 모습", "move"),
    Sleep("잠자는 모습", "sleep"),
    Fishing("낚시하는 모습", "idle"),
}

object PetPoses {
    // The other six design characters do not match the current game catalog yet.
    private val supplied = setOf("road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist")
    fun assetPath(speciesId: String?, pose: PetPose): String? =
        speciesId?.takeIf { it in supplied }?.let { "poses/$it/${pose.asset}.png" }

    fun animates(pose: PetPose, parked: Boolean, connected: Boolean, resumed: Boolean, motionEnabled: Boolean): Boolean =
        parked && connected && resumed && motionEnabled && pose in setOf(PetPose.Sleep, PetPose.Fishing)
}
