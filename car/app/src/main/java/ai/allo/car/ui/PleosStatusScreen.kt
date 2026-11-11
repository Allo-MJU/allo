package ai.allo.car.ui

import ai.allo.car.model.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp

/** Shared production/preview renderer. No timers, rewards, writes, or inferred phone outcomes. */
@Composable
fun PleosStatusScreen(
    route: PleosRoute, game: GameState, connected: Boolean = true,
    fishing: FishingDisplay? = null, transferMessage: String? = null,
    onPrimary: (() -> Unit)? = null, onSecondary: (() -> Unit)? = null,
    departure: PetSummary? = null, departureFraction: Float = 1f,
    motionAllowed: Boolean = true, requestMessage: String? = null, onRetryRequest: (() -> Unit)? = null,
    onHome: (() -> Unit)? = null,
) {
    val summary = PetSummary.from(game, connected, rememberSpeciesCatalog())
    val name = summary.title
    val title = when (route) {
        PleosRoute.Starting -> "오늘도 함께 떠나요"
        PleosRoute.Disconnected -> "연결이 잠시 끊겼어요"
        PleosRoute.Ended -> "이번 연결이 끝났어요"
        PleosRoute.Empty -> "함께할 친구를 골라 주세요"
        PleosRoute.TransferPending -> "친구를 부르고 있어요"
        PleosRoute.TransferComplete -> "친구가 폰으로 갔어요"
        PleosRoute.TransferRejected -> "지금은 폰으로 부를 수 없어요"
        PleosRoute.Fishing -> "${name}와 낚시하고 있어요"
        PleosRoute.Saving -> "관찰 기록을 저장하고 있어요"
        PleosRoute.Reward -> "새 관찰 기록이 생겼어요"
        PleosRoute.Paused -> "쉬었다가 이어갈 수 있어요"
        PleosRoute.SaveFailed -> "기록을 저장하지 못했어요"
        PleosRoute.SelectionPending -> "함께할 친구를 바꾸고 있어요"
        PleosRoute.SelectionFailed -> "친구를 바꾸지 못했어요"
        else -> route.label
    }
    val body = when (route) {
        PleosRoute.Starting -> "차량 상태와 연결을 확인하고 있어요."
        PleosRoute.Disconnected -> "폰의 알로 앱과 인터넷 연결을 확인해 주세요."
        PleosRoute.Ended -> "친구와 활동 결과는 폰의 알로에서 확인해 주세요."
        PleosRoute.Empty -> "폰의 보유 친구 목록에서 차량과 함께할 친구를 선택해 주세요."
        PleosRoute.TransferPending -> "폰에서 이동을 확인하고 있어요. 확인될 때까지 기존 모습을 유지해요."
        PleosRoute.TransferComplete -> "폰에서 친구를 만나 보세요."
        PleosRoute.TransferRejected -> transferMessage ?: "폰에서 친구의 활동 상태를 확인해 주세요."
        PleosRoute.Fishing -> "주차한 동안 친구가 자동으로 낚시해요."
        PleosRoute.Saving -> "이번 회차가 끝났어요. 폰의 저장 결과를 기다려 주세요."
        PleosRoute.Reward -> "물고기 관찰 기록을 저장했어요."
        PleosRoute.Paused -> "쉬는 동안 낚시는 진행되지 않아요."
        PleosRoute.SaveFailed -> "폰의 저장 상태를 확인해 주세요. 낚시는 멈춰 있어요."
        PleosRoute.SelectionPending -> "폰에서 새 친구의 선택을 확인하고 있어요."
        PleosRoute.SelectionFailed -> "새 친구 선택은 아직 확정되지 않았어요."
        else -> "폰의 상태를 확인해 주세요."
    }
    val note = when (route) {
        PleosRoute.Disconnected -> "마지막으로 받은 상태 · 이동 결과 미확정"
        PleosRoute.Ended -> "주차와 세션 종료는 달라요. 다음 연결을 준비해 주세요."
        PleosRoute.Empty -> "선택과 차량 동행이 확인되면 친구를 보여드려요."
        PleosRoute.TransferPending -> transferMessage ?: "이동 확인 중 · 아직 이동 완료가 아니에요."
        PleosRoute.TransferComplete -> "차량으로 자동 복귀하지 않아요. 함께할 친구 선택은 폰에서 해 주세요."
        PleosRoute.TransferRejected -> "진행 중인 활동을 취소하거나 자동으로 다시 호출하지 않아요."
        PleosRoute.Saving -> "새 보상은 아직 확정되지 않았어요. 다음 회차는 멈춰 있어요."
        PleosRoute.SaveFailed -> "기존 저장 기록은 유지해요. 확인되지 않은 보상은 더하지 않아요."
        PleosRoute.SelectionPending -> "기존 모습 유지 · 진행 저장과 선택 결과를 기다려요."
        PleosRoute.SelectionFailed -> "기존 모습 유지 · 폰의 저장 상태를 확인한 뒤 복구해요."
        PleosRoute.Fishing -> "출발하거나 연결이 끊기면 잠시 멈춰요."
        PleosRoute.Paused -> "주차와 연결을 확인한 뒤 이어갈 수 있어요."
        else -> null
    }
    val action = when (route) {
        PleosRoute.Disconnected -> "연결 다시 확인"
        PleosRoute.Ended -> "다음 연결 준비"
        PleosRoute.TransferComplete, PleosRoute.TransferRejected, PleosRoute.SelectionFailed -> "주차 홈으로"
        PleosRoute.TransferPending -> if (onPrimary != null) "이동 상태 다시 확인" else "이동 확인 중"
        PleosRoute.Empty -> "친구 선택 기다리는 중"
        PleosRoute.Fishing, PleosRoute.Reward -> "잠시 쉬기"
        PleosRoute.Paused -> if (fishing != null) "낚시 이어하기" else "주차 홈으로"
        PleosRoute.Saving -> "저장 확인 중"
        PleosRoute.SaveFailed -> "저장 다시 확인"
        PleosRoute.SelectionPending -> "선택 확인 중"
        else -> null
    }
    ScreenFrame(route.label, if (route == PleosRoute.Disconnected) "폰 연결 끊김" else route.label) {
        ScreenColumns(art = {
            when {
                route == PleosRoute.Starting -> AlloWordmark(Modifier.width(240.dp))
                route == PleosRoute.TransferComplete && departure != null -> PetArt(departure, 240.dp,
                    modifier = Modifier.graphicsLayer { translationX = departureFraction * 180.dp.toPx(); alpha = 1f - departureFraction },
                    pose = PetPose.Move, parked = false, connected = connected, runningMotion = true)
                route == PleosRoute.TransferComplete -> Text("✓", style = MaterialTheme.typography.displayLarge, color = MaterialTheme.colorScheme.secondary)
                route == PleosRoute.Empty -> Text("함께할 친구", style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                summary.showArt -> PetArt(summary, 240.dp, pose = if (route == PleosRoute.Paused) PetPose.Sleep else PetPose.Fishing,
                    parked = true, connected = connected && motionAllowed && route in setOf(PleosRoute.Fishing, PleosRoute.Paused))
                else -> AlloWordmark(Modifier.width(180.dp))
            }
        }, details = {
            Text(title, style = MaterialTheme.typography.headlineMedium)
            Text(body, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (fishing != null && route in setOf(PleosRoute.Fishing, PleosRoute.Paused)) {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("${fishing.elapsedSeconds} / ${fishing.targetSeconds}초", style = MaterialTheme.typography.titleLarge)
                        LinearProgressIndicator(progress = { fishing.progress }, modifier = Modifier.fillMaxWidth())
                        Text("폰에서 확인된 진행", style = MaterialTheme.typography.bodyMedium)
                        fishing.totalRecords?.let { Text("저장된 관찰 기록 ${it}건", style = MaterialTheme.typography.bodyMedium) }
                    }
                }
            }
            if (route == PleosRoute.Reward && fishing?.rewardName != null) {
                Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(20.dp)) {
                    Text(fishing.rewardName, style = MaterialTheme.typography.titleLarge)
                    fishing.totalRecords?.let { Text("누적 ${it}건 · 저장 완료") }
                } }
            }
            note?.let { Card(Modifier.fillMaxWidth()) { Text(it, Modifier.padding(20.dp), style = MaterialTheme.typography.bodyLarge) } }
            requestMessage?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            onRetryRequest?.let { ScreenAction("낚시 요청 다시 확인", it, secondary = true) }
            action?.let { label -> ScreenAction(label, { onPrimary?.invoke() }, enabled = onPrimary != null) }
            if (onSecondary != null) ScreenAction("폰으로 부르기", onSecondary, secondary = true)
            onHome?.let { ScreenAction("주차 홈으로", it, secondary = true) }
        }, modifier = Modifier.weight(1f))
    }
}
