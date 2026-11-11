package ai.allo.car

import android.content.pm.PackageManager
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import ai.allo.car.vehicle.AaosPropertyReader
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.Alignment
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.allo.car.model.TransferStatus
import ai.allo.car.feature.TravelRequestCard
import ai.allo.car.model.CarScreen
import ai.allo.car.model.CarDisplayPolicy
import ai.allo.car.model.ParkedShareTransition
import ai.allo.car.mirror.ParkedMirrorGate
import ai.allo.car.ui.AlloTheme
import ai.allo.car.ui.DrivingScreen
import ai.allo.car.ui.PairingScreen
import ai.allo.car.ui.ParkedScreen
import ai.allo.car.ui.SpeedNoticeScreen

class MainActivity : ComponentActivity() {
    private val main = Handler(Looper.getMainLooper())
    private var parkingGate: ParkedMirrorGate? = null
    private var parkedAllowed by mutableStateOf(false)
    private var parkingVerifiedAt = -1L
    private var visible = false
    private val shareTransition = ParkedShareTransition()
    private val checkParkingFreshness = object : Runnable {
        override fun run() {
            if (!visible) return
            if (SystemClock.elapsedRealtime() - parkingVerifiedAt >= ParkedMirrorGate.MAX_STATUS_AGE_MS) setParkingPermission(false)
            main.postDelayed(this, 100)
        }
    }

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
            val game by session.game.collectAsStateWithLifecycle()
            val meta by session.meta.collectAsStateWithLifecycle()
            val connected by session.gameConnected.collectAsStateWithLifecycle()
            val transfer by session.transferUi.collectAsStateWithLifecycle()
            val travelOffer by session.travelOffer.collectAsStateWithLifecycle()
            val travelMessage by session.travelMessage.collectAsStateWithLifecycle()
            val ended by session.ended.collectAsStateWithLifecycle()
            val screen = CarDisplayPolicy.screen(meta.paired, parkedAllowed)
            // 테마 없이 그리면 Text 가 기본 검정이 되어 DeviceDefault(어두운) 창 배경에 묻힌다 (AlloTheme = 어두운 차량용 테마)
            AlloTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    Box(modifier = Modifier.fillMaxSize()) {
                        if (showSpeedNotice && parkedAllowed) SpeedNoticeScreen(onContinue = { speedPermission.launch(AaosPropertyReader.SPEED_PERMISSION) })
                        else when (screen) {
                            CarScreen.Pairing -> PairingScreen(meta = meta, dbUrl = BuildConfig.ALLO_DB_URL, sessionId = session.sessionId)
                            CarScreen.Driving -> DrivingScreen(game = game, connected = connected && meta.paired, runningMotion = true)
                            CarScreen.Parked -> ParkedScreen(game = game, connected = connected,
                                onShare = if (BuildConfig.DEBUG) ({ openShare() }) else null,
                                transferMessage = transfer.message.takeIf { it.isNotBlank() && game.hasV2Contract },
                                onCallCompanion = if (game.hasV2Contract && game.companion?.location == "car" && transfer.pending == null && !ended)
                                    ({ session.requestCompanionTransfer(); Unit }) else null,
                                onRetryTransfer = if (transfer.status == TransferStatus.Unconfirmed && transfer.pending != null && !ended)
                                    ({ session.retryCompanionTransfer() }) else null,
                                exitSerial = transfer.exitSerial,
                                travelContent = {
                                    TravelRequestCard(game, connected && !ended, travelOffer, travelMessage,
                                        onOffer = { session.offerTravel() }, onAccept = { token, index -> session.acceptTravel(token, index) })
                                })
                        }
                        if (BuildConfig.DEBUG && parkedAllowed && (screen == CarScreen.Pairing || showSpeedNotice)) {
                            TextButton(
                                modifier = Modifier.align(Alignment.BottomEnd),
                                onClick = { openShare() },
                            ) { Text("폰 화면 공유") }
                        }
                    }
                }
            }
        }
    }

    /** 포그라운드 서비스는 화면에 보일 때만 시작할 수 있다 (Android 12+). 실패했으면 다음 onStart 에서 다시 */
    override fun onStart() {
        super.onStart()
        (application as AlloApp).session.ensureForeground()
        visible = true
        setParkingPermission(false)
        // The receiver may see D then close before this activity's first P read.
        val returnedFromDriving = BuildConfig.DEBUG && runCatching {
            Class.forName("ai.allo.car.mirror.MirrorActivity").getMethod("takeDrivingTransition").invoke(null) as Boolean
        }.getOrDefault(false)
        if (returnedFromDriving) shareTransition.update(true, false, null, false)
        parkingGate = ParkedMirrorGate(this) { connected, parked, uxAllowed ->
            if (!visible) return@ParkedMirrorGate
            parkingVerifiedAt = SystemClock.elapsedRealtime()
            setParkingPermission(connected && parked == true && uxAllowed == true)
            val configured = BuildConfig.DEBUG && runCatching {
                Class.forName("ai.allo.car.mirror.MirrorActivity").getMethod("hasConnection").invoke(null) as Boolean
            }.getOrDefault(false)
            if (shareTransition.update(connected, parked, uxAllowed, configured)) openShare()
        }.also { it.start() }
        main.post(checkParkingFreshness)
    }

    private fun setParkingPermission(allowed: Boolean) {
        parkedAllowed = allowed
        (application as AlloApp).session.updateParkedPermission(allowed, parkingVerifiedAt)
    }

    private fun openShare() {
        if (!BuildConfig.DEBUG || !visible || !parkedAllowed) return
        startActivity(Intent().setClassName(this, "ai.allo.car.mirror.MirrorActivity"))
    }

    override fun onStop() {
        visible = false
        setParkingPermission(false)
        main.removeCallbacks(checkParkingFreshness)
        parkingGate?.close()
        parkingGate = null
        super.onStop()
    }

    /**
     * 속도(CAR_SPEED)는 dangerous 권한. 에뮬레이터 시연의 거리 = 속도 적분이라 없으면 알이 안 자란다.
     * 시스템 창이 "위치 정보" 라고 나오므로 먼저 SpeedNoticeScreen 을 보여 준다.
     */
    private var showSpeedNotice by mutableStateOf(false)
}
