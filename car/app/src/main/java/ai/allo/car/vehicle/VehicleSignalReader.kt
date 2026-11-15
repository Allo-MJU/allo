package ai.allo.car.vehicle

import android.content.Context
import android.util.Log
import ai.allo.car.model.Capability
import ai.pleos.playground.vehicle.Vehicle
import ai.pleos.playground.vehicle.api.model.area.SeatArea
import ai.pleos.playground.vehicle.api.model.area.WindowArea
import ai.pleos.playground.vehicle.constant.area.SeatValue
import ai.pleos.playground.vehicle.constant.area.WindowValue
import ai.pleos.playground.vehicle.constant.control.LightState
import ai.pleos.playground.vehicle.constant.control.WiperState
import ai.pleos.playground.vehicle.listener.BrakePedalStatusListener
import ai.pleos.playground.vehicle.listener.DistanceDrivenListener
import ai.pleos.playground.vehicle.listener.LightStateListener
import ai.pleos.playground.vehicle.listener.SeatOccupancyListener
import ai.pleos.playground.vehicle.listener.SteeringWheelAngleListener
import ai.pleos.playground.vehicle.listener.WiperStateListener
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

/**
 * Pleos Vehicle SDK 구독 레이어. 공식 샘플의 Door 패턴을 따른다:
 *   initialize() → checkXXXCapabilities() → registerXXX(listener) → unregisterXXX() → release()
 *
 * 판정하지 않는다. 원본 값을 SignalMapping 으로 단위·형태만 맞춰 Raw 에 담는다.
 * 메서드·값은 docs/verification.md 의 에뮬레이터 실측 기준. 리스너는 세션보다 오래 살지 않는다.
 */
class VehicleSignalReader(context: Context, private val caps: CapabilityChecker) {
    private val vehicle = Vehicle(context.applicationContext)

    data class Raw(
        val wiperLevel: Int = 0,
        val headlightOn: Boolean = false,
        val seatRow2Occupied: Boolean = false, // SeatPolarity 반전 처리 후
        val odometerM: Double? = null,         // SDK km → m
        val steerDeg: Double? = null,          // ⚠️ 부호가 VC 와 반대. 급조향은 절댓값이라 무관
        val brakePressed: Boolean = false,
    )

    private val _raw = MutableStateFlow(Raw())
    val raw: StateFlow<Raw> = _raw

    private val frontWindshield = WindowArea(WindowValue.FRONT_WINDSHIELD)
    @Volatile private var wiperSwitch: String? = null
    @Volatile private var wiperOn: Boolean? = null
    private val row2Seats = ConcurrentHashMap<SeatArea, Boolean>()

    private val unregisters = mutableListOf<() -> Unit>()
    @Volatile private var started = false
    private val cornering = CorneringSignal()
    @Volatile private var steeringEpoch = 0L

    fun start() {
        if (started) return
        try {
            vehicle.initialize()
        } catch (e: Exception) {
            Log.e(TAG, "Vehicle SDK initialize failed", e)
            return
        }
        started = true
        steeringEpoch++
        startWiper()
        startLowBeam()
        startSeatRow2()
        startOdometer()
        startSteering()
        startBrake()
    }

    fun stop() {
        if (!started) return
        started = false
        steeringEpoch++
        invalidateCornering()
        synchronized(unregisters) {
            unregisters.forEach { runCatching(it).onFailure { e -> Log.w(TAG, "unregister failed", e) } }
            unregisters.clear()
        }
        runCatching { vehicle.release() }
        started = false
    }

    // --- Wiper (#1): WiperState 는 리스너, WiperSwitch 는 리스너가 없어 State 변화 때 다시 읽는다 ---

    private val wiperListener = object : WiperStateListener {
        override fun onWiperStateUpdated(state: WiperState?) {
            wiperOn = state?.let { it == WiperState.ON }
            refreshWiperSwitch()
        }
        override fun onFailed(e: Exception) = logFail(Capability.WIPER, e)
    }

