package ai.allo.car.ui

/** Artwork identities only. Never aliases or changes saved gameplay species IDs. */
object SuppliedCharacters {
    val ids = setOf("breeze_wyrm", "cloud_strider", "dewcap", "dune_roller", "ember_crab", "highway_comet", "lamp_moth", "pebble_orbit", "puddle_pip", "road_sprout", "sea_mist", "storm_lantern")
    fun path(id: String?, pose: PetPose): String? {
        if (id !in ids) return null
        val file = when (pose) {
            PetPose.Move -> "move"
            PetPose.Sleep -> "sleep"
            PetPose.Fall -> "surprised"
            else -> "idle"
        }
        return "supplied/$id/$file.png"
    }
}
