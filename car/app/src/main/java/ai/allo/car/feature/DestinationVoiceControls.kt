package ai.allo.car.feature

import ai.allo.car.ui.ScreenAction
import ai.allo.car.voice.DestinationVoiceState
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.unit.dp

/** Microphone access for the three existing destination commands, not a new travel-request flow. */
@Composable
fun DestinationVoiceControls(
    state: DestinationVoiceState,
    connected: Boolean,
    onVisible: (Boolean) -> Unit,
    onStart: () -> Unit,
    onCancel: () -> Unit,
) {
    DisposableEffect(Unit) {
        onVisible(true)
        onDispose { onVisible(false) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("목적지 음성 요청")
        Text("‘목적지 추천해 줘’, ‘응, 안내해 줘’, ‘다른 데는?’이라고 말해 주세요.")
        ScreenAction(if (state.busy) "음성 요청 중지" else "음성 요청", if (state.busy) onCancel else onStart,
            enabled = connected || state.busy, secondary = true)
        if (state.message.isNotBlank()) Text(state.message)
    }
}
