package ai.allo.car.gleo

import ai.allo.car.dialogue.DialogueBank
import ai.allo.car.model.GameState
import ai.allo.car.model.TransferStatus
import ai.allo.car.model.TransferUiState
import kotlinx.serialization.Serializable

/** Gleo 응답 와이어 포맷. 선례(핸들온)에서 확인된 형태를 따른다. */
@Serializable
data class GleoCallback(
    val functionName: String,
    val status: String,          // "success" | "asking"(확인이 더 필요) | "fail" — Pleos Callback Schema 가이드
    val message: String,         // Gleo 가 운전자에게 읽어줄 문장
    val data: String? = null,
    val mode: String? = null,    // null = 기본("voice"). "silent" 면 Gleo 는 말하지 않는다 (앱이 직접 말할 때)
)

/**
 * 순수 Kotlin. 게임 상태 → 운전자에게 들려줄 문장. 단위 테스트 대상.
 * [DialogueBank] 의 `car_*` 키에서 먼저 고르고, 없으면(검수 안 됨·키 없음·값 부족) 아래 고정 문장을 쓴다.
 */
object GleoFunctions {
    const val REPORT_EGG_STATUS = "REPORT_EGG_STATUS"
    const val SUGGEST_DESTINATION = "SUGGEST_DESTINATION"
    const val CELEBRATE_HATCH = "CELEBRATE_HATCH"
    const val REQUEST_COMPANION_TRANSFER = "REQUEST_COMPANION_TRANSFER"
    val FUNCTIONS = setOf(REPORT_EGG_STATUS, SUGGEST_DESTINATION, CELEBRATE_HATCH, REQUEST_COMPANION_TRANSFER)

    fun respond(function: String, game: GameState, offer: DestinationFlow.Offer? = null, bank: DialogueBank = DialogueBank.EMPTY): GleoCallback {
        if (function in setOf(REPORT_EGG_STATUS, CELEBRATE_HATCH)) {
            if (game.contractVersion != null && !game.hasV2Contract) {
                return GleoCallback(function, "fail", "연결된 폰의 상태 형식을 확인해 주세요.")
            }
            if (game.hasV2Contract) {
                if (game.stage == "failed") return GleoCallback(function,
                    if (function == CELEBRATE_HATCH) "fail" else "success",
                    "이번 알은 깨어나지 않았어요. 다음 기회에 다시 만나봐요.")
                val affinity = game.affinity
                if (game.stage == "incubating" && affinity?.phase in setOf("photoRequired", "resultPending")) {
                    val message = if (affinity?.phase == "photoRequired")
                        "사진 퀘스트를 기다리고 있어요. 주차 후 폰에서 확인해 주세요."
                    else "부화 결과를 저장하고 있어요. 폰의 확인을 기다려 주세요."
                    return GleoCallback(function, if (function == CELEBRATE_HATCH) "fail" else "success", message)
                }
                val ready = game.stage == "incubating" && affinity != null && affinity.target > 0 &&
                    affinity.score == affinity.target.toDouble() && affinity.ready
                if (ready) return GleoCallback(function,
                    if (function == CELEBRATE_HATCH) "fail" else "success",
                    "부화할 준비를 마쳤어요. 품기가 끝날 때까지 기다리고 있어요.")
                if (function == CELEBRATE_HATCH && game.stage != "hatched") {
                    return GleoCallback(function, "fail", "아직 깨어나지 않았어요.")
                }
            }
        }
        val vars = gameVars(game, bank)
        fun pick(q: String, situation: String, extra: Map<String, String> = emptyMap()) =
            bank.line(q, game.speciesId, game.attribute, situation, vars + extra)
        return when (function) {
            REPORT_EGG_STATUS -> when (game.stage) {
                "incubating" -> GleoCallback(function, "success", pick("car_egg_status", "incubating")
                    ?: "지금 ${tierWord(game.eggTier)} 알을 품고 있어요. ${(game.progress * 100).toInt()}퍼센트 자랐어요.")
                "hatched" -> GleoCallback(function, "success", pick("car_egg_status", "hatched") ?: "이미 깨어났어요. 도착까지 같이 가고 있어요.")
                else -> GleoCallback(function, "success", pick("car_egg_status", "idle") ?: "아직 품고 있는 알이 없어요.")
            }
            CELEBRATE_HATCH -> GleoCallback(function, "success",
                if (game.stage == "hatched") pick("car_hatch", "hatched") ?: hatchMessage(game, bank)
                else pick("car_hatch", "not_yet") ?: "아직 깨어나지 않았어요.")
            // 제안은 운전자 확인이 필요하므로 asking, 제안할 곳이 없으면 fail
            SUGGEST_DESTINATION -> GleoCallback(function, if (offer is DestinationFlow.Offer.Made) "asking" else "fail",
                suggestFromBank(offer, bank) ?: suggestMessage(offer))
            else -> GleoCallback(function, "fail", bank.line("car_unknown", null, null, "*") ?: "모르는 요청이에요.")
        }
    }

