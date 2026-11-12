package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Permission request is launched only by the caller after this parked-only explanation. */
@Composable
fun SpeedNoticeScreen(onContinue: () -> Unit, onLater: (() -> Unit)? = null) {
    ScreenFrame("차량 정보 사용 안내", "주차 중") {
        ScreenColumns(
            art = { artSize -> AlloWordmark(Modifier.width(artSize).height(artSize * .65f)) },
            details = {
                Text("속도 정보 사용을 허용해 주세요", style = MaterialTheme.typography.headlineMedium)
                Text("차량의 움직임을 폰의 경험에 연결해요. 허용하지 않아도 가능한 기능은 사용할 수 있어요.",
                    style = MaterialTheme.typography.bodyLarge, color = AlloColors.MistDim)
                Text("다음 단계에서 시스템 권한 창이 열려요. 속도 권한이 ‘위치 정보’로 표시될 수 있어요.",
                    style = MaterialTheme.typography.bodyMedium, color = AlloColors.MistDim)
                ScreenAction("계속", onContinue)
                onLater?.let { ScreenAction("나중에", it, secondary = true) }
            },
        )
    }
}
