package ai.allo.car.vehicle

import kotlin.math.*

/**
 * 차 안에서만 쓰는 좌표. ⚠️ Firebase·로그·이벤트로 내보내지 않는다 (CLAUDE.md 규칙 2).
 * 지역 판정(RegionTagger)과 가까운 목적지 고르기(DestinationSuggester)에만 쓴다.
 */
data class GeoPoint(val lat: Double, val lng: Double) {
    /** 대원 거리(km). 도로 거리보다 짧게 나온다. */
    fun kmTo(o: GeoPoint): Double {
        val r = 6371.0
        val dLat = Math.toRadians(o.lat - lat); val dLng = Math.toRadians(o.lng - lng)
        val a = sin(dLat / 2).pow(2) + cos(Math.toRadians(lat)) * cos(Math.toRadians(o.lat)) * sin(dLng / 2).pow(2)
        return 2 * r * asin(sqrt(a))
    }
    // 실수로 로그에 찍혀도 좌표가 남지 않게
    override fun toString() = "GeoPoint(…)"
}
