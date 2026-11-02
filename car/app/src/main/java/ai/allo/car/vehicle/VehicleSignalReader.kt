package ai.allo.car.vehicle

import android.content.Context
import android.util.Log
import ai.allo.car.model.Capability
import ai.pleos.playground.vehicle.Vehicle
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Pleos Vehicle SDK 구독 레이어. 공식 샘플의 Door 패턴을 따른다:
 *   initialize() → checkXXXCapabilities() → registerXXX(listener) → unregisterXXX() → release()
 *
 * 각 도메인의 정확한 메서드명·리스너 타입은 샘플앱 VehicleApiExplorer 로 확인한 뒤 TODO 를 채운다
 * (Wiper, Light, Seat, Odometer, Brake, SteeringWheel 도메인). 리스너는 세션보다 오래 살지 않는다.
 */
class VehicleSignalReader(context: Context, private val caps: CapabilityChecker) {
    private val vehicle = Vehicle(context.applicationContext)

    data class Raw(
        val wiperLevel: Int = 0,
        val headlightOn: Boolean = false,
        val seatRow2Raw: Boolean? = null,   // SDK 원본값. SeatPolarity 로 뒤집는다
        val odometerM: Double? = null,
        val steerDeg: Double? = null,
        val brakePressed: Boolean = false,
    )

    private val _raw = MutableStateFlow(Raw())
    val raw: StateFlow<Raw> = _raw

    fun start() {
        vehicle.initialize()
        // TODO(A, 검증 #1~#8): 도메인별 capability 확인 후 리스너 등록.
        //  예) vehicle.getWiper().checkXxxCapabilities(onComplete = { _, _ -> caps.mark(Capability.WIPER, true); registerWiper() }, onFailed = { caps.mark(Capability.WIPER, false) })
        //  - Wiper      → _raw.update { it.copy(wiperLevel = ...) }
        //  - Light      → headlightOn
        //  - Seat ROW_2 → seatRow2Raw (반전은 SeatPolarity 에서)
        //  - Odometer   → odometerM (해상도 기록: docs/verification.md #4)
        //  - Brake / SteeringWheel → brakePressed, steerDeg
        Log.i(TAG, "Vehicle SDK initialize requested")
    }

    fun stop() {
        // TODO(A): 등록한 리스너 전부 unregister 한 뒤 release
        vehicle.release()
    }

    private companion object { const val TAG = "VehicleSignalReader" }
}
