package ai.allo.preview

import ai.allo.car.model.*
import ai.allo.car.ui.*
import android.os.SystemClock
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/** Local-only transport: phone owns all progress/reward/persistence decisions. */
private val wireJson = Json { encodeDefaults = true }

private suspend fun bridge(path: String, body: String? = null): String = withContext(Dispatchers.IO) {
    val connection = URL("http://10.0.2.2:8765$path").openConnection() as HttpURLConnection
    try {
        connection.connectTimeout = 1500
        connection.readTimeout = 1500
        if (body != null) {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
        }
        check(connection.responseCode in 200..299) { "local bridge unavailable" }
        connection.inputStream.bufferedReader().use { it.readText() }
    } finally { connection.disconnect() }
}

@Composable
fun LocalFishingDemo(active: Boolean) {
    val latestActive by rememberUpdatedState(active)
    val scope = rememberCoroutineScope()
    val controller = remember { FishingController() }
    val freshness = remember { FishingFreshness() }
    val epoch = remember { UUID.randomUUID().toString() }
    var sequence by remember { mutableLongStateOf(0) }
    var game by remember { mutableStateOf(GameState()) }
    var ui by remember { mutableStateOf(FishingUiState()) }
    var connected by remember { mutableStateOf(false) }
    var networkError by remember { mutableStateOf<String?>(null) }
    var home by remember { mutableStateOf(false) }
    val session = "local-fishing-demo"
    fun permitted() = latestActive && freshness.isFresh(SystemClock.elapsedRealtime())
    fun send(action: String, retry: Boolean = false) {
        val now = SystemClock.elapsedRealtime()
        val request = if (retry) controller.retry(session, game, permitted(), now)
            else controller.request(session, game, permitted(), action, now)
        ui = controller.ui
        if (request != null) scope.launch {
            try { bridge("/events", fishingRequestEvent(request, System.currentTimeMillis()).toString()) }
            catch (_: Exception) { networkError = "로컬 연결을 확인해 주세요. 같은 요청을 다시 확인할 수 있어요." }
        }
    }
    LaunchedEffect(Unit) {
        while (isActive) {
            try {
                val raw = Json.parseToJsonElement(bridge("/game"))
                val next = (raw as? JsonObject)?.let(GameSnapshotReader::parse)
                val now = SystemClock.elapsedRealtime()
                if (next != null && freshness.observe(next.gameRevision, now)) {
                    if (game.companion?.displayId != next.companion?.displayId ||
                        game.companion?.displayRevision != next.companion?.displayRevision) home = false
                    game = next
                }
                connected = next != null && freshness.isFresh(now)
                controller.observe(session, game, connected && latestActive, now)
                ui = controller.ui
                val presence = game.fishing?.takeIf { it.appliesTo(game) }?.let {
                    FishingPresence(leaseId = it.leaseId, epoch = epoch, sequence = ++sequence,
                        active = latestActive && connected, parkedAllowed = latestActive && connected)
                }
                val vehicle = VehicleSnapshot(System.currentTimeMillis(), "P", 0.0, 0.0,
                    0, 0, 0, false, true, envTags = emptyList(), capabilities = listOf("gear"), fishingPresence = presence)
                bridge("/vehicle", wireJson.encodeToString(vehicle))
                networkError = null
            } catch (_: Exception) {
                freshness.disconnect()
                connected = false
                controller.observe(session, game, false, SystemClock.elapsedRealtime())
                ui = controller.ui
                networkError = "로컬 연결 대기 · 호스트의 모의 연동 서버를 확인해 주세요."
            }
            delay(750)
        }
    }
    val fishing = game.fishing?.takeIf { it.appliesTo(game) }
    val route = if (home) null else fishing?.route()
    val enabled = ui.available && ui.pending == null && active && connected
    val action = when (fishing?.state) {
        "ready" -> "start"; "paused" -> "resume"; "saveFailed" -> "retry"
        "running", "reward" -> "pause"; else -> null
    }
    Surface(Modifier.fillMaxSize()) {
        Column(Modifier.windowInsetsPadding(WindowInsets.safeDrawing)) {
            Text("로컬 모의 연동 · P/차량 신호 모의 · Firebase 미사용 · 폰 실제 계산/로컬 저장",
                fontSize = 13.sp, modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant).padding(8.dp))
            networkError?.let { Text(it, Modifier.padding(horizontal = 12.dp), fontSize = 14.sp) }
            if (game.ts == 0L) {
                Box(Modifier.weight(1f)) { PleosStatusScreen(PleosRoute.Empty, game) }
            } else if (route == null) {
                Box(Modifier.weight(1f)) {
                    ParkedScreen(game, connected = connected,
                        onStartFishing = if (!enabled) null else ({
                            home = false
                            if (fishing?.state in setOf("ready", "paused", "saveFailed")) action?.let { send(it) }
                        }), fishingMessage = ui.message,
                        onRetryFishing = if (ui.unconfirmed && connected) ({ send("", true) }) else null,
                        fishingMotionAllowed = active && connected,
                        onPauseFishing = if (enabled) ({ send("pause") }) else null)
                }
            } else {
                Box(Modifier.weight(1f)) {
                    PleosStatusScreen(route, game, connected = connected, fishing = fishing?.display(),
                        onPrimary = if (enabled && action != null) ({ send(action) }) else null,
                        requestMessage = ui.message,
                        onRetryRequest = if (ui.unconfirmed && connected) ({ send("", true) }) else null,
                        motionAllowed = active && connected, onHome = { home = true })
                }
            }
        }
    }
}
