package ai.allo.car.sync

import android.content.Context
import android.content.Intent
import android.os.Build
import ai.allo.car.BuildConfig
import ai.allo.car.model.*
import ai.allo.car.vehicle.*
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

    val sessionId: String = UUID.randomUUID().toString()
    private val _meta = MutableStateFlow(
        SessionMeta(createdAt = System.currentTimeMillis(), pairCode = newPairCode(), carAppVersion = BuildConfig.CAR_APP_VERSION)
    )
    val meta: StateFlow<SessionMeta> = _meta
    private val _game = MutableStateFlow(GameState())
    val game: StateFlow<GameState> = _game
    private val _vehicle = MutableStateFlow<VehicleSnapshot?>(null)
    val vehicle: StateFlow<VehicleSnapshot?> = _vehicle
    /** 내비 ETA. NaviHelper 연동 후 NaviEtaReader 가 채운다. 없으면 null → 폰은 거리 폴백 */
    val etaSec = MutableStateFlow<Long?>(null)

    val screen: StateFlow<CarScreen> = combine(_meta, aaos.state) { m, a ->
        when {
            !m.paired -> CarScreen.Pairing
            a.gear == "P" -> CarScreen.Parked        // 검증 #6 뒤 CarUxRestrictions 판정으로 교체
            else -> CarScreen.Driving
        }
    }.stateIn(scope, SharingStarted.Eagerly, CarScreen.Pairing)

    private var started = false

    fun ensureStarted() {
        if (started) return
        started = true
        context.startForegroundService(Intent(context, SessionService::class.java))
        caps.assumeAaos()
        if (!aaos.start()) caps.mark(Capability.SPEED, false) // 권한 허용 후 onSpeedPermissionGranted 에서 다시 true
        vehicleReader.start()
        scope.launch { createSession() }
        scope.launch { publishLoop() }
        scope.launch { subscribeGame() }
    }

    /** MainActivity 가 CAR_SPEED 런타임 권한을 받은 뒤 호출. */
    fun onSpeedPermissionGranted() {
        if (aaos.startSpeed()) caps.mark(Capability.SPEED, true)
    }

    fun stop() {
        scope.launch { runCatching { emitEvent("sessionEnd") } }
        vehicleReader.stop(); aaos.stop()
        scope.cancel()
    }

    private suspend fun createSession() {
        if (!rest.isConfigured) return
        runCatching { rest.put("sessions/$sessionId/meta", rest.json.encodeToString(_meta.value)) }
    }

    /** 1초 주기. 변화가 없어도 ts 는 갱신한다 (폰이 연결 상태를 알 수 있게). */
    private suspend fun publishLoop() {
        while (currentCoroutineContext().isActive) {
            val now = System.currentTimeMillis()
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
                etaSec = etaSec.value,
                envTags = envTagger.tags(now, a.speedKph, r.wiperLevel, r.headlightOn, regionTagger.tag(null, null)),
                capabilities = caps.snapshot(),
            )
            if (BuildConfig.DEBUG && snap.copy(ts = 0) != _vehicle.value?.copy(ts = 0)) {
                android.util.Log.d("SessionManager", "vehicle $snap") // 디버그 빌드만. 값이 바뀔 때만
            }
            _vehicle.value = snap
            if (rest.isConfigured) runCatching { rest.put("sessions/$sessionId/vehicle", rest.json.encodeToString(snap)) }
            delay(1_000)
        }
    }

    private suspend fun subscribeGame() {
        if (!rest.isConfigured) return
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
        if (!rest.isConfigured) return
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
