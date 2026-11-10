package ai.allo.car.model

/** Parking controls require a verified permissive state, never the vehicle feed's default P. */
object CarDisplayPolicy {
    fun screen(paired: Boolean, parkedAllowed: Boolean): CarScreen = when {
        !parkedAllowed -> CarScreen.Driving
        !paired -> CarScreen.Pairing
        else -> CarScreen.Parked
    }
}

/** Reopen a configured share only on a verified driving -> parking transition, not every resume. */
class ParkedShareTransition {
    private var sawDriving = false
    fun update(connected: Boolean, parked: Boolean?, uxAllowed: Boolean?, configured: Boolean): Boolean {
        if (connected && parked == false) sawDriving = true
        if (!connected || parked != true || uxAllowed != true) return false
        val reopen = sawDriving && configured
        sawDriving = false
        return reopen
    }
}
