package ai.allo.car.model

import java.util.UUID

data class PairingRefreshUi(val busy: Boolean = false, val message: String? = null)
data class PairingRefreshRequest(val sessionId: String, val requestId: String)

/** Keeps the same id on an uncertain response; never replaces an established pairing. */
class PairingRefresh(private val nextId: () -> String = { UUID.randomUUID().toString() }) {
    var ui = PairingRefreshUi(); private set
    private var request: PairingRefreshRequest? = null

    fun begin(sessionId: String, paired: Boolean, parked: Boolean, ended: Boolean, ready: Boolean): PairingRefreshRequest? {
        if (paired || !parked || ended || !ready || ui.busy) return null
        val next = request?.takeIf { it.sessionId == sessionId } ?: PairingRefreshRequest(sessionId, nextId())
        request = next
        ui = PairingRefreshUi(busy = true)
        return next
    }
    fun complete(value: PairingRefreshRequest, success: Boolean) {
        if (request != value) return
        ui = if (success) PairingRefreshUi() else PairingRefreshUi(message = "새 코드를 확인하지 못했어요. 다시 확인해 주세요.")
        if (success) request = null
    }
    fun reset() { request = null; ui = PairingRefreshUi() }
}
