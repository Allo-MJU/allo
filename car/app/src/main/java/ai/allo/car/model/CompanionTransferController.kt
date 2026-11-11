package ai.allo.car.model

import java.util.UUID

/** Immutable event payload. Retrying must reuse all of these original identifiers. */
data class TransferRequest(
    val requestId: String,
    val displayId: String,
    val displayRevision: Long,
    val target: String = "phone",
)

enum class TransferStatus {
    Idle, Waiting, Unconfirmed, Accepted, AlreadyOnPhone, Busy, StaleSelection,
    Disconnected, Ended, NoCompanion, Unsupported,
}

data class TransferUiState(
    val status: TransferStatus = TransferStatus.Idle,
    val message: String = "",
    val pending: TransferRequest? = null,
    val exitSerial: Long = 0,
)

/**
 * Read-only vehicle-side request tracking. Only the phone's matching persisted result
 * confirms a move. No timers, network writes, retries or game-state mutation occur here.
 */
class CompanionTransferController(
    private val requestIdFactory: () -> String = { UUID.randomUUID().toString() },
) {
    @Volatile var state = TransferUiState()
        private set
    private var sessionId: String? = null
    private var ended = false
    private var highestGameRevision = -1L
    private var attemptStartedAt = 0L
    private var refreshRequested = false

    @Synchronized
    fun request(sessionId: String, game: GameState, connected: Boolean, nowMs: Long): TransferRequest? {
        if (!prepare(sessionId, game, connected) || nowMs < 0 || state.pending != null) return null
        val companion = game.companion
        if (companion == null) {
            status(TransferStatus.NoCompanion, "폰에서 함께할 친구를 먼저 골라 주세요.")
            return null
        }
        if (companion.location == "phone") {
            status(TransferStatus.AlreadyOnPhone, "친구가 이미 폰에 있어요.")
            return null
        }
        if (companion.location != "car" || companion.displayId.isBlank() || companion.displayRevision < 0) {
            status(TransferStatus.Unsupported, "캐릭터 선택 정보를 다시 확인해 주세요.")
            return null
        }
        val id = requestIdFactory()
        if (id.isBlank()) {
            status(TransferStatus.Unsupported, "이동 요청을 준비하지 못했어요.")
            return null
        }
        val request = TransferRequest(id, companion.displayId, companion.displayRevision)
        waitFor(request, nowMs)
        return request
    }

    @Synchronized
    fun observe(sessionId: String, game: GameState, connected: Boolean, ended: Boolean = false) {
        bindSession(sessionId)
        if (ended) {
            endSession()
            return
        }
        if (!prepare(sessionId, game, connected)) return
        val pending = state.pending ?: return
        // Results are independent of companion: an accepted move can remove that block.
        val result = game.transferResult ?: return
        if (result.requestId != pending.requestId || result.displayId != pending.displayId ||
            result.requestRevision != pending.displayRevision) return
        when (result.status) {
            "accepted" -> {
                if (result.resultLocation != "phone") return
                // A late result for the former selection must never dismiss a new pet.
                val current = game.companion
                val sameDisplay = current == null || current.displayId == pending.displayId &&
                    (current.displayRevision == pending.displayRevision || current.location == "phone")
                state = TransferUiState(TransferStatus.Accepted, "폰에서 친구를 만나 보세요.",
                    exitSerial = state.exitSerial + if (sameDisplay) 1 else 0)
            }
            "alreadyOnPhone" -> {
                if (result.resultLocation != "phone") return
                status(TransferStatus.AlreadyOnPhone, "친구가 이미 폰에 있어요.")
            }
            "busy" -> status(TransferStatus.Busy, "친구가 다른 활동 중이에요. 잠시 후 다시 불러 주세요.")
            "staleSelection" -> status(TransferStatus.StaleSelection, "선택한 친구가 바뀌었어요. 폰에서 다시 확인해 주세요.")
        }
    }

    /** True once per send attempt: the caller should re-read /game, not auto-resend. */
    @Synchronized
    fun checkTimeout(nowMs: Long): Boolean {
        if (state.pending == null || refreshRequested || nowMs < attemptStartedAt ||
            nowMs - attemptStartedAt < TIMEOUT_MS) return false
        refreshRequested = true
        state = state.copy(status = TransferStatus.Unconfirmed,
            message = "이동 결과를 확인 중이에요. 폰이 켜져 있고 연결돼 있는지 확인해 주세요.")
        return true
    }

    /** Explicit user retry only; do not create a new request ID or retarget a changed selection. */
    @Synchronized
    fun retry(sessionId: String, game: GameState, connected: Boolean, nowMs: Long): TransferRequest? {
        if (!prepare(sessionId, game, connected) || nowMs < 0) return null
        val pending = state.pending ?: return null
        waitFor(pending, nowMs)
        return pending
    }

    @Synchronized
    fun disconnect() {
        if (!ended) status(TransferStatus.Disconnected, "폰 연결을 확인해 주세요. 폰에서 직접 친구를 불러올 수도 있어요.")
    }

    @Synchronized
    fun endSession() {
        ended = true
        status(TransferStatus.Ended, "주행이 끝났어요. 다음 연결에서 다시 불러 주세요.")
    }

    private fun bindSession(id: String) {
        if (sessionId == id) return
        sessionId = id
        ended = false
        highestGameRevision = -1L
        state = TransferUiState(exitSerial = state.exitSerial)
        refreshRequested = false
    }

    private fun prepare(id: String, game: GameState, connected: Boolean): Boolean {
        bindSession(id)
        if (ended) return false
        if (!connected || id.isBlank()) {
            disconnect()
            return false
        }
        if (!game.hasV2Contract) {
            status(TransferStatus.Unsupported, "캐릭터 이동을 지원하는 폰 연결이 필요해요.")
            return false
        }
        val revision = game.gameRevision!!
        if (revision < highestGameRevision) return false
        highestGameRevision = revision
        if (state.status == TransferStatus.Disconnected || state.status == TransferStatus.Unsupported) {
            status(TransferStatus.Idle, "")
        }
        return true
    }

    private fun waitFor(request: TransferRequest, nowMs: Long) {
        attemptStartedAt = nowMs
        refreshRequested = false
        state = state.copy(status = TransferStatus.Waiting, message = "폰의 이동 결과를 기다리고 있어요.", pending = request)
    }

    private fun status(status: TransferStatus, message: String) {
        state = TransferUiState(status, message, exitSerial = state.exitSerial)
    }

    companion object { const val TIMEOUT_MS = 10_000L }
}
