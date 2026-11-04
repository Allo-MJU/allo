package ai.allo.car

import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import ai.allo.car.sync.SessionManager
import ai.allo.car.vehicle.AaosPropertyReader
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.ui.Modifier
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.allo.car.model.CarScreen
import ai.allo.car.ui.DrivingScreen
import ai.allo.car.ui.PairingScreen
import ai.allo.car.ui.ParkedScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val session = (application as AlloApp).session
        session.ensureStarted()
        requestSpeedPermission(session)

        setContent {
            val screen by session.screen.collectAsStateWithLifecycle()
            val game by session.game.collectAsStateWithLifecycle()
            val meta by session.meta.collectAsStateWithLifecycle()
            // 테마 없이 그리면 Text 가 기본 검정이 되어 DeviceDefault(어두운) 창 배경에 묻힌다
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    when (screen) {
                        CarScreen.Pairing -> PairingScreen(meta = meta, dbUrl = BuildConfig.ALLO_DB_URL, sessionId = session.sessionId)
                        CarScreen.Driving -> DrivingScreen(game = game)
                        CarScreen.Parked -> ParkedScreen(game = game)
                    }
                }
            }
        }
    }

    /** 속도(CAR_SPEED)는 dangerous 권한. 에뮬레이터 시연의 거리 = 속도 적분이라 없으면 알이 안 자란다. */
    private fun requestSpeedPermission(session: SessionManager) {
        val perm = AaosPropertyReader.SPEED_PERMISSION
        if (checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED) return
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) session.onSpeedPermissionGranted()
        }.launch(perm)
    }
}
