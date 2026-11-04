package ai.allo.car.vehicle

/**
 * 위치 → 지역 태그 (coast / mountain / city). ⚠️ 이 클래스 밖으로 좌표가 나가지 않는다. 태그 문자열만 나간다.
 *
 * 판정: 기준점 목록과의 거리. 우선순위 coast > mountain > city (해운대처럼 바다이자 도시인 곳은 바다).
 * 기준점·반경은 근사값이다. 해안은 대표 해변·항구를 6km 반경으로 이어 붙였고, 사이가 먼 구간은 놓칠 수 있다.
 * 에뮬레이터 내비 위치는 판교로 고정 → city. 시연에서 바다를 보이려면 [override] 를 쓴다.
 */
class RegionTagger {
    @Volatile var override: String? = null   // 시연용. "coast" | "mountain" | "city" | null

    fun tag(latitude: Double?, longitude: Double?): String? {
        override?.let { return it }
        if (latitude == null || longitude == null) return null
        return classify(GeoPoint(latitude, longitude))
    }

    companion object {
        private data class Zone(val name: String, val center: GeoPoint, val radiusKm: Double)
        private fun z(name: String, lat: Double, lng: Double, r: Double) = Zone(name, GeoPoint(lat, lng), r)

        private const val COAST_KM = 6.0
        private val COAST = listOf(
            // 동해안 (북 → 남)
            z("거진", 38.45, 128.47, COAST_KM), z("속초", 38.20, 128.60, COAST_KM), z("낙산", 38.12, 128.63, COAST_KM),
            z("주문진", 37.89, 128.83, COAST_KM), z("경포", 37.80, 128.91, COAST_KM), z("정동진", 37.69, 129.03, COAST_KM),
            z("묵호", 37.55, 129.12, COAST_KM), z("삼척", 37.44, 129.19, COAST_KM), z("울진", 37.00, 129.42, COAST_KM),
            z("후포", 36.68, 129.45, COAST_KM), z("강구", 36.36, 129.39, COAST_KM), z("영일대", 36.06, 129.38, COAST_KM),
            z("호미곶", 36.08, 129.57, COAST_KM), z("감포", 35.80, 129.50, COAST_KM), z("일산해변", 35.50, 129.43, COAST_KM),
            z("기장", 35.24, 129.22, COAST_KM), z("해운대", 35.16, 129.16, COAST_KM), z("광안리", 35.15, 129.12, COAST_KM),
            // 남해안 (동 → 서)
            z("다대포", 35.05, 128.97, COAST_KM), z("거제", 34.88, 128.62, COAST_KM), z("통영", 34.84, 128.43, COAST_KM),
            z("남해", 34.80, 127.92, COAST_KM), z("여수", 34.74, 127.74, COAST_KM), z("고흥", 34.60, 127.28, COAST_KM),
            z("율포", 34.67, 127.09, COAST_KM), z("완도", 34.31, 126.75, COAST_KM), z("땅끝", 34.30, 126.53, COAST_KM),
            z("목포", 34.79, 126.38, COAST_KM),
            // 서해안 (남 → 북)
            z("가마미", 35.38, 126.42, COAST_KM), z("변산", 35.68, 126.53, COAST_KM), z("군산", 35.97, 126.62, COAST_KM),
            z("춘장대", 36.17, 126.52, COAST_KM), z("대천", 36.31, 126.51, COAST_KM), z("만리포", 36.79, 126.14, COAST_KM),
            z("궁평", 37.12, 126.68, COAST_KM), z("대부도", 37.25, 126.58, COAST_KM), z("을왕리", 37.45, 126.37, COAST_KM),
            z("강화", 37.62, 126.42, COAST_KM),
            // 제주
            z("협재", 33.39, 126.24, COAST_KM), z("함덕", 33.54, 126.67, COAST_KM), z("성산", 33.46, 126.93, COAST_KM),
            z("중문", 33.24, 126.41, COAST_KM),
        )
        private val MOUNTAIN = listOf(
            z("설악산", 38.12, 128.46, 12.0), z("오대산", 37.79, 128.54, 10.0), z("치악산", 37.37, 128.05, 8.0),
            z("태백산", 37.10, 128.92, 8.0), z("소백산", 36.96, 128.48, 10.0), z("월악산", 36.89, 128.10, 8.0),
            z("속리산", 36.54, 127.87, 8.0), z("계룡산", 36.34, 127.21, 6.0), z("덕유산", 35.86, 127.75, 10.0),
            z("지리산", 35.34, 127.73, 18.0), z("지리산 노고단", 35.29, 127.53, 10.0), z("가야산", 35.82, 128.12, 7.0), z("주왕산", 36.40, 129.17, 7.0),
            z("내장산", 35.49, 126.89, 6.0), z("월출산", 34.76, 126.70, 5.0), z("한라산", 33.36, 126.53, 12.0),
            z("북한산", 37.66, 126.98, 6.0),
        )
        private val CITY = listOf(
            z("서울", 37.5665, 126.978, 14.0), z("인천", 37.456, 126.705, 10.0), z("수원", 37.263, 127.029, 8.0),
            z("성남", 37.42, 127.13, 8.0), z("고양", 37.66, 126.83, 8.0), z("용인", 37.24, 127.18, 8.0),
            z("부산", 35.18, 129.075, 12.0), z("대구", 35.871, 128.601, 10.0), z("대전", 36.35, 127.385, 10.0),
            z("광주", 35.16, 126.85, 10.0), z("울산", 35.54, 129.31, 8.0), z("청주", 36.64, 127.49, 7.0),
            z("전주", 35.82, 127.15, 6.0), z("창원", 35.23, 128.68, 8.0), z("천안", 36.81, 127.15, 6.0),
        )

        /** 순수 함수. 단위 테스트 대상. 어디에도 안 걸리면 null (태그 없음). */
        fun classify(p: GeoPoint): String? = when {
            COAST.any { p.kmTo(it.center) <= it.radiusKm } -> "coast"
            MOUNTAIN.any { p.kmTo(it.center) <= it.radiusKm } -> "mountain"
            CITY.any { p.kmTo(it.center) <= it.radiusKm } -> "city"
            else -> null
        }
    }
}