    private fun startWiper() {
        val wiper = vehicle.getWiper()
        wiper.checkWiperStateCapabilities({ _, _ ->
            caps.mark(Capability.WIPER, true)
            register({ wiper.registerWiperState(frontWindshield, wiperListener) },
                { wiper.unregisterWiperState(frontWindshield, wiperListener) })
            refreshWiperSwitch()
        }, { unsupported(Capability.WIPER, it) })
    }

    private fun refreshWiperSwitch() {
        vehicle.getWiper().getCurrentWiperSwitch(frontWindshield, { s ->
            wiperSwitch = s?.name
            _raw.update { it.copy(wiperLevel = SignalMapping.wiperLevel(wiperSwitch, wiperOn)) }
        }, { logFail(Capability.WIPER, it) })
    }

    // --- 하향등 (#2): 스위치가 아니라 실제 점등 상태. 실차 Auto 모드 터널 점등을 잡기 위해 ---

    private val lowBeamListener = object : LightStateListener {
        override fun onLightStateUpdated(state: LightState?) {
            _raw.update { it.copy(headlightOn = SignalMapping.headlightOn(state?.name)) }
        }
        override fun onFailed(e: Exception) = logFail(Capability.LIGHT, e)
    }

    private fun startLowBeam() {
        val light = vehicle.getLight()
        light.checkLowBeamLightStateCapabilities({ _, _ ->
            caps.mark(Capability.LIGHT, true)
            register({ light.registerLowBeamLightState(lowBeamListener) },
                { light.unregisterLowBeamLightState(lowBeamListener) })
            light.getCurrentLowBeamLightState({ s -> lowBeamListener.onLightStateUpdated(s) }, { logFail(Capability.LIGHT, it) })
        }, { unsupported(Capability.LIGHT, it) })
    }

    // --- 2열 좌석 점유 (#8): 좌석별 원본값을 모아 SeatPolarity 로 한 번에 판정 ---

    private fun startSeatRow2() {
        val seat = vehicle.getSeat()
        seat.checkSeatOccupancyCapabilities({ _, areas ->
            val row2 = areas.filter { area -> area.values.any { it in ROW2 } }
            caps.mark(Capability.SEAT, row2.isNotEmpty())
            row2.forEach { area ->
                val listener = object : SeatOccupancyListener {
                    override fun onSeatOccupancyUpdated(occupied: Boolean?) = onSeatRaw(area, occupied)
                    override fun onFailed(e: Exception) = logFail(Capability.SEAT, e)
                }
                register({ seat.registerSeatOccupancy(area, listener) }, { seat.unregisterSeatOccupancy(area, listener) })
                seat.getCurrentSeatOccupancy(area, { onSeatRaw(area, it) }, { logFail(Capability.SEAT, it) })
            }
        }, { unsupported(Capability.SEAT, it) })
    }

    private fun onSeatRaw(area: SeatArea, sdkValue: Boolean?) {
        if (sdkValue == null) row2Seats.remove(area) else row2Seats[area] = sdkValue
        _raw.update { it.copy(seatRow2Occupied = SeatPolarity.anyOccupied(row2Seats.values)) }
    }

    // --- Odometer (#4): km Float. 에뮬레이터는 주행으로 안 늘어나 SignalDerivation 이 속도 적분으로 폴백 ---

    private val odometerListener = object : DistanceDrivenListener {
        override fun onDistanceDrivenUpdated(km: Float?) {
            _raw.update { it.copy(odometerM = SignalMapping.odometerM(km)) }
        }
        override fun onFailed(e: Exception) = logFail(Capability.ODOMETER, e)
    }

