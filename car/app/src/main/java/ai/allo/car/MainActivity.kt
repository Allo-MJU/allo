package ai.allo.car

import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import ai.allo.car.vehicle.AaosPropertyReader
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.allo.car.model.CarScreen
import ai.allo.car.ui.AlloTheme
import ai.allo.car.ui.DrivingScreen
import ai.allo.car.ui.PairingScreen
import ai.allo.car.ui.ParkedScreen
import ai.allo.car.ui.SpeedNoticeScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val session = (application as AlloApp).session
        session.ensureStarted()
        // 런처는 STARTED 전에 등록해야 한다. 요청은 안내 화면의 [계속] 에서
        val speedPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            showSpeedNotice = false   // 거부해도 화면은 넘긴다. 속도 없이 SPEED capability=false 로 동작
            if (granted) session.onSpeedPermissionGranted()
        }
        showSpeedNotice = checkSelfPermission(AaosPropertyReader.SPEED_PERMISSION) != PackageManager.PERMISSION_GRANTED

        setContent {
            val screen by session.screen.collectAsStateWithLifecycle()
            val game by session.game.collectAsStateWithLifecycle()
            val meta by session.meta.collectAsStateWithLifecycle()
            // 테마 없이 그리면 Text 가 기본 검정이 되어 DeviceDefault(어두운) 창 배경에 묻힌다 (AlloTheme = 어두운 차량용 테마)
            AlloTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    if (showSpeedNotice) SpeedNoticeScreen(onContinue = { speedPermission.launch(AaosPropertyReader.SPEED_PERMISSION) })
                    else when (screen) {
                        CarScreen.Pairing -> PairingScreen(meta = meta, dbUrl = BuildConfig.ALLO_DB_URL, sessionId = session.sessionId)
                        CarScreen.Driving -> DrivingScreen(game = game)
                        CarScreen.Parked -> ParkedScreen(game = game)
                    }
                }
            }
        }
    }

    /**
     * 속도(CAR_SPEED)는 dangerous 권한. 에뮬레이터 시연의 거리 = 속도 적분이라 없으면 알이 안 자란다.
     * 시스템 창이 "위치 정보" 라고 나오므로 먼저 SpeedNoticeScreen 을 보여 준다.
     */
    private var showSpeedNotice by mutableStateOf(false)
}
