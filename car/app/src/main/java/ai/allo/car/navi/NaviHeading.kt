package ai.allo.car.navi

import kotlin.math.roundToLong

/**
 * 내비 현재 위치 콜백의 heading → 스냅샷 `headingDeg` (docs/schema.md 3.3). 순수 Kotlin, 단위 테스트 대상.
 * 진행 방향만 다룬다. ⚠️ 같은 콜백의 위도·경도·주소는 받지도 내보내지도 않는다 (CLAUDE.md 규칙 2).
 */
object NaviHeading {
    /**
     * @param heading CurrentLocationInfo.heading (도, 북쪽 0·시계 방향). 아직 콜백이 없었으면 null
     * @return 0 이상 360 미만, 소수 첫째 자리 반올림. NaN·무한대·null 이면 null
     */
    fun deg(heading: Double?): Double? {
        if (heading == null || !heading.isFinite()) return null
        val r = heading % 360.0
        val norm = if (r < 0) r + 360.0 else r
        val rounded = (norm * 10).roundToLong() / 10.0
        return if (rounded >= 360.0) 0.0 else rounded   // 359.96 → 360.0 → 0.0
    }
}
