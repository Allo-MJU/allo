package ai.allo.car.feature

import ai.allo.car.gleo.TravelRequestFlow
import ai.allo.car.model.GameState
import ai.allo.car.ui.ScreenAction
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.util.Locale

/** A separate driver confirmation is required for each proposed fixed destination. */
@Composable
fun TravelRequestCard(
    game: GameState,
    connected: Boolean,
    offer: TravelRequestFlow.Offer?,
    message: String,
    onOffer: () -> Unit,
    onAccept: (Long, Int) -> Unit,
) {
    if (!game.hasV2Contract) return
    val request = game.travelRequest
    if (request == null) {
        if ("travelRequest" in game.invalidBlocks) Text("여행 부탁 정보를 폰에서 다시 확인해 주세요.")
        return
    }
    val region = when (request.targetRegion) { "coast" -> "바다"; "mountain" -> "산"; "city" -> "도시"; else -> return }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("다음 여행 부탁 · $region", style = MaterialTheme.typography.titleMedium)
            Text("부모님과 후보를 살펴본 뒤 운전자가 내비 요청을 수락해 주세요.")
            if (!connected) Text("폰 연결과 주행 세션을 확인해 주세요.")
            ScreenAction("여행 후보 보기", onOffer, enabled = connected)
            when (offer) {
                is TravelRequestFlow.Offer.Made -> {
                    if (offer.suggestions.all { it.distanceKm == null }) Text("현재 위치를 몰라 거리가 없는 기본 후보를 보여드려요.")
                    offer.suggestions.forEachIndexed { index, suggestion ->
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(suggestion.destination.name)
                            suggestion.distanceKm?.let { Text("직선 거리 ${String.format(Locale.ROOT, "%.1f", it)} km") }
                            ScreenAction("운전자 내비 요청 수락", { onAccept(offer.token, index) }, enabled = connected, secondary = true)
                        }
                    }
                }
                is TravelRequestFlow.Offer.None -> Text(when (offer.reason) {
                    TravelRequestFlow.Reason.CONFIRM_VISIT_ON_PHONE -> "이미 부탁한 지역에 있어요. 방문 확인은 폰에서 해 주세요."
                    TravelRequestFlow.Reason.NONE_NEARBY -> "직선 120 km 안에 준비된 후보가 없어요. 부탁은 폰에 남아 있어요."
                    TravelRequestFlow.Reason.PARK_REQUIRED -> "주차 상태를 확인한 뒤 후보를 볼 수 있어요."
                    TravelRequestFlow.Reason.NO_REQUEST -> "폰에서 여행 부탁을 먼저 골라 주세요."
                    TravelRequestFlow.Reason.INVALID_REQUEST -> "여행 부탁 정보를 폰에서 다시 확인해 주세요."
                    TravelRequestFlow.Reason.UNSUPPORTED_CONTRACT -> "여행 부탁을 지원하는 폰 연결이 필요해요."
                    TravelRequestFlow.Reason.UNAVAILABLE -> "폰 연결과 주행 세션을 확인해 주세요."
                })
                null -> Unit
            }
            if (message.isNotBlank()) Text(message)
            Text("후보 선택이나 내비 요청만으로 방문이 완료되지는 않아요.", style = MaterialTheme.typography.bodySmall)
        }
    }
}
