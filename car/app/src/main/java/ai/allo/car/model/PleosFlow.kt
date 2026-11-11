package ai.allo.car.model

/** Presentation states, not a new phone wire contract. Fishing/selection states require an adapter. */
enum class PleosRoute(val label: String) {
    Starting("시작"), Permission("권한 안내"), Pairing("폰 연결"), Driving("주행"),
    Home("주차 홈"), Disconnected("연결 끊김"), Ended("세션 종료"), Empty("동행 없음"),
    TransferPending("폰 이동 대기"), TransferComplete("폰 이동 완료"), TransferRejected("폰 이동 거절"),
    Fishing("낚시 진행"), Saving("보상 저장 중"), Reward("보상 획득"), Paused("쉬는 시간"),
    SaveFailed("저장 실패"), SelectionPending("선택 변경 중"), SelectionFailed("선택 변경 실패"),
}

object PleosFlow {
    fun route(
        parkingChecked: Boolean, parkedAllowed: Boolean, permissionNotice: Boolean,
        paired: Boolean, connected: Boolean, ended: Boolean, game: GameState,
        transfer: TransferUiState = TransferUiState(), dismissTransfer: Boolean = false,
        dismissFishing: Boolean = false,
    ): PleosRoute = when {
        !parkingChecked -> PleosRoute.Starting
        !parkedAllowed -> PleosRoute.Driving
        ended -> PleosRoute.Ended
        paired && !connected -> PleosRoute.Disconnected
        permissionNotice -> PleosRoute.Permission
        !paired -> PleosRoute.Pairing
        !dismissTransfer && transfer.appliesTo(game) && transfer.pending != null -> PleosRoute.TransferPending
        !dismissTransfer && transfer.appliesTo(game) && transfer.status in setOf(TransferStatus.Accepted, TransferStatus.AlreadyOnPhone) &&
            (game.companion == null || game.companion?.location == "phone") && "companion" !in game.invalidBlocks -> PleosRoute.TransferComplete
        !dismissTransfer && transfer.appliesTo(game) && transfer.status in setOf(TransferStatus.Busy, TransferStatus.StaleSelection, TransferStatus.NoCompanion, TransferStatus.Unsupported) -> PleosRoute.TransferRejected
        game.hasV2Contract && "companion" !in game.invalidBlocks &&
            (game.companion?.location == "phone" || game.companion == null && game.stage != "incubating") -> PleosRoute.Empty
        else -> game.fishing?.takeIf { !dismissFishing && it.appliesTo(game) }?.route() ?: PleosRoute.Home
    }
}

/** Only explicit, validated phone progress may populate this presentation model. No wall-clock accrual. */
data class FishingDisplay(val elapsedSeconds: Int, val targetSeconds: Int, val rewardName: String? = null, val totalRecords: Int? = null) {
    val progress: Float get() = if (targetSeconds > 0) (elapsedSeconds.toFloat() / targetSeconds).coerceIn(0f, 1f) else 0f
}
