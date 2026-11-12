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
    ScreenFrame("차량 정보 연결", "주차 중") {
        ScreenColumns(
            art = { artSize -> AlloWordmark(Modifier.width(artSize).height(artSize * .65f)) },
            details = {
                Text("차량의 움직임을 연결해요", style = MaterialTheme.typography.headlineMedium)
                Text("속도 정보를 사용하면 주행 상태를 폰의 알로와 함께 볼 수 있어요.",
                    style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                ScreenAction("권한 확인하기", onContinue)
                onLater?.let { ScreenAction("나중에 연결하기", it, secondary = true) }
                Text("시스템 권한 창에서 ‘위치 정보’로 표시될 수 있어요. 허용하지 않아도 가능한 기능은 사용할 수 있어요.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            },
        )
    }
}
