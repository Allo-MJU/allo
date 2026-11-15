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
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.Alignment
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.*
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import ai.allo.car.model.GameState
import ai.allo.car.ui.PetSummary
import ai.allo.car.ui.rememberSpeciesCatalog
import ai.allo.car.model.PleosFlow
import ai.allo.car.model.PleosRoute
import ai.allo.car.ui.PleosStatusScreen
import ai.allo.car.model.TransferStatus
import ai.allo.car.feature.TravelRequestCard
import ai.allo.car.feature.DestinationVoiceControls
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
    private var parkingChecked by mutableStateOf(false)
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
            getPreferences(MODE_PRIVATE).edit().putBoolean("speedNoticeSeen", true).apply()
            showSpeedNotice = false   // 거부해도 화면은 넘긴다. 속도 없이 SPEED capability=false 로 동작
            if (granted) session.onSpeedPermissionGranted()
        }
        showSpeedNotice = !getPreferences(MODE_PRIVATE).getBoolean("speedNoticeSeen", false) &&
            checkSelfPermission(AaosPropertyReader.SPEED_PERMISSION) != PackageManager.PERMISSION_GRANTED

        setContent {
            val parkedState = rememberSaveableStateHolder()
            val game by session.game.collectAsStateWithLifecycle()
            val drivingMotion by session.drivingMotion.collectAsStateWithLifecycle()
            val meta by session.meta.collectAsStateWithLifecycle()
            val connected by session.gameConnected.collectAsStateWithLifecycle()
            val transfer by session.transferUi.collectAsStateWithLifecycle()
            val fishingUi by session.fishingUi.collectAsStateWithLifecycle()
            val travelOffer by session.travelOffer.collectAsStateWithLifecycle()
            val destinationVoiceState by session.destinationVoiceState.collectAsStateWithLifecycle()
            val travelMessage by session.travelMessage.collectAsStateWithLifecycle()
            val ended by session.ended.collectAsStateWithLifecycle()
            val pairingReady by session.pairingReady.collectAsStateWithLifecycle()
            val sid by session.sessionIdentity.collectAsStateWithLifecycle()
            val pairingRefresh by session.pairingRefreshUi.collectAsStateWithLifecycle()
            val resultKey = "$sid:${game.transferResult?.requestId}:${transfer.status}"
            var dismissed by remember(resultKey) { mutableStateOf(false) }
            var fishingDismissed by remember(sid, game.companion?.displayId, game.companion?.displayRevision) { mutableStateOf(false) }
            val route = PleosFlow.route(parkingChecked, parkedAllowed, showSpeedNotice,
                meta.paired, connected, ended, game, transfer, dismissed, dismissFishing = true)
            val catalog = rememberSpeciesCatalog()
            var previousCarGame by remember(sid) { mutableStateOf<GameState?>(null) }
            var departing by remember(sid) { mutableStateOf<GameState?>(null) }
            var observedExit by remember(sid) { mutableLongStateOf(transfer.exitSerial) }
            val exit = remember(sid) { Animatable(1f) }
            SideEffect {
                if (game.companion?.location == "car" && "companion" !in game.invalidBlocks) previousCarGame = game
            }
            LaunchedEffect(transfer.exitSerial, route) {
                if (observedExit != transfer.exitSerial && route in setOf(PleosRoute.TransferComplete, PleosRoute.Driving)) {
                    observedExit = transfer.exitSerial
                    val old = previousCarGame
                    if (route == PleosRoute.TransferComplete && old?.companion?.displayId == transfer.subjectDisplayId) {
                        departing = old
                        try {
                            exit.snapTo(0f)
                            exit.animateTo(1f, tween(900))
                        } finally { departing = null }
                    }
                }
            }
            AlloTheme {
                Column(Modifier.fillMaxSize()) {
                    if (BuildConfig.FIREBASE_EMULATOR) Surface(modifier = Modifier.fillMaxWidth(), color = androidx.compose.material3.MaterialTheme.colorScheme.secondaryContainer) {
                        Text("로컬 Firebase 검증 · 실제 프로젝트 아님", modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp), style = androidx.compose.material3.MaterialTheme.typography.labelSmall)
                    }
                    Box(Modifier.weight(1f)) {
                        when (route) {
                            PleosRoute.Starting -> PleosStatusScreen(route, game, false)
                            PleosRoute.Permission -> SpeedNoticeScreen(
                                onContinue = {
                                    getPreferences(MODE_PRIVATE).edit().putBoolean("speedNoticeSeen", true).apply()
                                    speedPermission.launch(AaosPropertyReader.SPEED_PERMISSION)
                                },
                                onLater = {
                                    getPreferences(MODE_PRIVATE).edit().putBoolean("speedNoticeSeen", true).apply()
                                    showSpeedNotice = false
                                })
                            PleosRoute.Pairing -> PairingScreen(meta, if (pairingReady) BuildConfig.ALLO_DB_URL else "", sid,
                                onRenewCode = if (pairingReady && !meta.paired && parkedAllowed) ({ session.renewPairingCode() }) else null,
                                renewing = pairingRefresh.busy, renewalMessage = pairingRefresh.message)
                            PleosRoute.Driving -> DrivingScreen(game, connected && meta.paired && !ended,
                                fishingMotion = true, drivingSignalFresh = drivingMotion.fresh, statusMessage = when {
                                    ended -> "이번 연결이 끝났어요"
                                    meta.paired && !connected -> "폰 연결이 끊겼어요"
                                    !meta.paired -> "주차 후 폰을 연결해 주세요"
                                    else -> null
                                })
                            PleosRoute.Home, PleosRoute.Empty -> parkedState.SaveableStateProvider(sid) {
                                ParkedScreen(game, connected,
                                    dialogueBank = session.dialogue, unreviewedDialoguePreview = BuildConfig.DEBUG,
                                    onShare = if (BuildConfig.DEBUG) ({ openShare() }) else null,
                                    onCallCompanion = if (game.hasV2Contract && game.companion?.location == "car" && transfer.pending == null && fishingUi.pending == null && !ended)
                                        ({ session.requestCompanionTransfer(); Unit }) else null,
                                    travelContent = {
                                        DestinationVoiceControls(destinationVoiceState, connected && !ended,
                                            onVisible = session::setDestinationVoiceVisible,
                                            onStart = session::startDestinationVoice,
                                            onCancel = { session.cancelDestinationVoice() })
                                        TravelRequestCard(game, connected && !ended, travelOffer, travelMessage,
                                            onOffer = { session.offerTravel() }, onAccept = { token, index -> session.acceptTravel(token, index) })
                                    })
                            }
                            else -> PleosStatusScreen(route, game, connected && !ended,
                                fishing = game.fishing?.takeIf { it.appliesTo(game) }?.display(),
                                motionAllowed = fishingUi.available && fishingUi.pending == null,
                                requestMessage = if (route in setOf(PleosRoute.Fishing, PleosRoute.Paused, PleosRoute.Saving, PleosRoute.SaveFailed, PleosRoute.Reward)) fishingUi.message else null,
                                onRetryRequest = if (fishingUi.unconfirmed) ({ session.retryFishing() }) else null,
                                onHome = if (route in setOf(PleosRoute.Fishing, PleosRoute.Paused, PleosRoute.Saving, PleosRoute.SaveFailed, PleosRoute.Reward)) ({ fishingDismissed = true }) else null,
                                onSecondary = if (route in setOf(PleosRoute.Fishing, PleosRoute.Paused, PleosRoute.Reward) && fishingUi.available && fishingUi.pending == null)
                                    ({ session.requestCompanionTransfer(); Unit }) else null,
                                transferMessage = transfer.message.takeIf { it.isNotBlank() },
                                departure = departing?.let { PetSummary.from(it, true, catalog) }, departureFraction = exit.value,
                                onPrimary = when (route) {
                                    PleosRoute.Disconnected -> ({ session.refreshGameState() })
                                    PleosRoute.Ended -> ({ session.prepareNextSession() })
                                    PleosRoute.TransferComplete, PleosRoute.TransferRejected -> ({ dismissed = true })
                                    PleosRoute.TransferPending -> if (transfer.status == TransferStatus.Unconfirmed) ({ session.retryCompanionTransfer() }) else null
                                    PleosRoute.Fishing, PleosRoute.Reward -> if (fishingUi.available && fishingUi.pending == null) ({ session.requestFishing("pause") }) else null
                                    PleosRoute.Paused -> if (fishingUi.available && fishingUi.pending == null) ({ session.requestFishing("resume") }) else null
                                    PleosRoute.SaveFailed -> if (fishingUi.available && fishingUi.pending == null) ({ session.requestFishing("retry") }) else null
                                    else -> null
                                })
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
        parkingChecked = false
        setParkingPermission(false)
        // The receiver may see D then close before this activity's first P read.
        val returnedFromDriving = BuildConfig.DEBUG && runCatching {
            Class.forName("ai.allo.car.mirror.MirrorActivity").getMethod("takeDrivingTransition").invoke(null) as Boolean
        }.getOrDefault(false)
        if (returnedFromDriving) shareTransition.update(true, false, null, false)
        parkingGate = ParkedMirrorGate(this) { connected, parked, uxAllowed ->
            if (!visible) return@ParkedMirrorGate
            parkingChecked = true
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

    override fun onResume() {
        super.onResume()
        (application as AlloApp).session.updateActivityResumed(true)
    }

    override fun onPause() {
        (application as AlloApp).session.updateActivityResumed(false)
        super.onPause()
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
