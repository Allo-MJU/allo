package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import ai.allo.car.model.GameState

/**
 * 정차(기어 P): 폰의 게임 상태를 차 화면 레이아웃으로 다시 그린다.
 * 영상 미러링이 아니라 /game 노드를 읽어 렌더한다. 기어 D 로 가면 즉시 DrivingScreen 으로 바뀐다.
 */
@Composable
fun ParkedScreen(game: GameState) {
    Column(
        modifier = Modifier.fillMaxSize().padding(48.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        when (game.stage) {
            "hatched" -> {
                Text("깨어났어요!", style = MaterialTheme.typography.displayMedium)
                Spacer(Modifier.height(16.dp))
                Text("${game.speciesId ?: "?"} · ${game.attribute ?: "-"} · tier ${game.tier ?: "-"}", style = MaterialTheme.typography.headlineMedium)
                // TODO(B/D): 종 스프라이트, 속성 이펙트
            }
            "incubating" -> {
                Text("알을 품는 중 · ${(game.progress * 100).toInt()}%", style = MaterialTheme.typography.displaySmall)
                Spacer(Modifier.height(16.dp))
                Text("감싸주기 ${game.careCount}회 · 창밖 보기 ${game.lookOutCount}회", style = MaterialTheme.typography.titleLarge)
            }
            else -> Text("뒷자리 폰에서 알을 골라 주세요", style = MaterialTheme.typography.displaySmall)
        }
    }
}
