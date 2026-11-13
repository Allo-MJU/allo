package ai.allo.car.ui

/** Normalized anchors for 4x2 fishing sheets; no asset mirroring. */
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
            // Measured source-cell anchors transformed by the new sheets' 8% render inset.
            "breeze_wyrm" to FishingSceneProfile(true, 0.416f, 0.832f, 0.462f, true,
                contacts(0 to p(0.814f,0.779f), 1 to p(0.812f,0.774f), 6 to p(0.809f,0.738f), 7 to p(0.818f,0.780f))),
            "cloud_strider" to FishingSceneProfile(true, 0.433f, 0.794f, 0.462f, false,
                contacts(0 to p(0.818f,0.764f), 1 to p(0.815f,0.770f), 6 to p(0.801f,0.760f), 7 to p(0.802f,0.765f))),
            "dewcap" to FishingSceneProfile(true, 0.416f, 0.823f, 0.538f, false,
                contacts(0 to p(0.802f,0.794f), 1 to p(0.797f,0.786f), 6 to p(0.803f,0.801f), 7 to p(0.801f,0.787f))),
            "dune_roller" to FishingSceneProfile(false, 0.601f, 0.787f, 0.580f, false,
                contacts(0 to p(0.151f,0.789f), 1 to p(0.156f,0.789f), 6 to p(0.151f,0.787f), 7 to p(0.150f,0.787f))),
            "ember_crab" to FishingSceneProfile(true, 0.433f, 0.789f, 0.538f, false,
                contacts(0 to p(0.836f,0.771f), 1 to p(0.836f,0.777f), 6 to p(0.828f,0.768f), 7 to p(0.828f,0.786f))),
            "pebble_orbit" to FishingSceneProfile(true, 0.441f, 0.832f, 0.420f, true,
                contacts(0 to p(0.837f,0.786f), 1 to p(0.821f,0.804f), 7 to p(0.835f,0.787f))),
        )
        fun forSpecies(id: String?): FishingSceneProfile? = all[id]
    }
}
