package ai.allo.car.sync

/**
 * 주행이 끝났는지 판단한다 (`sessionEnd` 이벤트). 순수 Kotlin, 단위 테스트 대상.
 *
 * - 목적지 도착 후 기어 P → 바로 종료 ([Reason.ARRIVED])
 * - 경로 안내가 없을 때 기어 P 가 [parkHoldMs] (3분) 이어지면 종료 ([Reason.PARKED])
 * - 경로 안내 중(휴게소 등)에는 [parkHoldWithRouteMs] (30분) 까지 기다린다. 중간 정차로 세션이 끊기지 않게
 * - 출발 전(누적 거리 [minDrivenM] 미만)에는 끝내지 않는다. 페어링하며 P 로 서 있는 동안 끝나면 안 된다
 *
 * 한 번 종료를 돌려준 뒤에는 [reset] 전까지 다시 돌려주지 않는다.
 */
class SessionEndDetector(
    private val parkHoldMs: Long = 3 * 60_000L,
    private val parkHoldWithRouteMs: Long = 30 * 60_000L,
    private val minDrivenM: Double = 100.0,
) {
    enum class Reason { ARRIVED, PARKED }

    private var parkedSince: Long? = null
    private var fired = false

    /**
     * 1초마다 호출.
     * @param routeActive 내비 경로 안내 중 (etaSec != null)
     * @param arrived 이 세션에서 목적지 도착 이벤트를 받았는가
     */
    fun update(ts: Long, gear: String?, distanceM: Double, routeActive: Boolean, arrived: Boolean): Reason? {
        if (fired) return null
        if (gear != "P") { parkedSince = null; return null }
        val since = parkedSince ?: ts.also { parkedSince = it }
        if (distanceM < minDrivenM) return null
        val reason = when {
            arrived -> Reason.ARRIVED
            ts - since >= (if (routeActive) parkHoldWithRouteMs else parkHoldMs) -> Reason.PARKED
            else -> null
        }
        if (reason != null) fired = true
        return reason
    }

    fun reset() { parkedSince = null; fired = false }
}
