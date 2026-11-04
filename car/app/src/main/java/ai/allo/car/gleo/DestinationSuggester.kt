package ai.allo.car.gleo

/**
 * Gleo `SUGGEST_DESTINATION` 의 목적지 고르기. 순수 Kotlin, 단위 테스트 대상.
 * ⚠️ 좌표는 이 파일과 NaviHelper 사이에서만 쓰인다. Firebase 로는 지역 태그만 나간다 (절대 규칙 2).
 */
data class Destination(val region: String, val name: String, val latitude: Double, val longitude: Double)

/** [unvisited] 가 true 면 폰이 알려준 실제 미방문 지역, false 면 방문 기록 없이 고른 폴백. */
data class Suggestion(val destination: Destination, val unvisited: Boolean)

object DestinationSuggester {
    /** 제안 우선순위. 시연 위치(판교, 도심)에서는 바다가 먼저 나온다. */
    val ORDER = listOf("coast", "mountain", "city")

    /** 지역별 대표 목적지 (근사 좌표, 공개 장소). 실제 안내 지점은 내비가 POI 이름으로 맞춘다. */
    val DESTINATIONS: Map<String, Destination> = listOf(
        Destination("coast", "경포해변", 37.8055, 128.9083),
        Destination("mountain", "설악산 소공원", 38.1724, 128.4893),
        Destination("city", "N서울타워", 37.5512, 126.9882),
    ).associateBy { it.region }

    /**
     * @param currentRegion 지금 있는 지역 태그. 모르면 null
     * @param unvisitedRegions 폰이 알려준 미방문 지역. **null = 방문 기록을 모름** → 폴백.
     *   빈 목록 = 다 가 봤음 → 제안 없음
     */
    fun pick(currentRegion: String?, unvisitedRegions: List<String>? = null): Suggestion? {
        if (unvisitedRegions != null) {
            val region = ORDER.firstOrNull { it in unvisitedRegions && it != currentRegion } ?: return null
            return Suggestion(DESTINATIONS.getValue(region), unvisited = true)
        }
        // TODO(A): /game 에 미방문 지역 필드가 생기면 (이슈 #9) 그 값을 unvisitedRegions 로 넘긴다
        val region = ORDER.first { it != currentRegion }
        return Suggestion(DESTINATIONS.getValue(region), unvisited = false)
    }
}

/**
 * 제안 → 수락의 2단계. 제안한 지 [ttlMs] 안에 들어온 수락만 받는다.
 * GleoReceiver 는 보낸 쪽 신원을 확인할 수 없으므로, 수락으로 설정되는 목적지는 **직전에 우리가 제안한 고정 목록 중 하나**로 제한한다.
 */
class DestinationFlow(
    private val now: () -> Long = System::currentTimeMillis,
    private val ttlMs: Long = 120_000,
) {
    private var pending: Pair<Suggestion, Long>? = null

    @Synchronized
    fun offer(currentRegion: String?, unvisitedRegions: List<String>? = null): Suggestion? =
        DestinationSuggester.pick(currentRegion, unvisitedRegions).also { s -> pending = s?.let { it to now() } }

    /** 유효한 제안이 있으면 그 목적지를 돌려주고 비운다. 없거나 만료됐으면 null. */
    @Synchronized
    fun accept(): Destination? {
        val (s, at) = pending ?: return null
        pending = null
        return s.destination.takeIf { now() - at <= ttlMs }
    }
}
