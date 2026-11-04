package ai.allo.car.gleo

import ai.allo.car.model.GameState
import kotlinx.serialization.Serializable

/** Gleo 응답 와이어 포맷. 선례(핸들온)에서 확인된 형태를 따른다. */
@Serializable
data class GleoCallback(
    val functionName: String,
    val status: String,          // "success" | "fail" | "error"
    val message: String,         // Gleo 가 운전자에게 읽어줄 문장
    val data: String? = null,
)

/** 순수 Kotlin. 게임 상태 → 운전자에게 들려줄 문장. 단위 테스트 대상. */
object GleoFunctions {
    const val REPORT_EGG_STATUS = "REPORT_EGG_STATUS"
    const val SUGGEST_DESTINATION = "SUGGEST_DESTINATION"
    const val CELEBRATE_HATCH = "CELEBRATE_HATCH"
    val FUNCTIONS = setOf(REPORT_EGG_STATUS, SUGGEST_DESTINATION, CELEBRATE_HATCH)

    fun respond(function: String, game: GameState, suggestion: Suggestion? = null): GleoCallback = when (function) {
        REPORT_EGG_STATUS -> when (game.stage) {
            "incubating" -> GleoCallback(function, "success",
                "뒷자리에서 ${tierWord(game.eggTier)} 알을 품고 있어요. ${(game.progress * 100).toInt()}퍼센트 자랐어요. 조금만 더 부드럽게 가면 좋은 아이가 나와요.")
            "hatched" -> GleoCallback(function, "success", "이미 깨어났어요. 도착까지 같이 가고 있어요.")
            else -> GleoCallback(function, "success", "아직 품고 있는 알이 없어요.")
        }
        CELEBRATE_HATCH -> GleoCallback(function, "success",
            if (game.stage == "hatched") "${attrWord(game.attribute)} 아이가 깨어났어요! 뒷자리에 물어보세요." else "아직 깨어나지 않았어요.")
        SUGGEST_DESTINATION -> GleoCallback(function, "success", suggestMessage(suggestion))
        else -> GleoCallback(function, "fail", "모르는 요청이에요.")
    }

    /**
     * 방문 기록을 모르는 폴백(unvisited=false)에서는 "아직 안 가보셨네요"라고 말하지 않는다. 사실이 아닐 수 있다.
     * 장소 이름 뒤에는 받침과 무관한 "까지" 를 쓴다.
     */
    private fun suggestMessage(s: Suggestion?): String {
        if (s == null) return "가까운 곳은 다 가보셨어요. 다음 계절에 새 아이가 나와요."
        val d = s.destination
        val lead = if (s.unvisited) "${regionWord(d.region)} 쪽은 아직 안 가보셨네요. 거기서만 나오는 아이가 있어요."
                   else "${regionWord(d.region)} 쪽에서만 나오는 아이가 있어요."
        return "$lead ${d.name}까지 안내할까요?"
    }

    /** confirm=true 로 다시 불렸을 때. [destination] 이 null 이면 유효한 제안이 없었던 것. */
    fun respondAccept(destination: Destination?): GleoCallback =
        if (destination != null) GleoCallback(SUGGEST_DESTINATION, "success", "${destination.name}까지 안내를 시작할게요.")
        else GleoCallback(SUGGEST_DESTINATION, "fail", "먼저 어디로 갈지 물어봐 주세요.")

    private fun tierWord(t: String) = when (t) { "large" -> "긴"; "mid" -> "중간"; else -> "작은" }
    private fun attrWord(a: String?) = when (a) { "water" -> "물 속성"; "dark" -> "어둠 속성"; else -> "" }
    private fun regionWord(r: String) = when (r) { "coast" -> "바다"; "mountain" -> "산"; else -> "도심" }
}
