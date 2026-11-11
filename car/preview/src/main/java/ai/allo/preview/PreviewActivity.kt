package ai.allo.preview

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.allo.car.model.*
import ai.allo.car.ui.*

/** Explicit UI fixtures only. This APK has no vehicle, Firebase, reward or persistence adapter. */
class PreviewActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val initialRoute = intent.getStringExtra("screen")?.let { name ->
            PleosRoute.entries.find { it.name == name }
        } ?: when {
            intent.getBooleanExtra("disconnected", false) -> PleosRoute.Disconnected
            intent.getStringExtra("mode") == "parked" -> PleosRoute.Home
            else -> PleosRoute.Starting
        }
        val speciesOptions = linkedMapOf(
            "road_sprout" to "길싹이", "puddle_pip" to "웅덩이삐약", "lamp_moth" to "등불나방",
            "storm_lantern" to "폭풍등", "highway_comet" to "고속혜성", "sea_mist" to "바다안개",
        )
        val initialSpecies = intent.getStringExtra("species")?.takeIf { it in speciesOptions } ?: "road_sprout"
        setContent {
            AlloTheme {
                var routeName by rememberSaveable { mutableStateOf(initialRoute.name) }
                var speciesId by rememberSaveable { mutableStateOf(initialSpecies) }
                val route = PleosRoute.valueOf(routeName)
                fun show(next: PleosRoute) { routeName = next.name }
                val game = GameState(
                    ts = 1, stage = "hatched", progress = 1.0, speciesId = speciesId,
                    contractVersion = 2, gameRevision = 1,
                    companion = if (route == PleosRoute.Empty) null else CompanionDisplay(
                        "preview-$speciesId", 1, speciesId,
                        if (route == PleosRoute.TransferComplete) "phone" else "car",
                    ),
                    baseSummary = BaseSummary("road_sprout", "puddle_pip", "lamp_moth"),
                )
                val fishing = FishingDisplay(
                    elapsedSeconds = if (route in listOf(PleosRoute.Saving, PleosRoute.Reward, PleosRoute.SaveFailed)) 60 else 35,
                    targetSeconds = 60,
                    rewardName = if (route == PleosRoute.Reward) "물고기 A · 예시" else null,
                    totalRecords = if (route == PleosRoute.Reward) 3 else null,
                )
                Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.windowInsetsPadding(WindowInsets.safeDrawing)) {
                        Text("UI 미리보기 · 테스트 데이터 · 실차/폰 연동 아님",
                            color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp,
                            modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant).padding(8.dp))
                        if (intent.getBooleanExtra("controls", true)) {
                        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            PleosRoute.entries.forEach { candidate ->
                                FilterChip(route == candidate, { show(candidate) }, { Text(candidate.label, fontSize = 16.sp) })
                            }
                        }
                        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(onClick = { show(nextFixture(route)) }) { Text("다음 상태 시연", fontSize = 16.sp) }
                            speciesOptions.forEach { (id, label) ->
                                FilterChip(speciesId == id, { speciesId = id }, { Text(label, fontSize = 16.sp) })
                            }
                        }
                        }
                        // key prevents local home/tab/action state from leaking into another fixture.
                        key(route, speciesId) {
                            Box(Modifier.weight(1f).fillMaxWidth()) {
                                when (route) {
                                    PleosRoute.Permission -> SpeedNoticeScreen(
                                        onContinue = { show(PleosRoute.Pairing) }, onLater = { show(PleosRoute.Pairing) })
                                    PleosRoute.Pairing -> PairingScreen(
                                        SessionMeta(1, "482619", carAppVersion = "preview"),
                                        dbUrl = "preview-only", sessionId = "ui-fixture-not-a-real-session")
                                    PleosRoute.Driving -> DrivingScreen(game, connected = true, runningMotion = true)
                                    PleosRoute.Home, PleosRoute.Empty -> ParkedScreen(game, connected = true,
                                        onCallCompanion = { show(PleosRoute.TransferPending) })
                                    else -> PleosStatusScreen(
                                        route = route, game = game, connected = route != PleosRoute.Disconnected,
                                        fishing = fishing,
                                        transferMessage = if (route == PleosRoute.TransferRejected)
                                            "폰에서 다른 활동 중이라고 알려왔어요. 활동 상태를 폰에서 확인해 주세요." else null,
                                        onPrimary = if (route in setOf(PleosRoute.Starting, PleosRoute.Saving,
                                                PleosRoute.Empty, PleosRoute.SelectionPending, PleosRoute.TransferPending)) null
                                            else ({ show(if (route == PleosRoute.Fishing) PleosRoute.Paused else nextFixture(route)) }),
                                        onSecondary = if (route == PleosRoute.Fishing)
                                            ({ show(PleosRoute.TransferPending) }) else null,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Manual scenario navigation; no clocks or fake backend success events enter the production app. */
private fun nextFixture(route: PleosRoute): PleosRoute = when (route) {
    PleosRoute.Starting -> PleosRoute.Permission
    PleosRoute.Permission -> PleosRoute.Pairing
    PleosRoute.Pairing -> PleosRoute.Home
    PleosRoute.Driving -> PleosRoute.Home
    PleosRoute.Home -> PleosRoute.Fishing
    PleosRoute.Fishing -> PleosRoute.Saving
    PleosRoute.Paused -> PleosRoute.Fishing
    PleosRoute.Saving -> PleosRoute.Reward
    PleosRoute.Reward -> PleosRoute.Paused
    PleosRoute.SaveFailed -> PleosRoute.Saving
    PleosRoute.TransferPending -> PleosRoute.TransferComplete
    PleosRoute.TransferComplete -> PleosRoute.Empty
    PleosRoute.TransferRejected -> PleosRoute.Home
    PleosRoute.Empty -> PleosRoute.SelectionPending
    PleosRoute.SelectionPending -> PleosRoute.Home
    PleosRoute.SelectionFailed -> PleosRoute.Home
    PleosRoute.Disconnected -> PleosRoute.Paused
    PleosRoute.Ended -> PleosRoute.Pairing
}
