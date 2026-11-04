package ai.allo.car.sync

import android.content.Context
import android.content.Intent
import android.os.Build
import ai.allo.car.BuildConfig
import ai.allo.car.model.*
import ai.allo.car.vehicle.*
import ai.allo.car.dialogue.DialogueBank
import ai.allo.car.gleo.AcceptResult
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
 * 주행 1회 = 세션 1개. 생성 → 페어링 → 1초 발행 → /game 구독 → 종료(sessionEnd) → 다음 출발 때 새 세션.
 * 판정은 하지 않는다. 폰이 쓴 /game 을 읽어 화면과 Gleo 에 전달만 한다.
 * 종료 기준은 [SessionEndDetector]. 종료 뒤에는 vehicle 을 더 쓰지 않고, 차 화면은 마지막 /game 을 그대로 보여 준다.
 * 기어가 P 를 벗어나면 새 세션(새 sessionId·페어링 코드)을 만든다.
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
    /** 대사 뱅크 (data/dialogue.json). 디버그 빌드는 검수 전 문장도 쓴다, release 는 reviewedBy 가 있는 것만 */
    val dialogue: DialogueBank = DialogueBank.load(context.assets, includeUnreviewed = BuildConfig.DEBUG)
        .also { if (BuildConfig.DEBUG) android.util.Log.d("SessionManager", "dialogue bank keys=${it.size}") }

    private val _sessionId = MutableStateFlow(UUID.randomUUID().toString())
    val sessionId: String get() = _sessionId.value
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
     * 세션마다 새로 만든다. [beginSession] 은 이것을 [_sessionId] 보다 먼저 바꾼다 (읽는 쪽은 id → ready 순서)
     */
    @Volatile private var sessionReady = CompletableDeferred<Unit>()
    /** 현재 세션의 구독(meta·game)과 생성 재시도. 새 세션에서 취소한다 */
    private var sessionJob: Job? = null
    @Volatile private var sessionStartedAt = 0L
    private val endDetector = SessionEndDetector()
    private val _ended = MutableStateFlow(false)
    /** 현재 세션에 sessionEnd 를 보냈는가. 다음 출발(P 이탈) 때 새 세션으로 바뀌며 false 가 된다 */
    val ended: StateFlow<Boolean> = _ended

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
        beginSession()
        scope.launch { publishLoop() }
        if (BuildConfig.DEBUG) scope.launch { screen.collect { debugLog("screen $it gear=${aaos.state.value.gear}") } } // P↔D 전환 시간 측정용
    }

    /** MainActivity 가 CAR_SPEED 런타임 권한을 받은 뒤 호출. */
    fun onSpeedPermissionGranted() {
        if (aaos.startSpeed()) caps.mark(Capability.SPEED, true)
    }

    /** Gleo 제안. 현재 위치에서 가까운 순. 폰에는 지역 태그만 알린다 (좌표 X). */
    fun suggestDestination(): DestinationFlow.Offer {
        if (naviEta.etaSec.value != null) return DestinationFlow.Offer.None(ai.allo.car.gleo.NoSuggestion.ROUTE_ACTIVE)
        val here = naviEta.position.value
        // 방문 기록은 폰에만 있다. /game 에 미방문 지역 필드가 생기기 전까지는 null(폴백). 이슈 #9
        val offer = destinations.offer(here, regionTagger.tag(here?.lat, here?.lng), unvisitedRegions = null)
        if (offer is DestinationFlow.Offer.Made) {
            val region = offer.suggestion.destination.region
            scope.launch { runCatching { emitEvent("destinationSuggest", mapOf("region" to region, "status" to "offered")) } }
        }
        return offer
    }

    /**
     * 운전자가 수락. 직전 제안이 유효하고, 안내 중이 아니고, 내비 요청이 성공했을 때만 목적지가 바뀐다.
     * accepted 이벤트도 성공했을 때만 보낸다.
     */
    fun acceptDestination(): AcceptResult {
        val r = destinations.accept(routeActive = naviEta.etaSec.value != null) { d -> naviEta.requestRoute(d.latitude, d.longitude, d.name) }
        if (r is AcceptResult.Started) {
            val d = r.destination
            scope.launch { runCatching { emitEvent("destinationSuggest", mapOf("region" to d.region, "status" to "accepted")) } }
        }
        debugLog("accept → ${r::class.simpleName}")
        return r
    }

    /** 새 세션: 새 id·페어링 코드, 누적값 초기화, 구독 다시 시작. 폰은 다시 페어링해야 한다 */
    @Synchronized
    private fun beginSession() {
        sessionJob?.cancel()
        val id = UUID.randomUUID().toString()
        val ready = CompletableDeferred<Unit>()
        derivation.reset(); endDetector.reset(); destinations.reset()
        sessionStartedAt = System.currentTimeMillis()
        sessionReady = ready
        _sessionId.value = id
        _game.value = GameState()
        _meta.value = SessionMeta(createdAt = sessionStartedAt, pairCode = newPairCode(), carAppVersion = BuildConfig.CAR_APP_VERSION)
        _ended.value = false
        sessionJob = scope.launch {
            launch { createSession(id, ready) }
            launch { subscribeGame(id, ready) }
            launch { subscribeMeta(id, ready) }
        }
    }

    /**
     * 세션 종료. 폰에 sessionEnd 를 보내고(폰이 도감 저장 후 정리) vehicle 쓰기를 멈춘다.
     * 구독은 남겨 둔다: 차 화면은 부화한 생물을 계속 보여 주고, 다음 출발 때 [beginSession] 이 정리한다.
     */
    @Synchronized
    fun endSession(reason: String) {
        if (_ended.value) return
        _ended.value = true
        val id = sessionId; val ready = sessionReady
        debugLog("session end sid=$id reason=$reason")
        scope.launch { runCatching { emitEvent("sessionEnd", id = id, ready = ready) } }
    }

    fun stop() {
        if (!_ended.value) scope.launch { runCatching { emitEvent("sessionEnd") } }
        vehicleReader.stop(); aaos.stop(); voice.release(); naviEta.stop()
        scope.cancel()
    }

    /** 폰이 /game 을 hatched 로 바꾸는 순간 운전자에게 한 번 말한다 (시연 7단계). */
    private suspend fun announceHatch() {
        var prev: String? = null
        _game.collect { g ->
            if (HatchAnnouncement.shouldAnnounce(prev, g.stage)) {
                voice.speak(GleoFunctions.respond(GleoFunctions.CELEBRATE_HATCH, g, bank = dialogue).message)
            }
            prev = g.stage
        }
    }

    private suspend fun createSession(id: String, ready: CompletableDeferred<Unit>) {
        if (!rest.isConfigured) return
        val meta = _meta.value
        while (currentCoroutineContext().isActive) {
            val r = runCatching { rest.put("sessions/$id/meta", rest.json.encodeToString(meta)) }
            if (r.isSuccess) {
                debugLog("session created sid=$id")
                ready.complete(Unit)
                return
            }
            debugLog("session create failed sid=$id: ${r.exceptionOrNull()?.message}")
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
            val id = sessionId; val ready = sessionReady   // 이 순서로 읽는다 (beginSession 주석)
            if (rest.isConfigured && ready.isCompleted && !_ended.value) runCatching { rest.put("sessions/$id/vehicle", rest.json.encodeToString(snap)) }
                .onSuccess { reportWrite(true) }
                .onFailure { reportWrite(false, it) }
            checkSessionEnd(now, a.gear)
            delay(1_000)
        }
    }

    /** 종료 판단, 종료 뒤 출발하면 새 세션. 페어링 전에는 끝내지 않는다 */
    private fun checkSessionEnd(now: Long, gear: String?) {
        if (_ended.value) {
            if (gear != null && gear != "P") { debugLog("new session (gear=$gear)"); beginSession() }
            return
        }
        if (!_meta.value.paired) return
        val arrived = naviEta.arrivedAt.value?.let { it >= sessionStartedAt } == true
        endDetector.update(now, gear, derivation.distanceM, routeActive = naviEta.etaSec.value != null, arrived = arrived)
            ?.let { endSession(it.name.lowercase()) }
    }

    private suspend fun subscribeGame(id: String, ready: CompletableDeferred<Unit>) {
        if (!rest.isConfigured) return
        ready.await()
        var current: JsonObject = JsonObject(emptyMap())
        while (currentCoroutineContext().isActive) {
            runCatching {
                rest.stream("sessions/$id/game").collect { ev ->
                    if (id != sessionId) return@collect   // 이미 다음 세션
                    current = merge(current, ev.path, ev.data)
                    runCatching { rest.json.decodeFromJsonElement<GameState>(current) }.onSuccess { _game.value = it }
                }
            }
            delay(2_000)   // 끊기면 재연결
        }
    }

    /** 페어링 여부는 meta.paired 를 폰이 바꾼다 */
    private suspend fun subscribeMeta(id: String, ready: CompletableDeferred<Unit>) {
        if (!rest.isConfigured) return
        ready.await()
        while (currentCoroutineContext().isActive) {
            runCatching {
                rest.stream("sessions/$id/meta").collect { ev ->
                    if (id != sessionId) return@collect   // 이미 다음 세션
                    if (ev.data is JsonObject && (ev.data as JsonObject)["paired"]?.jsonPrimitive?.booleanOrNull == true)
                        _meta.update { it.copy(paired = true) }
                    if (ev.path == "/paired" && ev.data.jsonPrimitive.booleanOrNull == true)
                        _meta.update { it.copy(paired = true) }
                }
            }
            delay(2_000)
        }
    }

    suspend fun emitEvent(type: String, payload: Map<String, String> = emptyMap(), id: String = sessionId, ready: CompletableDeferred<Unit> = sessionReady) {
        if (!rest.isConfigured || !ready.isCompleted) return
        val ev = GameEvent(ts = System.currentTimeMillis(), type = type, by = "car", payload = payload)
        rest.post("sessions/$id/events", rest.json.encodeToString(ev))
    }

    private fun merge(base: JsonObject, path: String, data: JsonElement): JsonObject {
        if (path == "/" || path.isEmpty()) return data as? JsonObject ?: base
        val key = path.trim('/').substringBefore('/')   // 한 단계 깊이만 (game 노드는 평평하다)
        return JsonObject(base.toMutableMap().apply { if (data is JsonNull) remove(key) else put(key, data) })
    }

    private fun newPairCode(): String = "%06d".format(SecureRandom().nextInt(1_000_000))
}
