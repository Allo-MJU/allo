package ai.allo.car.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import java.util.UUID

@Serializable
data class FishingSnapshot(
    val version: Int, val leaseId: String, val displayId: String, val displayRevision: Long,
    val activityId: String, val cycle: Long, val state: String, val elapsedMs: Long,
    val targetMs: Long, val totalRecords: Long, val rewardName: String? = null,
    val requestId: String? = null,
) {
    fun appliesTo(game: GameState): Boolean = game.hasV2Contract && "fishing" !in game.invalidBlocks &&
        "companion" !in game.invalidBlocks && game.companion?.let {
            it.location == "car" && it.displayId == displayId && it.displayRevision == displayRevision
        } == true
    fun display() = FishingDisplay((elapsedMs / 1000).toInt(), (targetMs / 1000).toInt(),
        rewardName.takeIf { state == "reward" }, totalRecords.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
    fun route(): PleosRoute? = when (state) {
        "running" -> PleosRoute.Fishing; "saving" -> PleosRoute.Saving; "reward" -> PleosRoute.Reward
        "paused" -> PleosRoute.Paused; "saveFailed" -> PleosRoute.SaveFailed; else -> null
    }
}

@Serializable
data class FishingPresence(val version: Int = 1, val leaseId: String, val epoch: String,
    val sequence: Long, val active: Boolean, val parkedAllowed: Boolean)

data class FishingRequest(val requestId: String, val leaseId: String, val displayId: String,
    val displayRevision: Long, val action: String, val activityId: String, val cycle: Long)

data class FishingUiState(val available: Boolean = false, val pending: FishingRequest? = null,
    val unconfirmed: Boolean = false) {
    val message: String? get() = when {
        pending != null && unconfirmed -> "폰의 결과를 확인 중이에요. 연결을 확인한 뒤 같은 요청을 다시 확인해 주세요."
        pending != null -> "폰에서 요청을 확인하고 있어요."
        !available -> "폰의 최신 낚시 상태를 기다리고 있어요."
        else -> null
    }
}

/** Vehicle sends intent only. All progress and rewards come from persisted phone snapshots. */
class FishingController(private val idFactory: () -> String = { UUID.randomUUID().toString() }) {
    var ui = FishingUiState(); private set
    private var boundSession: String? = null
    private var startedAt = 0L
    fun observe(session: String, game: GameState, permitted: Boolean, nowMs: Long) {
        val f = game.fishing?.takeIf { it.appliesTo(game) }
        val valid = permitted && session.isNotBlank() && f != null
        val p = ui.pending
        val same = boundSession == session && f != null && p?.let {
            it.leaseId == f.leaseId && it.displayId == f.displayId && it.displayRevision == f.displayRevision
        } != false
        boundSession = session
        if (!valid || !same) { ui = FishingUiState(available = valid); return }
        // A reported storage failure is not an unconfirmed network request. Release the intent
        // so the user can send action=retry for the phone's pending write, never resend start.
        if (p != null && p.action != "retry" && f!!.state == "saveFailed") { ui = FishingUiState(true); return }
        // A matching receipt may advance activity/cycle. It must be considered before old-scope clearing.
        if (p != null && f!!.requestId == p.requestId) { ui = FishingUiState(true); return }
        if (p != null && f != null && (p.activityId != f.activityId || p.cycle != f.cycle)) {
            ui = FishingUiState(true); return
        }
        ui = ui.copy(available = true, unconfirmed = p != null && nowMs - startedAt >= 10_000)
    }
    fun request(session: String, game: GameState, permitted: Boolean, action: String, nowMs: Long): FishingRequest? {
        observe(session, game, permitted, nowMs)
        val f = game.fishing ?: return null
        if (!ui.available || ui.pending != null || nowMs < 0) return null
        val allowed = when (action) {
            "start" -> f.state == "ready"
            "pause" -> f.state in setOf("running", "reward")
            "resume" -> f.state == "paused"
            "retry" -> f.state == "saveFailed"
            else -> false
        }
        if (!allowed) return null
        val id = idFactory().takeIf { it.isNotBlank() } ?: return null
        return FishingRequest(id, f.leaseId, f.displayId, f.displayRevision, action, f.activityId, f.cycle).also {
            startedAt = nowMs; ui = FishingUiState(true, it)
        }
    }
    fun retry(session: String, game: GameState, permitted: Boolean, nowMs: Long): FishingRequest? {
        observe(session, game, permitted, nowMs)
        if (!ui.available || !ui.unconfirmed) return null
        return ui.pending?.also { startedAt = nowMs; ui = ui.copy(unconfirmed = false) }
    }
}

fun fishingRequestEvent(request: FishingRequest, timestamp: Long): JsonObject = buildJsonObject {
    put("ts", timestamp); put("type", "fishingRequested"); put("by", "car")
    put("payload", buildJsonObject {
        put("requestId", request.requestId); put("leaseId", request.leaseId); put("displayId", request.displayId)
        put("displayRevision", request.displayRevision); put("action", request.action)
        put("activityId", request.activityId); put("cycle", request.cycle)
    })
}
