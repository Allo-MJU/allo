package ai.allo.preview

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.allo.car.model.GameState
import ai.allo.car.ui.AlloTheme
import ai.allo.car.ui.DrivingScreen
import ai.allo.car.ui.ParkedScreen

/** Real production composables with explicit fixture data; no vehicle/Firebase emulation. */
class PreviewActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val mode = intent.getStringExtra("mode") ?: "driving"
        val connected = !intent.getBooleanExtra("disconnected", false)
        val game = GameState(ts = System.currentTimeMillis(), stage = "hatched", progress = 1.0,
            speciesId = "tide_keeper", attribute = "water", tier = 3)
        setContent {
            AlloTheme {
                Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.windowInsetsPadding(WindowInsets.safeDrawing)) {
                        Text(
                            "UI 미리보기 · ${if (mode == "parked") "주차" else "주행"} · 테스트 데이터 (실차 연동 아님)",
                            color = Color(0xFFA9ACC6), fontSize = 14.sp,
                            modifier = Modifier.fillMaxWidth().background(Color(0xFF1D2142)).padding(12.dp),
                        )
                        if (mode == "parked") {
                            ParkedScreen(game = game, connected = connected, onShare = {})
                        } else {
                            DrivingScreen(game = game, connected = connected)
                        }
                    }
                }
            }
        }
    }
}
