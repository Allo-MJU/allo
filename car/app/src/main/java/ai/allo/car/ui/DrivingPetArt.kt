package ai.allo.car.ui

import android.os.SystemClock
import androidx.compose.runtime.*
import androidx.compose.ui.unit.Dp
import ai.allo.car.model.DrivingMotionState

/** Sensor speed changes the accumulated frame clock, never restarts the running cycle. */
@Composable
internal fun DrivingPetArt(summary: PetSummary, size: Dp, motion: DrivingMotionState,
                           connected: Boolean, runningMotion: Boolean) {
    val allowed = ambientMotionAllowed(PetPose.Move, false, connected, runningMotion) && motion.fresh
    val currentMotion by rememberUpdatedState(motion)
    val timeline = remember(summary.species?.id) { DrivingPetTimeline() }
    var frame by remember(summary.species?.id) { mutableStateOf(DrivingPetFrame()) }
    LaunchedEffect(timeline, allowed) {
        if (!allowed) {
            frame = timeline.frame(SystemClock.elapsedRealtime(), currentMotion, false)
        } else {
            while (true) {
                withFrameNanos {
                    frame = timeline.frame(SystemClock.elapsedRealtime(), currentMotion, true)
                }
            }
        }
    }
    // Gate immediately, before the effect runs, to avoid a stale falling pose on disconnect.
    val visible = if (allowed) frame else DrivingPetFrame()
    PetArt(summary, size, pose = visible.pose, connected = connected,
        runningMotion = runningMotion && allowed, elapsedMs = visible.elapsedMs)
}
