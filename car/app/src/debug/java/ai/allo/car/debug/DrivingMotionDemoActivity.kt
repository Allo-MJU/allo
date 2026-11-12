package ai.allo.car.debug

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.allo.car.model.CompanionDisplay
import ai.allo.car.model.GameState
import ai.allo.car.ui.AlloTheme
import ai.allo.car.ui.DrivingScreen
import ai.allo.car.vehicle.AaosPropertyReader
import kotlinx.coroutines.launch

/** Debug only: real AAOS speed/gear, explicitly synthetic companion. No Firebase writes. */
class DrivingMotionDemoActivity : ComponentActivity() {
    private lateinit var reader: AaosPropertyReader
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        reader = AaosPropertyReader(this)
        val species = intent.getStringExtra("species")?.takeIf {
            it in setOf("road_sprout", "puddle_pip", "lamp_moth", "storm_lantern", "highway_comet", "sea_mist")
        } ?: "road_sprout"
        val game = GameState(ts = 1, stage = "hatched", progress = 1.0, speciesId = species,
            contractVersion = 2, gameRevision = 1,
            companion = CompanionDisplay("sensor-demo-$species", 1, species, "car"))
        lifecycleScope.launch {
            reader.motion.collect { Log.d("AlloMotion", "speed=${it.speedKph} rate=${it.playbackRate} fresh=${it.fresh} brake=${it.brakeSerial} at=${it.brakeAtMs}") }
        }
        setContent {
            val motion by reader.motion.collectAsStateWithLifecycle()
            val vehicle by reader.state.collectAsStateWithLifecycle()
            AlloTheme {
                Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.windowInsetsPadding(WindowInsets.safeDrawing)) {
                        Text("실제 Pleos 차량 신호 · 캐릭터만 테스트 데이터 · Firebase 미사용",
                            modifier = Modifier.fillMaxWidth().padding(8.dp), style = MaterialTheme.typography.bodySmall)
                        Text("${vehicle.gear} · ${"%.0f".format(motion.speedKph)} km/h · 달리기 ${"%.2f".format(motion.playbackRate)}배 · 급감속 ${motion.brakeSerial}회 · ${if (motion.fresh) "신호 수신" else "정지/신호 대기"}",
                            modifier = Modifier.padding(horizontal = 8.dp), style = MaterialTheme.typography.bodySmall)
                        Box(Modifier.weight(1f)) {
                            DrivingScreen(game, connected = true, drivingMotion = motion,
                                statusMessage = "주행 신호 연동 검증")
                        }
                    }
                }
            }
        }
    }
    override fun onStart() { super.onStart(); reader.start() }
    override fun onStop() { reader.stop(); super.onStop() }
}
