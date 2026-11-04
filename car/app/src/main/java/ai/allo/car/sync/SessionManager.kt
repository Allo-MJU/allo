package ai.allo.car.sync

import android.content.Context
import android.content.Intent
import android.os.Build
import ai.allo.car.BuildConfig
import ai.allo.car.model.*
import ai.allo.car.vehicle.*
import ai.allo.car.gleo.Destination
import ai.allo.car.gleo.DestinationFlow
import ai.allo.car.gleo.GleoFunctions
import ai.allo.car.voice.DriverVoice
import ai.allo.car.navi.NaviEtaReader
import ai.allo.car.voice.HatchAnnouncement
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.security.SecureRandom
import java.util.UUID

/**
 * 주행 1회 = 세션 1개. 생성 → 페어링 → 1초 발행 → /game 구독 → 종료.
 * 판정은 하지 않는다. 폰이 쓴 /game 을 읽어 화면과 Gleo 에 전달만 한다.
 */
class SessionManager(private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val rest = FirebaseRest(BuildConfig.ALLO_DB_URL)

    val caps = CapabilityChecker()
    private val derivation = SignalDerivation()
    private val envTagger = EnvTagger()
    val regionTagger = RegionTagger()
    private val vehicleReader = VehicleSignalReader(context, caps)
    private val aaos = AaosPropertyReader(context)
    /** 운전자 음성. 차 화면에 게임을 띄우지 않고 말로만 알린다. */
    val voice = DriverVoice(context)

    val sessionId: String = UUID.randomUUID().toString()
    private val _meta = MutableStateFlow(
        SessionMeta(createdAt = System.currentTimeMillis(), pairCode = newPairCode(), carAppVersion = BuildConfig.CAR_APP_VERSION)
    )
    val meta: StateFlow<SessionMeta> = _meta
    private val _game = MutableStateFlow(GameState())
    val game: StateFlow<GameState> = _game
    private val _vehicle = MutableStateFlow<VehicleSnapshot?>(null)
    val vehicle: StateFlow<VehicleSnapshot?> = _vehicle
    /** 내비 ETA. 경로 안내 중이 아니면 null → 폰은 거리 폴백 */
    val naviEta = NaviEtaReader(context)
    /** Gleo 목적지 제안 → 수락 */
    val destinations = DestinationFlow()

    val screen: StateFlow<CarScreen> = combine(_meta, aaos.state) { m, a ->
        when {
            !m.paired -> CarScreen.Pairing
            a.gear == "P" -> CarScreen.Parked        // 검증 #6 뒤 CarUxRestrictions 판정으로 교체
            else -> CarScreen.Driving
        }
    }.stateIn(scope, SharingStarted.Eagerly, CarScreen.Pairing)

    private var started = false

    /**
     * meta 가 먼저 써져야 규칙의 `meta/createdAt` 조건이 성립한다.
     * vehicle 이 먼저 써지면 이후 meta·vehicle 쓰기가 전부 401 이 되므로, 완료 전에는 원격에 쓰지 않는다.
     */
    private val sessionReady = CompletableDeferred<Unit>()

    fun ensureStarted() {
        if (started) return
        started = true
        context.startForegroundService(Intent(context, SessionService::class.java))
        caps.assumeAaos()
        if (!aaos.start()) caps.mark(Capability.SPEED, false) // 권한 허용 후 onSpeedPermissionGranted 에서 다시 true
        vehicleReader.start()
        voice.start()
        naviEta.start()
        scope.launch { announceHatch() }
        scope.launch { createSession() }
        scope.launch { publishLoop() }
        scope.launch { subscribeGame() }
        if (BuildConfig.DEBUG) scope.launch { screen.collect { debugLog("screen $it gear=${aaos.state.value.gear}") } } // P↔D 전환 시간 측정용
    }

    /** MainActivity 가 CAR_SPEED 런타임 권한을 받은 뒤 호출. */
    fun onSpeedPermissionGranted() {
        if (aaos.startSpeed()) caps.mark(Capability.SPEED, true)
    }

    /** Gleo 제안. 현재 위치에서 가까운 순. 폰에는 지역 태그만 알린다 (좌표 X). */
    fun suggestDestination(): DestinationFlow.Offer {
        val here = naviEta.position.value
        // 방문 기록은 폰에만 있다. /game 에 미방문 지역 필드가 생기기 전까지는 null(폴백). 이슈 #9
        val offer = destinations.offer(here, regionTagger.tag(here?.lat, here?.lng), unvisitedRegions = null)
        if (offer is DestinationFlow.Offer.Made) {
            val region = offer.suggestion.destination.region
            scope.launch { runCatching { emitEvent("destinationSuggest", mapOf("region" to region, "status" to "offered")) } }
        }
        return offer
    }

    /** 운전자가 수락. 직전 제안이 유효할 때만 내비에 목적지를 넣는다. */
    fun acceptDestination(): Destination? {
        val d = destinations.accept() ?: return null
        naviEta.requestRoute(d.latitude, d.longitude, d.name)
        scope.launch { runCatching { emitEvent("destinationSuggest", mapOf("region" to d.region, "status" to "accepted")) } }
        return d
    }

    fun stop() {
        scope.launch { runCatching { emitEvent("sessionEnd") } }
        vehicleReader.stop(); aaos.stop(); voice.release(); naviEta.stop()
        scope.cancel()
    }

    /** 폰이 /game 을 hatched 로 바꾸는 순간 운전자에게 한 번 말한다 (시연 7단계). */
    private suspend fun announceHatch() {
        var prev: String? = null
        _game.collect { g ->
            if (HatchAnnouncement.shouldAnnounce(prev, g.stage)) {
                voice.speak(GleoFunctions.respond(GleoFunctions.CELEBRATE_HATCH, g).message)
            }
            prev = g.stage
        }
    }

    private suspend fun createSession() {
        if (!rest.isConfigured) return
        while (currentCoroutineContext().isActive) {
            val r = runCatching { rest.put("sessions/$sessionId/meta", rest.json.encodeToString(_meta.value)) }
            if (r.isSuccess) {
                debugLog("session created sid=$sessionId")
                sessionReady.complete(Unit)
                return
            }
            debugLog("session create failed sid=$sessionId: ${r.exceptionOrNull()?.message}")
            delay(2_000)   // 네트워크가 늦게 붙는 경우 재시도
        }
    }

    /** 쓰기 성공/실패가 바뀔 때만 남긴다. 1초마다 같은 줄이 쌓이지 않게. */
    private var lastWriteOk: Boolean? = null
    private fun reportWrite(ok: Boolean, err: Throwable? = null) {
        if (ok == lastWriteOk) return
        lastWriteOk = ok
        debugLog(if (ok) "vehicle write ok sid=$sessionId" else "vehicle write failed sid=$sessionId: ${err?.message}")
    }

    private fun debugLog(msg: String) {
        if (BuildConfig.DEBUG) android.util.Log.d("SessionManager", msg)
    }

    /** 1초 주기. 변화가 없어도 ts 는 갱신한다 (폰이 연결 상태를 알 수 있게). */
    private suspend fun publishLoop() {
        var tick = 0L
        while (currentCoroutineContext().isActive) {
            val now = System.currentTimeMillis()
            if (tick++ % 10 == 0L) naviEta.poll() // 남은 시간 이벤트가 뜸한 구간 보강 (10초)
            val a = aaos.state.value
            val r = vehicleReader.raw.value
            derivation.update(now, a.speedKph, r.steerDeg, r.odometerM)
            val snap = VehicleSnapshot(
                ts = now,
                gear = a.gear,
                speedKph = a.speedKph,
                distanceM = derivation.distanceM,
                harshBrake = derivation.harshBrakeCount,
                harshSteer = derivation.harshSteerCount,
                wiperLevel = r.wiperLevel,
                headlightOn = r.headlightOn,
                seatRow2 = r.seatRow2Occupied,
                etaSec = naviEta.etaSec.value,
                envTags = envTagger.tags(now, a.speedKph, r.wiperLevel, r.headlightOn, naviEta.position.value.let { regionTagger.tag(it?.lat, it?.lng) }),
                capabilities = caps.snapshot(),
            )
            if (BuildConfig.DEBUG && snap.copy(ts = 0) != _vehicle.value?.copy(ts = 0)) {
                android.util.Log.d("SessionManager", "vehicle $snap") // 디버그 빌드만. 값이 바뀔 때만
            }
            _vehicle.value = snap
            if (rest.isConfigured && sessionReady.isCompleted) runCatching { rest.put("sessions/$sessionId/vehicle", rest.json.encodeToString(snap)) }
                .onSuccess { reportWrite(true) }
                .onFailure { reportWrite(false, it) }
            delay(1_000)
        }
    }

    private suspend fun subscribeGame() {
        if (!rest.isConfigured) return
        sessionReady.await()
        var current: JsonObject = JsonObject(emptyMap())
        while (currentCoroutineContext().isActive) {
            runCatching {
                rest.stream("sessions/$sessionId/game").collect { ev ->
                    current = merge(current, ev.path, ev.data)
                    runCatching { rest.json.decodeFromJsonElement<GameState>(current) }.onSuccess { _game.value = it }
                }
            }
            delay(2_000)   // 끊기면 재연결
        }
        // 페어링 여부는 meta.paired 를 폰이 바꾼다. 같은 방식으로 meta 도 구독한다.
    }

    init {
        scope.launch {
            if (!rest.isConfigured) return@launch
            sessionReady.await()
            while (isActive) {
                runCatching {
                    rest.stream("sessions/$sessionId/meta").collect { ev ->
                        if (ev.data is JsonObject && (ev.data as JsonObject)["paired"]?.jsonPrimitive?.booleanOrNull == true)
                            _meta.update { it.copy(paired = true) }
                        if (ev.path == "/paired" && ev.data.jsonPrimitive.booleanOrNull == true)
                            _meta.update { it.copy(paired = true) }
                    }
                }
                delay(2_000)
            }
        }
    }

    suspend fun emitEvent(type: String, payload: Map<String, String> = emptyMap()) {
        if (!rest.isConfigured || !sessionReady.isCompleted) return
        val ev = GameEvent(ts = System.currentTimeMillis(), type = type, by = "car", payload = payload)
        rest.post("sessions/$sessionId/events", rest.json.encodeToString(ev))
    }

    private fun merge(base: JsonObject, path: String, data: JsonElement): JsonObject {
        if (path == "/" || path.isEmpty()) return data as? JsonObject ?: base
        val key = path.trim('/').substringBefore('/')   // 한 단계 깊이만 (game 노드는 평평하다)
        return JsonObject(base.toMutableMap().apply { if (data is JsonNull) remove(key) else put(key, data) })
    }

    private fun newPairCode(): String = "%06d".format(SecureRandom().nextInt(1_000_000))
}
