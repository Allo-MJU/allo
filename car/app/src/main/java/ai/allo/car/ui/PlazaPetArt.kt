package ai.allo.car.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp

/** Additional authored art is scoped to the plaza; fishing and phone artwork stay unchanged. */
internal val plazaAtlases = listOf("bridge_hopper", "mountain_sprite", "river_glider", "tide_keeper", "tunnel_moth", "star_owl")
    .associateWith { PetSpriteSpec("plaza/$it/actions.png", 120, (0..7).toList(), rows = 6, alphaCutoff = 32) }

@Composable
internal fun PlazaPetArt(summary: PetSummary, size: Dp, modifier: Modifier, connected: Boolean, moving: Boolean) {
    val spec = plazaAtlases[summary.species?.id]
    val sheet = rememberPetSpriteSheet(spec)
    if (spec != null && sheet != null) {
        PetSpriteSheet(sheet, spec, moving, summary.title, size, modifier)
    } else {
        PetArt(summary, size, modifier, pose = if (moving) PetPose.Move else PetPose.Idle,
            connected = connected, runningMotion = moving)
    }
}
