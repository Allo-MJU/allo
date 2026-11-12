package ai.allo.car.dialogue

/** Plaza-only copy based on docs/dialogue-style.md; independent of the legacy dialogue bank. */
internal class PlazaDialogue {
    private val nextIndices = mutableMapOf<String, Int>()

    fun next(speciesId: String): String? {
        val choices = lines[speciesId] ?: return null
        val index = nextIndices[speciesId] ?: 0
        nextIndices[speciesId] = (index + 1) % choices.size
        return choices[index]
    }

    companion object {
        val lines: Map<String, List<String>> = mapOf(
            "road_sprout" to listOf("풀잎이 반짝인다! 정말 신기해.", "오늘도 새로운 친구를 만났어!"),
            "bridge_hopper" to listOf("광장을 한 바퀴 돌았어. 깡총!", "작은 길도 신나게 건너자!"),
            "mountain_sprite" to listOf("천천히 쉬어 가자. 여기선 괜찮아.", "나무처럼 든든하게 곁에 있을게."),
            "puddle_pip" to listOf("첨벙첨벙, 물놀이가 제일 좋아!", "촉촉한 풀밭에서 놀고 싶어. 삐약!"),
            "river_glider" to listOf("바람 따라 느긋하게 흘러가자.", "조금 쉬었다 가도 좋아. 스르르."),
            "tide_keeper" to listOf("마음도 파도처럼 잔잔해졌어.", "여기서 편안하게 쉬어 가자."),
            "storm_lantern" to listOf("광장에 씩씩한 등불 등장! 번쩍!", "내 작은 불빛으로 환하게 비출게."),
            "sea_mist" to listOf("살며시 다가왔어. 몽글몽글.", "조용히 쉬는 시간이 참 좋아."),
            "lamp_moth" to listOf("작은 불빛만 봐도 신나. 반짝!", "환한 빛을 따라 산책하고 싶어."),
            "tunnel_moth" to listOf("낯선 길도 천천히 살펴보면 돼.", "어두워도 괜찮아. 함께 걸어가자."),
            "star_owl" to listOf("별은 저마다 다른 빛을 내. 후후.", "달빛 아래 쉬는 시간도 소중해."),
            "highway_comet" to listOf("광장 한 바퀴, 신나게 달려! 슝!", "쌩쌩 달리고 잠깐 쉬는 거야."),
        )
    }
}
