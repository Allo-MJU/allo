package ai.allo.car.ui

/** Normalized anchors measured against each original 4x2 fishing sheet; no asset mirroring. */
internal data class FishingContact(val x: Float, val y: Float)
internal data class FishingSceneProfile(
    val castsRight: Boolean, val bodyX: Float, val groundY: Float,
    val shadowWidth: Float, val hovering: Boolean,
    val contacts: Map<Int, FishingContact>,
) {
    companion object {
        private fun contacts(vararg points: Pair<Int, FishingContact>) = mapOf(*points)
        private fun p(x: Float, y: Float) = FishingContact(x, y)
        val all = mapOf(
            "road_sprout" to FishingSceneProfile(false, .62f, .90f, .62f, false,
                contacts(0 to p(.093f,.85f), 1 to p(.06f,.85f), 6 to p(.093f,.84f), 7 to p(.093f,.84f))),
            "puddle_pip" to FishingSceneProfile(false, .60f, .88f, .60f, false,
                contacts(0 to p(.075f,.70f), 1 to p(.075f,.70f), 6 to p(.075f,.72f), 7 to p(.075f,.72f))),
            "lamp_moth" to FishingSceneProfile(true, .48f, .94f, .42f, true,
                contacts(0 to p(.86f,.82f), 1 to p(.85f,.82f), 6 to p(.85f,.80f), 7 to p(.86f,.82f))),
            "storm_lantern" to FishingSceneProfile(true, .47f, .86f, .64f, false,
                contacts(0 to p(.88f,.79f), 1 to p(.88f,.82f), 6 to p(.84f,.81f), 7 to p(.86f,.80f))),
            "highway_comet" to FishingSceneProfile(true, .51f, .86f, .57f, false,
                contacts(0 to p(.89f,.74f), 1 to p(.87f,.73f), 6 to p(.86f,.69f), 7 to p(.86f,.73f))),
            "sea_mist" to FishingSceneProfile(false, .57f, .98f, .43f, true,
                contacts(0 to p(.095f,.70f), 1 to p(.14f,.70f), 6 to p(.14f,.66f), 7 to p(.105f,.70f))),
        )
        fun forSpecies(id: String?): FishingSceneProfile? = all[id]
    }
}
