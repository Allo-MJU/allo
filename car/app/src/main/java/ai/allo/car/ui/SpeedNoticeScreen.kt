package ai.allo.car.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import ai.allo.car.R

/**
 * CAR_SPEED 권한 요청 직전 안내. AAOS 는 CAR_SPEED 를 위치 권한 그룹으로 묶어
 * 시스템 창에 "위치 정보" 라고 나온다. 실제로는 속도만 읽는다는 것을 먼저 알린다 (verification.md 권한 실측).
 */
@Composable
fun SpeedNoticeScreen(onContinue: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(48.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        EggMark(size = 140.dp, fill = 0.5f)
        Spacer(Modifier.height(40.dp))
        Text(stringResource(R.string.speed_notice_title), style = MaterialTheme.typography.displaySmall, textAlign = TextAlign.Center)
        Spacer(Modifier.height(28.dp))
        Text(stringResource(R.string.speed_notice_body), style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(56.dp))
        Button(onClick = onContinue, modifier = Modifier.height(88.dp).widthIn(min = 360.dp)) {
            Text(stringResource(R.string.speed_notice_continue), style = MaterialTheme.typography.labelLarge)
        }
    }
}
