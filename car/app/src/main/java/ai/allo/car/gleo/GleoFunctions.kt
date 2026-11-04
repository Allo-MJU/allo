package ai.allo.car.gleo

import ai.allo.car.dialogue.DialogueBank
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

/**
 * 순수 Kotlin. 게임 상태 → 운전자에게 들려줄 문장. 단위 테스트 대상.
 * [DialogueBank] 의 `car_*` 키에서 먼저 고르고, 없으면(검수 안 됨·키 없음·값 부족) 아래 고정 문장을 쓴다.
 */
object GleoFunctions {
    const val REPORT_EGG_STATUS = "REPORT_EGG_STATUS"
    const val SUGGEST_DESTINATION = "SUGGEST_DESTINATION"
    const val CELEBRATE_HATCH = "CELEBRATE_HATCH"
    val FUNCTIONS = setOf(REPORT_EGG_STATUS, SUGGEST_DESTINATION, CELEBRATE_HATCH)

    fun respond(function: String, game: GameState, offer: DestinationFlow.Offer? = null, bank: DialogueBank = DialogueBank.EMPTY): GleoCallback {
        val vars = gameVars(game, bank)
        fun pick(q: String, situation: String, extra: Map<String, String> = emptyMap()) =
            bank.line(q, game.speciesId, game.attribute, situation, vars + extra)
        return when (function) {
            REPORT_EGG_STATUS -> when (game.stage) {
                "incubating" -> GleoCallback(function, "success", pick("car_egg_status", "incubating")
                    ?: "뒷자리에서 ${tierWord(game.eggTier)} 알을 품고 있어요. ${(game.progress * 100).toInt()}퍼센트 자랐어요. 조금만 더 부드럽게 가면 좋은 아이가 나와요.")
                "hatched" -> GleoCallback(function, "success", pick("car_egg_status", "hatched") ?: "이미 깨어났어요. 도착까지 같이 가고 있어요.")
                else -> GleoCallback(function, "success", pick("car_egg_status", "idle") ?: "아직 품고 있는 알이 없어요.")
            }
            CELEBRATE_HATCH -> GleoCallback(function, "success",
                if (game.stage == "hatched") pick("car_hatch", "hatched") ?: "${attrWord(game.attribute)} 아이가 깨어났어요! 뒷자리에 물어보세요."
                else pick("car_hatch", "not_yet") ?: "아직 깨어나지 않았어요.")
            SUGGEST_DESTINATION -> GleoCallback(function, "success", suggestFromBank(offer, bank) ?: suggestMessage(offer))
            else -> GleoCallback(function, "fail", bank.line("car_unknown", null, null, "*") ?: "모르는 요청이에요.")
        }
    }

    /** 뱅크에 넘길 값. 값이 없으면 키를 넣지 않는다 → 그 값이 필요한 문장은 뱅크가 건너뛴다 */
    private fun gameVars(game: GameState, bank: DialogueBank): Map<String, String> = buildMap {
        put("tier_word", tierWord(game.eggTier))
        put("progress", (game.progress * 100).toInt().toString())
        bank.speciesName(game.speciesId)?.let { put("name", it) }
        attrWord(game.attribute).takeIf { it.isNotEmpty() }?.let { put("attr_word", it) }
    }

    private fun suggestFromBank(offer: DestinationFlow.Offer?, bank: DialogueBank): String? = when (offer) {
        null -> null
        is DestinationFlow.Offer.None -> bank.line("car_suggest_none", null, null, offer.why.name.lowercase())
        is DestinationFlow.Offer.Made -> {
            val s = offer.suggestion; val d = s.destination
            val vars = mapOf(
                "region_word" to regionWord(d.region),
                "place" to d.name,
                "km" to (s.distanceKm?.let { " 직선으로 약 ${roundKm(it)}km예요." } ?: ""),
            )
            val situation = when { s.alternative -> "alt"; s.unvisited -> "unvisited"; else -> "first" }
            bank.line("car_suggest", null, null, situation, vars)
        }
    }

    /**
     * 방문 기록을 모르는 폴백(unvisited=false)에서는 "아직 안 가보셨네요"라고 말하지 않는다. 사실이 아닐 수 있다.
     * 장소 이름 뒤에는 받침과 무관한 "까지"·"도" 를 쓴다. 거리는 직선 거리라 "직선으로" 를 붙인다.
     */
    private fun suggestMessage(offer: DestinationFlow.Offer?): String = when (offer) {
        null -> "가까운 곳은 다 가보셨어요. 다음 계절에 새 아이가 나와요."
        is DestinationFlow.Offer.None -> when (offer.why) {
            NoSuggestion.ALL_VISITED -> "가까운 곳은 다 가보셨어요. 다음 계절에 새 아이가 나와요."
            NoSuggestion.NONE_NEARBY -> "가까운 곳에는 새 아이가 나오는 곳이 없어요."
            NoSuggestion.EXHAUSTED -> "근처에서 추천할 곳은 여기까지예요. 내비에서 원하는 곳을 직접 고르셔도 돼요."
        }
        is DestinationFlow.Offer.Made -> {
            val s = offer.suggestion; val d = s.destination
            val far = s.distanceKm?.let { " 직선으로 약 ${roundKm(it)}km예요." } ?: ""
            if (s.alternative) "${regionWord(d.region)} 쪽 ${d.name}도 있어요.$far 안내할까요?"
            else {
                val lead = if (s.unvisited) "${regionWord(d.region)} 쪽은 아직 안 가보셨네요. 거기서만 나오는 아이가 있어요."
                           else "${regionWord(d.region)} 쪽에서만 나오는 아이가 있어요."
                "$lead ${d.name}까지 안내할까요?$far 같은 ${withIra(regionWord(d.region))} 다른 곳도 괜찮아요."
            }
        }
    }

    /** "바다라면" / "산이라면": 받침이 있으면 "이라면" */
    internal fun withIra(word: String): String {
        val c = word.lastOrNull() ?: return word
        val batchim = c in '가'..'힣' && (c - '가') % 28 != 0
        return word + if (batchim) "이라면" else "라면"
    }

    /** 5km 단위 반올림, 최소 5 */
    internal fun roundKm(km: Double): Int = maxOf(5, (Math.round(km / 5.0) * 5).toInt())

    /** confirm=true 로 다시 불렸을 때. [destination] 이 null 이면 유효한 제안이 없었던 것. */
    fun respondAccept(destination: Destination?, bank: DialogueBank = DialogueBank.EMPTY): GleoCallback =
        if (destination != null) GleoCallback(SUGGEST_DESTINATION, "success",
            bank.line("car_accept", null, null, "ok", mapOf("place" to destination.name)) ?: "${destination.name}까지 안내를 시작할게요.")
        else GleoCallback(SUGGEST_DESTINATION, "fail", bank.line("car_accept", null, null, "none") ?: "먼저 어디로 갈지 물어봐 주세요.")

    private fun tierWord(t: String) = when (t) { "large" -> "긴"; "mid" -> "중간"; else -> "작은" }
    private fun attrWord(a: String?) = when (a) { "water" -> "물 속성"; "dark" -> "어둠 속성"; else -> "" }
    private fun regionWord(r: String) = when (r) { "coast" -> "바다"; "mountain" -> "산"; else -> "도심" }
}
