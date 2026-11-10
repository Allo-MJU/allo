package ai.allo.car.mirror

import android.car.Car
import android.car.VehicleGear
import android.car.VehiclePropertyIds
import android.car.drivingstate.CarUxRestrictions
import android.car.drivingstate.CarUxRestrictionsManager
import android.car.hardware.CarPropertyValue
import android.car.hardware.property.CarPropertyManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.util.concurrent.Executors

/** Independent, fail-closed gate: never uses the normal feed's default "P" state. */
class ParkedMirrorGate(
    private val context: Context,
    private val onState: (connected: Boolean, parked: Boolean?, uxAllowed: Boolean?) -> Unit,
) {
    companion object { const val MAX_STATUS_AGE_MS = 1000L }

    private val main = Handler(Looper.getMainLooper())
    private val reader = Executors.newSingleThreadExecutor()
    private var car: Car? = null
    private var properties: CarPropertyManager? = null
    private var restrictions: CarUxRestrictionsManager? = null
    private var alive = false
    private var connected = false
    private var version = 0L
    private var readPending = false

    private val gearCallback = object : CarPropertyManager.CarPropertyEventCallback {
        override fun onChangeEvent(value: CarPropertyValue<*>) {
            if (value.propertyId != VehiclePropertyIds.GEAR_SELECTION) return
            // Any update invalidates a concurrent old snapshot. A new full read is required
            // even for P so an old permissive UX value cannot be paired with a new gear value.
            main.post {
                if (!alive) return@post
                version++
                onState(connected, null, null)
                readCurrent()
            }
        }
        override fun onErrorEvent(propertyId: Int, areaId: Int) {
            if (propertyId == VehiclePropertyIds.GEAR_SELECTION) main.post {
                if (!alive) return@post
                version++
                onState(connected, null, null)
            }
        }
    }

    private val uxCallback = CarUxRestrictionsManager.OnUxRestrictionsChangedListener {
        main.post {
            if (!alive) return@post
            version++
            onState(connected, null, null)
            readCurrent()
        }
    }

    private val heartbeat = object : Runnable {
        override fun run() {
            if (!alive) return
            readCurrent()
            main.postDelayed(this, 400)
        }
    }

    fun start() {
        if (alive) return
        alive = true
        onState(false, null, null)
        try {
            car = Car.createCar(context, main, Car.CAR_WAIT_TIMEOUT_DO_NOT_WAIT) { readyCar, ready ->
                main.post {
                    if (!alive) return@post
                    version++
                    connected = ready
                    onState(false, null, null)
                    detachManagers()
                    if (!ready) return@post
                    try {
                        car = readyCar
                        properties = readyCar.getCarManager(Car.PROPERTY_SERVICE) as CarPropertyManager
                        restrictions = readyCar.getCarManager(Car.CAR_UX_RESTRICTION_SERVICE) as CarUxRestrictionsManager
                        val subscribed = properties!!.registerCallback(
                            gearCallback, VehiclePropertyIds.GEAR_SELECTION, CarPropertyManager.SENSOR_RATE_ONCHANGE)
                        check(subscribed)
                        restrictions!!.registerListener(uxCallback)
                        readCurrent()
                    } catch (_: Exception) {
                        connected = false
                        detachManagers()
                        onState(false, null, null)
                    }
                }
            }
        } catch (_: Exception) {
            onState(false, null, null)
        }
        main.post(heartbeat)
    }

    private fun readCurrent() {
        if (!alive || !connected || readPending) return
        val c = car ?: return
        val pm = properties ?: return
        val ux = restrictions ?: return
        val ticket = version
        val startedAt = SystemClock.elapsedRealtime()
        readPending = true
        reader.execute {
            var parked: Boolean? = null
            var allowed: Boolean? = null
            var available = false
            try {
                available = c.isConnected
                if (available) {
                    val gear = pm.getProperty<Int>(VehiclePropertyIds.GEAR_SELECTION, 0)
                    if (gear.status == CarPropertyValue.STATUS_AVAILABLE) {
                        parked = gear.value == VehicleGear.GEAR_PARK
                    }
                    val state = ux.currentCarUxRestrictions
                    allowed = !state.isRequiresDistractionOptimization &&
                        state.activeRestrictions and CarUxRestrictions.UX_RESTRICTIONS_NO_VIDEO == 0
                }
            } catch (_: Exception) {
                parked = null
                allowed = null
            }
            main.post {
                readPending = false
                if (!alive || ticket != version) return@post
                if (SystemClock.elapsedRealtime() - startedAt >= MAX_STATUS_AGE_MS) {
                    onState(connected, null, null)
                } else {
                    onState(available && connected, parked, allowed)
                }
            }
        }
    }

    private fun detachManagers() {
        runCatching { properties?.unregisterCallback(gearCallback) }
        runCatching { restrictions?.unregisterListener() }
        properties = null
        restrictions = null
    }

    fun close() {
        alive = false
        connected = false
        version++
        main.removeCallbacks(heartbeat)
        onState(false, null, null)
        detachManagers()
        runCatching { car?.disconnect() }
        car = null
        reader.shutdownNow()
    }
}