    private fun startOdometer() {
        val odometer = vehicle.getOdometer()
        odometer.checkCurrentDistanceDrivenCapabilities({
            caps.mark(Capability.ODOMETER, true)
            register({ odometer.registerDistanceDriven(odometerListener) },
                { odometer.unregisterDistanceDriven(odometerListener) })
        }, { unsupported(Capability.ODOMETER, it) })
    }

    // --- 조향각 ---

    private val steeringListener = object : SteeringWheelAngleListener {
        override fun onSteeringWheelAngleUpdated(deg: Float?) {
            synchronized(cornering) {
                if (!started) return
                _raw.update { it.copy(steerDeg = deg?.toDouble()) }
                cornering.receive(deg?.toDouble())
            }
        }
        override fun onFailed(e: Exception) {
            invalidateCornering()
            logFail(Capability.STEERING, e)
        }
    }

    private fun startSteering() {
        val wheel = vehicle.getSteeringWheel()
        wheel.checkSteeringWheelAngleCapabilities({ _, _ ->
            caps.mark(Capability.STEERING, true)
            register({ wheel.registerSteeringWheelAngle(steeringListener) },
                { wheel.unregisterSteeringWheelAngle(steeringListener) })
            pollSteering()
        }, { invalidateCornering(); unsupported(Capability.STEERING, it) })
    }

    private fun invalidateCornering() = synchronized(cornering) {
        cornering.invalidate()
    }

    /** Read-only refresh for a held wheel angle. SDK success does not guarantee a new hardware sample. */
    fun pollSteering() {
        if (!started || !caps.has(Capability.STEERING)) return
        val epoch = steeringEpoch
        val request = cornering.beginRead()
        try {
            vehicle.getSteeringWheel().getCurrentSteeringWheelAngle({ degrees ->
                synchronized(cornering) {
                    if (started && epoch == steeringEpoch) cornering.completeRead(request, degrees?.toDouble())
                }
            }, { error ->
                synchronized(cornering) {
                    if (started && epoch == steeringEpoch) {
                        cornering.failRead(request)
                        logFail(Capability.STEERING, error)
                    }
                }
            })
        } catch (error: Exception) {
            synchronized(cornering) {
                if (started && epoch == steeringEpoch) cornering.failRead(request)
            }
            logFail(Capability.STEERING, error)
        }
    }

    fun corneringSnapshot(gear: String, speedKph: Double, speedFresh: Boolean) =
        cornering.snapshotCurrent(gear, speedKph, caps.has(Capability.STEERING), speedFresh)

    // --- 브레이크 페달 ---

    private val brakeListener = object : BrakePedalStatusListener {
        override fun onBrakePedalStatusUpdated(pressed: Boolean?) {
            _raw.update { it.copy(brakePressed = pressed == true) }
        }
        override fun onFailed(e: Exception) = logFail(Capability.BRAKE, e)
    }

    private fun startBrake() {
        val brake = vehicle.getBrake()
        brake.checkBrakePedalStatusCapabilities({
            caps.mark(Capability.BRAKE, true)
            register({ brake.registerBrakePedalStatus(brakeListener) },
                { brake.unregisterBrakePedalStatus(brakeListener) })
        }, { unsupported(Capability.BRAKE, it) })
    }

    // --- 공통 ---

    private fun register(doRegister: () -> Unit, doUnregister: () -> Unit) {
        try {
            doRegister()
            synchronized(unregisters) { unregisters += doUnregister }
        } catch (e: Exception) {
            Log.w(TAG, "register failed", e)
        }
    }

    private fun unsupported(name: String, e: Exception) {
        caps.mark(name, false)
        Log.w(TAG, "$name not supported: ${e.message}")
    }

    private fun logFail(name: String, e: Exception) {
        Log.w(TAG, "$name read failed: ${e.message}")
    }

    private companion object {
        const val TAG = "VehicleSignalReader"
        val ROW2 = setOf(SeatValue.ROW_2_LEFT, SeatValue.ROW_2_CENTER, SeatValue.ROW_2_RIGHT)
    }
}
