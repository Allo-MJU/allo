package ai.allo.car.gleo

import ai.allo.car.vehicle.GeoPoint

/**
 * Gleo `SUGGEST_DESTINATION` 의 목적지 고르기. 순수 Kotlin, 단위 테스트 대상.
 * ⚠️ 좌표는 이 파일과 NaviHelper 사이에서만 쓰인다. Firebase 로는 지역 태그만 나간다 (절대 규칙 2).
 */
data class Destination(val region: String, val name: String, val latitude: Double, val longitude: Double) {
    val point get() = GeoPoint(latitude, longitude)
}

/**
 * @param unvisited true 면 폰이 알려준 실제 미방문 지역, false 면 방문 기록 없이 고른 폴백
 * @param distanceKm 현재 위치에서의 직선 거리. 위치를 모르면 null
 * @param alternative 같은 대화에서 "다른 곳"으로 두 번째 이후에 제안한 것
 */
data class Suggestion(
    val destination: Destination,
    val unvisited: Boolean,
    val distanceKm: Double? = null,
    val alternative: Boolean = false,
)

/** 제안할 곳이 없는 이유. 운전자에게 들려줄 문장이 다르다. */
enum class NoSuggestion { ALL_VISITED, NONE_NEARBY, EXHAUSTED }

object DestinationSuggester {
    /** 위치를 모를 때의 지역 우선순위. */
    val ORDER = listOf("coast", "mountain", "city")

    /** 직선 거리 limit. 도로 거리는 보통 1.3~1.5배라 약 2시간 안쪽이 된다. */
    const val MAX_KM = 120.0

    /**
     * 지역별 후보 (근사 좌표, 공개 장소). 실제 안내 지점은 내비가 POI 이름으로 맞춘다.
     * 각 후보가 RegionTagger 로도 같은 지역으로 판정되는지 단위 테스트로 확인한다.
     */
    val CANDIDATES: List<Destination> = listOf(
        Destination("coast", "을왕리해수욕장", 37.4475, 126.3723),
        Destination("coast", "만리포해수욕장", 36.7866, 126.1424),
        Destination("coast", "대천해수욕장", 36.3085, 126.5136),
        Destination("coast", "경포해변", 37.8055, 128.9083),
        Destination("coast", "속초해수욕장", 38.1906, 128.6018),
        Destination("coast", "해운대해수욕장", 35.1587, 129.1604),
        Destination("coast", "협재해수욕장", 33.3940, 126.2393),
        Destination("mountain", "북한산 국립공원", 37.6600, 126.9800),
        Destination("mountain", "계룡산 동학사", 36.3611, 127.2289),
        Destination("mountain", "속리산 법주사", 36.5426, 127.8330),
        Destination("mountain", "설악산 소공원", 38.1724, 128.4893),
        Destination("mountain", "지리산 화엄사", 35.2557, 127.4979),
        Destination("mountain", "한라산 성판악", 33.3846, 126.6198),
        Destination("city", "N서울타워", 37.5512, 126.9882),
        Destination("city", "수원화성", 37.2871, 127.0116),
        Destination("city", "대전 엑스포과학공원", 36.3760, 127.3870),
        Destination("city", "대구 동성로", 35.8690, 128.5960),
        Destination("city", "광주 아시아문화전당", 35.1468, 126.9204),
    )

    /**
     * 제안 순서대로 정렬한 후보. 빈 목록이면 [why] 로 이유를 알 수 있다.
     * @param here 현재 위치. null 이면 거리 없이 [ORDER] 순서
     * @param currentRegion 지금 있는 지역 태그. 같은 지역은 제안하지 않는다
     * @param unvisitedRegions 폰이 알려준 미방문 지역. **null = 방문 기록을 모름** → 폴백. 빈 목록 = 다 가 봄
     */
    fun rank(here: GeoPoint?, currentRegion: String?, unvisitedRegions: List<String>? = null): List<Suggestion> {
        val regions = (unvisitedRegions ?: ORDER).filter { it in ORDER && it != currentRegion }
        val unvisited = unvisitedRegions != null
        val pool = CANDIDATES.filter { it.region in regions }
        if (here == null) {
            // TODO(A): /game 에 미방문 지역 필드가 생기면 (이슈 #9) 그 값을 unvisitedRegions 로 넘긴다
            return pool.sortedBy { ORDER.indexOf(it.region) }.map { Suggestion(it, unvisited) }
        }
        return pool.map { it to here.kmTo(it.point) }
            .filter { (_, km) -> km <= MAX_KM }
            .sortedBy { (_, km) -> km }
            .map { (d, km) -> Suggestion(d, unvisited, km) }
    }

    fun why(here: GeoPoint?, currentRegion: String?, unvisitedRegions: List<String>?): NoSuggestion =
        if (unvisitedRegions != null && unvisitedRegions.none { it in ORDER && it != currentRegion }) NoSuggestion.ALL_VISITED
        else NoSuggestion.NONE_NEARBY
}

/**
 * 제안 → 수락의 2단계. 제안한 지 [ttlMs] 안에 들어온 수락만 받는다.
 * 같은 시간 안에 다시 제안을 요청하면("다른 데는?") 다음으로 가까운 후보를 낸다.
 * GleoReceiver 는 보낸 쪽 신원을 확인할 수 없으므로, 수락으로 설정되는 목적지는 **직전에 우리가 제안한 고정 목록 중 하나**로 제한한다.
 */
class DestinationFlow(
    private val now: () -> Long = System::currentTimeMillis,
    private val ttlMs: Long = 120_000,
) {
    private var ranked: List<Suggestion> = emptyList()
    private var index = -1
    private var at = 0L

    sealed interface Offer {
        data class Made(val suggestion: Suggestion) : Offer
        data class None(val why: NoSuggestion) : Offer
    }

    @Synchronized
    fun offer(here: GeoPoint?, currentRegion: String?, unvisitedRegions: List<String>? = null): Offer {
        val continuing = index >= 0 && now() - at <= ttlMs
        if (!continuing) {
            ranked = DestinationSuggester.rank(here, currentRegion, unvisitedRegions)
            index = -1
            if (ranked.isEmpty()) return Offer.None(DestinationSuggester.why(here, currentRegion, unvisitedRegions))
        }
        index++
        at = now()
        if (index >= ranked.size) { index = -1; return Offer.None(NoSuggestion.EXHAUSTED) }
        return Offer.Made(ranked[index].copy(alternative = index > 0))
    }

    /** 유효한 제안이 있으면 그 목적지를 돌려주고 대화를 끝낸다. 없거나 만료됐으면 null. */
    @Synchronized
    fun accept(): Destination? {
        if (index < 0 || index >= ranked.size) return null
        val d = ranked[index].destination.takeIf { now() - at <= ttlMs }
        index = -1
        return d
    }
}