    /** A queued transfer is not a completed move; the phone alone confirms the outcome. */
    fun respondCompanionTransfer(state: TransferUiState): GleoCallback {
        val status = when (state.status) {
            TransferStatus.Waiting, TransferStatus.Unconfirmed -> "asking"
            TransferStatus.Accepted, TransferStatus.AlreadyOnPhone -> "success"
            else -> "fail"
        }
        return GleoCallback(REQUEST_COMPANION_TRANSFER, status,
            state.message.ifBlank { "폰에서 친구를 선택하고 연결을 확인해 주세요." })
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
            val situation = when { s.alternative -> "alt"; s.uncollected -> "uncollected"; else -> "first" }
            bank.line("car_suggest", null, null, situation, vars)
        }
    }

    /**
     * 방문 여부·지역 전용 생물·계절 해금·생물 부재를 단정하지 않는다 (#32 C 사전 검토).
     * 추천 기준은 폰 도감의 **수집 기록**이다 (docs/schema.md "지역 추천 요약"). 그 지역에서 만난 아이가 없다는 것까지만 말하고,
     * 가면 특정 아이가 나온다고 약속하지 않는다.
     * 장소 이름 뒤에는 받침과 무관한 "까지"·"도" 를 쓴다. 거리는 직선 거리라 "직선으로" 를 붙인다.
     */
    private fun suggestMessage(offer: DestinationFlow.Offer?): String = when (offer) {
        null -> "지금은 추가로 제안할 곳이 없어요."
        is DestinationFlow.Offer.None -> when (offer.why) {
            NoSuggestion.ALL_COLLECTED -> "바다·산·도심에서 모두 아이를 만났어요. 지금은 따로 추천할 곳이 없어요."
            NoSuggestion.ONLY_CURRENT_REGION -> "아직 아이를 못 만난 곳이 지금 계신 지역이에요. 다른 지역은 추천할 곳이 없어요."
            NoSuggestion.NONE_NEARBY -> "가까운 곳에서 추천할 장소를 찾지 못했어요."
            NoSuggestion.EXHAUSTED -> "지금 추천할 장소는 여기까지예요."
            NoSuggestion.ROUTE_ACTIVE -> "지금은 길 안내 중이에요. 안내가 끝나면 다시 물어봐 주세요."
        }
        is DestinationFlow.Offer.Made -> {
            val s = offer.suggestion; val d = s.destination
            val far = s.distanceKm?.let { " 직선으로 약 ${roundKm(it)}km예요." } ?: ""
            if (s.alternative) "${regionWord(d.region)} 쪽 ${d.name}도 있어요.$far 안내할까요?"
            else if (s.uncollected) "아직 ${regionWord(d.region)}에서 만난 아이가 없어요. ${d.name}까지 안내할까요?$far"
            else "${regionWord(d.region)} 쪽 ${d.name}까지 안내할까요?$far 같은 ${withIra(regionWord(d.region))} 다른 곳도 괜찮아요."
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

    /**
     * confirm=true 로 다시 불렸을 때. 성공 응답은 기본(voice) 모드다.
     * 차량 앱이 직접 말하는 데 성공했을 때만 [selfVoiced] 로 silent 로 바꾼다 ([GleoReceiver]).
     */
    fun respondAccept(result: AcceptResult, bank: DialogueBank = DialogueBank.EMPTY): GleoCallback {
        fun line(situation: String, vars: Map<String, String> = emptyMap()) = bank.line("car_accept", null, null, situation, vars)
        return when (result) {
            // requestRoute() 가 예외 없이 끝났다는 뜻이지 안내 시작 확인은 아니다 → "요청했어요" (#32 D21·D22)
            is AcceptResult.Started -> GleoCallback(SUGGEST_DESTINATION, "success",
                line("ok", mapOf("place" to result.destination.name)) ?: "${result.destination.name}까지 안내를 요청했어요.")
            AcceptResult.NoOffer -> GleoCallback(SUGGEST_DESTINATION, "fail", line("none") ?: "먼저 어디로 갈지 물어봐 주세요.")
            AcceptResult.RouteActive -> GleoCallback(SUGGEST_DESTINATION, "fail", line("route_active") ?: "지금은 길 안내 중이라 목적지를 바꾸지 않을게요.")
            AcceptResult.NaviNotReady -> GleoCallback(SUGGEST_DESTINATION, "fail", line("not_ready") ?: "지금은 내비에 목적지를 넣지 못했어요. 잠시 뒤에 다시 말해 주세요.")
        }
    }

    /**
     * 목적지가 바뀌면 차량 앱이 직접 말한다. 그래서 Gleo 를 거치지 않은 호출도 운전자가 듣는다 (PR #10 P1 완화).
     * 직접 말했으면 Gleo 는 silent (두 번 듣지 않게), 못 했으면(TTS 미준비·실패) Gleo 음성을 그대로 둔다 (PR #24 리뷰).
     */
    fun selfVoiced(callback: GleoCallback, spoke: Boolean): GleoCallback = if (spoke) callback.copy(mode = "silent") else callback

    /** 부화 고정 문장. 뒷자리 대화를 운전자에게 권하지 않는다 (#39 C 검수와 같은 방향) */
    private fun hatchMessage(game: GameState, bank: DialogueBank): String {
        val who = bank.speciesName(game.speciesId)?.let { it + DialogueBank.josa(it, "이", "가") }
            ?: listOf(attrWord(game.attribute), "아이가").filter { it.isNotEmpty() }.joinToString(" ")
        return "$who 알에서 깨어났어요."
    }

    private fun tierWord(t: String) = when (t) { "large" -> "긴"; "mid" -> "중간"; else -> "작은" }
    private fun attrWord(a: String?) = when (a) { "water" -> "물 속성"; "dark" -> "어둠 속성"; else -> "" }
    private fun regionWord(r: String) = when (r) { "coast" -> "바다"; "mountain" -> "산"; else -> "도심" }
}
