package ai.allo.car

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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

        setContent {
            val screen by session.screen.collectAsStateWithLifecycle()
            val game by session.game.collectAsStateWithLifecycle()
            val meta by session.meta.collectAsStateWithLifecycle()
            when (screen) {
                CarScreen.Pairing -> PairingScreen(meta = meta, dbUrl = BuildConfig.ALLO_DB_URL, sessionId = session.sessionId)
                CarScreen.Driving -> DrivingScreen(game = game)
                CarScreen.Parked -> ParkedScreen(game = game)
            }
        }
    }
}
