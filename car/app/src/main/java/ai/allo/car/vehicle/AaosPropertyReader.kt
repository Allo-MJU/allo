package ai.allo.car.vehicle

import android.car.Car
import android.car.VehicleGear
import android.car.VehiclePropertyIds
import android.car.hardware.CarPropertyValue
import android.car.hardware.property.CarPropertyManager
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * 속도·기어는 Vehicle SDK 가 아니라 AAOS car-lib 로 읽는다 (2.3.2에서 속도 리스너 삭제, Gear 미제공).
 * 권한: android.car.permission.CAR_SPEED, CAR_POWERTRAIN
 */
class AaosPropertyReader(private val context: Context) {
    data class State(val speedKph: Double = 0.0, val gear: String = "P")

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state

    private var car: Car? = null
    private var pm: CarPropertyManager? = null

    private val callback = object : CarPropertyManager.CarPropertyEventCallback {
        override fun onChangeEvent(value: CarPropertyValue<*>) {
            when (value.propertyId) {
                VehiclePropertyIds.PERF_VEHICLE_SPEED -> {
                    val mps = (value.value as? Float) ?: return
                    _state.value = _state.value.copy(speedKph = (mps * 3.6f).toDouble())
                }
                VehiclePropertyIds.GEAR_SELECTION -> {
                    val g = (value.value as? Int) ?: return
                    _state.value = _state.value.copy(gear = gearLetter(g))
                }
            }
        }
        override fun onErrorEvent(propertyId: Int, areaId: Int) {
            Log.w(TAG, "property error id=$propertyId area=$areaId")
        }
    }

    /** @return 속도 구독까지 됐으면 true. false 면 CAR_SPEED 권한 대기 중 */
    fun start(): Boolean {
        val c = Car.createCar(context) ?: run { Log.e(TAG, "Car.createCar returned null"); return false }
        car = c
        val manager = c.getCarManager(Car.PROPERTY_SERVICE) as CarPropertyManager
        pm = manager
        manager.registerCallback(callback, VehiclePropertyIds.GEAR_SELECTION, CarPropertyManager.SENSOR_RATE_ONCHANGE)
        return startSpeed()
    }

    /**
     * CAR_SPEED 는 dangerous 권한이라 런타임 허용 전엔 등록이 막힌다.
     * MainActivity 가 권한을 받은 뒤 다시 부른다. 이미 등록돼 있어도 같은 콜백이라 중복되지 않는다.
     */
    fun startSpeed(): Boolean {
        val manager = pm ?: return false
        if (context.checkSelfPermission(SPEED_PERMISSION) != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "$SPEED_PERMISSION not granted yet")
            return false
        }
        return try {
            manager.registerCallback(callback, VehiclePropertyIds.PERF_VEHICLE_SPEED, CarPropertyManager.SENSOR_RATE_NORMAL)
        } catch (e: SecurityException) {
            Log.w(TAG, "speed register denied", e)
            false
        }
    }

    fun stop() {
        pm?.unregisterCallback(callback)
        car?.disconnect()
        pm = null; car = null
    }

    private fun gearLetter(g: Int): String = when (g) {
        VehicleGear.GEAR_PARK -> "P"
        VehicleGear.GEAR_REVERSE -> "R"
        VehicleGear.GEAR_NEUTRAL -> "N"
        else -> "D"
    }

    companion object {
        private const val TAG = "AaosPropertyReader"
        const val SPEED_PERMISSION = "android.car.permission.CAR_SPEED"
    }
}
