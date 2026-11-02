package ai.allo.car.vehicle

import android.car.Car
import android.car.VehicleGear
import android.car.VehiclePropertyIds
import android.car.hardware.CarPropertyValue
import android.car.hardware.property.CarPropertyManager
import android.content.Context
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

    fun start() {
        val c = Car.createCar(context) ?: run { Log.e(TAG, "Car.createCar returned null"); return }
        car = c
        val manager = c.getCarManager(Car.PROPERTY_SERVICE) as CarPropertyManager
        pm = manager
        manager.registerCallback(callback, VehiclePropertyIds.PERF_VEHICLE_SPEED, CarPropertyManager.SENSOR_RATE_NORMAL)
        manager.registerCallback(callback, VehiclePropertyIds.GEAR_SELECTION, CarPropertyManager.SENSOR_RATE_ONCHANGE)
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

    private companion object { const val TAG = "AaosPropertyReader" }
}
