package ai.allo.preview

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.allo.car.model.*
import ai.allo.car.ui.AlloTheme
import ai.allo.car.ui.DrivingScreen
import ai.allo.car.ui.ParkedScreen

/** Production composables with explicit fixtures; no vehicle/Firebase emulation. */
class PreviewActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val initialParked = intent.getStringExtra("mode") == "parked"
        val initiallyConnected = !intent.getBooleanExtra("disconnected", false)
        val speciesId = intent.getStringExtra("species") ?: "road_sprout"
        setContent {
            AlloTheme {
                var parked by remember { mutableStateOf(initialParked) }
                var scenario by remember { mutableStateOf(if(initiallyConnected) "기존" else "연결끊김") }
                var phone by remember { mutableStateOf(false) }
                var exitSerial by remember { mutableLongStateOf(0) }
                val connected = scenario != "연결끊김"
                val legacy = GameState(ts = 1, stage = "hatched", progress = 1.0, speciesId = speciesId)
                val game = if(scenario=="기존") legacy else legacy.copy(
                    contractVersion=2, gameRevision=1,
                    stage=when(scenario) { "품기준비" -> "incubating"; "실패" -> "failed"; else -> "hatched" },
                    progress=if(scenario=="품기준비") .65 else 1.0,
                    companion=CompanionDisplay("preview-pet",1,speciesId,if(phone || scenario=="폰이동") "phone" else "car"),
                    affinity=if(scenario=="품기준비") AffinitySummary(10,10,true) else null,
                    baseSummary=if(scenario=="거점") BaseSummary("road_sprout","puddle_pip","lamp_moth",listOf("nest","kitchen"),"berry_meal","training") else null,
                )
                Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.windowInsetsPadding(WindowInsets.safeDrawing)) {
                        Text("UI 미리보기 · 테스트 데이터 · 실차/폰 연동 아님", color=Color(0xFFA9ACC6),fontSize=14.sp,
                            modifier=Modifier.fillMaxWidth().background(Color(0xFF1D2142)).padding(8.dp))
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                            FilterChip(parked,{parked=!parked},{Text(if(parked) "주차 → 주행" else "주행 → 주차")})
                            listOf("기존","품기준비","실패","폰이동","거점","연결끊김").forEach { option ->
                                FilterChip(scenario==option,{scenario=option;phone=false},{Text(option)})
                            }
                        }
                        if(parked) ParkedScreen(game,connected,
                            transferMessage=if(phone) "모의 응답 · 폰 이동 완료 (실제 전송 아님)" else null,
                            onCallCompanion=if(game.hasV2Contract && game.companion?.location=="car") ({phone=true;exitSerial++}) else null,
                            exitSerial=exitSerial)
                        else DrivingScreen(game,connected,runningMotion=true)
                    }
                }
            }
        }
    }
}
