package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import ai.allo.car.R
import ai.allo.car.model.GameState

/** 주행 중: 알 + 한 줄 상태 + 진행바만. 게임 화면은 절대 띄우지 않는다 (주행 규제). */
@Composable
fun DrivingScreen(game: GameState) {
    val p = game.progress.toFloat()
    Row(
        modifier = Modifier.fillMaxSize().padding(64.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        EggMark(size = 220.dp, fill = p)
        Spacer(Modifier.width(72.dp))
        Column(Modifier.widthIn(max = 900.dp)) {
            Text(stringResource(R.string.driving_status, (p * 100).toInt()), style = MaterialTheme.typography.displaySmall)
            Spacer(Modifier.height(32.dp))
            ThickProgress(p, Modifier.fillMaxWidth())
        }
    }
}
