package ai.allo.car.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp

/** Each collected identity uses its own supplied walking sheet or gameplay action atlas. */
internal object PlazaWalkArt {
    val existing = setOf("road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist")
    fun spec(id: String?): PetSpriteSpec? = id?.takeIf { it in SuppliedCharacters.ids }?.let {
        PetSpriteSpec(if (it in existing) "poses/$it/run-sheet.png" else "plaza_walk/$it/walk.png",
            frameMs = 160, timeline = (0..7).toList(), alphaCutoff = 32)
    } ?: PetSpriteSheets.forDisplay(id, PetPose.Move, parked = false, runningMotion = true)
    fun mirror(id: String?, moving: Boolean, facingLeft: Boolean): Boolean {
        val sourceLeft = id in if (moving) setOf("road_sprout", "puddle_pip", "dune_roller") else setOf("road_sprout", "puddle_pip", "dune_roller")
        return sourceLeft != facingLeft
    }
}

@Composable
internal fun PlazaPetArt(summary: PetSummary, size: Dp, modifier: Modifier, connected: Boolean, moving: Boolean,
    facingLeft: Boolean? = null) {
    val allowed = moving && ambientMotionAllowed(PetPose.Move, false, connected, true)
    val spec = PlazaWalkArt.spec(summary.species?.id)
    val sheet = rememberPetSpriteSheet(spec)
    val walking = allowed && sheet != null && spec != null
    val oriented = modifier.graphicsLayer {
        scaleX = if (facingLeft != null && PlazaWalkArt.mirror(summary.species?.id, walking, facingLeft)) -1f else 1f
    }
    if (walking) PetSpriteSheet(sheet!!, spec!!, true, "${summary.title} 산책", size, oriented)
    else PetArt(summary, size, oriented, pose = PetPose.Idle, connected = connected)
}
