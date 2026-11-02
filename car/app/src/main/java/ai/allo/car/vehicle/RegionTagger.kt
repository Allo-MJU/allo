package ai.allo.car.vehicle

/**
 * 위치 → 지역 태그. ⚠️ 이 클래스 밖으로 좌표가 나가지 않는다.
 * 공모전 데모는 에뮬레이터 내비 위치가 고정돼(판교) 실측이 어려우므로, 우선 수동 오버라이드만 제공한다.
 * 이후 NaviHelper 위치를 받아 간단한 바운딩 박스로 coast/mountain/city 를 판정한다.
 */
class RegionTagger {
    @Volatile var override: String? = null   // 시연용. "coast" | "mountain" | "city" | null

    fun tag(latitude: Double?, longitude: Double?): String? {
        override?.let { return it }
        if (latitude == null || longitude == null) return null
        // TODO(A/C): 동해안·서해안·남해안 바운딩 박스 → coast, 강원 내륙 → mountain, 수도권·광역시 → city
        return null
    }
}
