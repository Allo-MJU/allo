package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import ai.allo.car.R
import ai.allo.car.model.GameState

/** 주행 중: 한 줄 상태 + 진행바만. 게임 화면은 절대 띄우지 않는다 (주행 규제). */
@Composable
fun DrivingScreen(game: GameState) {
    Column(
        modifier = Modifier.fillMaxSize().padding(48.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = stringResource(R.string.driving_status, (game.progress * 100).toInt()),
            style = MaterialTheme.typography.displaySmall,
        )
        Spacer(Modifier.height(24.dp))
        LinearProgressIndicator(progress = { game.progress.toFloat() }, modifier = Modifier.fillMaxWidth(0.6f).height(16.dp))
    }
}
