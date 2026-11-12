package ai.allo.car.navi

import ai.allo.car.model.Turn
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * 시연용 가짜 경로 안내. 에뮬레이터 내비는 위치가 판교에 고정이라 경로 안내(onTBTInfo)·진행 방향이 움직이지 않는다.
 * 디버그 빌드에서 DebugDemoReceiver 가 켠다 (`--es route "right:220,left:560,uturn:900"`).
 *
 * 켠 뒤 차가 실제로 달린 거리(VC 속도로 쌓인 distanceM)만큼 남은 거리를 줄여 내비와 같은 [Turn] 목록을 만든다.
 * 회전 지점을 지나면 진행 방향이 그만큼 바뀐다(우 +90, 좌 -90, 유턴 180, 차로 유지 0). 직진 구간은 실제 도로처럼
 * 완만하게 굽는다(±[SWAY_DEG]). 마지막 회전 뒤 [LOOP_TAIL_M] 를 더 가면 처음부터 다시 돈다.
 *
 * 좌표는 만들지 않는다. 판정하지 않는다 (차 창밖 모양에만 쓰인다).
 */
class RouteSim(private val plan: List<Pair<String, Int>>, private val startHeading: Double = 0.0) {
    private var startM: Double? = null

    private val period: Int = (plan.maxOfOrNull { it.second } ?: 0) + LOOP_TAIL_M

    /** 켠 뒤 달린 거리 (m). 처음 부른 때의 distanceM 을 0 으로 본다 */
    private fun travelled(distanceM: Double): Double {
        val s = startM ?: distanceM.also { startM = it }
        return (distanceM - s).coerceAtLeast(0.0)
    }

    /** 가까운 순 최대 3개 (NaviTurns 와 같은 규칙). 다음 바퀴의 회전도 이어서 보인다 */
    fun turns(distanceM: Double): List<Turn> {
        if (plan.isEmpty()) return emptyList()
        val t = travelled(distanceM)
        val lap = (t / period).toInt()
        val out = mutableListOf<Turn>()
        for (k in lap..lap + 1) for ((type, at) in plan) {
            val left = k * period + at - t
            if (left >= 0) out += Turn(type, left.roundToInt())
        }
        return out.sortedBy { it.inM }.take(3)
    }

    /** 0~360. 지난 회전만큼 돌고, 직진 구간은 완만하게 굽는다 */
    fun headingDeg(distanceM: Double): Double {
        val t = travelled(distanceM)
        val lap = (t / period).toInt()
        val inLap = t - lap * period
        val perLap = plan.sumOf { delta(it.first) }
        var h = startHeading + lap * perLap + plan.filter { it.second <= inLap }.sumOf { delta(it.first) }
        h += SWAY_DEG * sin(2 * PI * t / SWAY_PERIOD_M)
        return ((h % 360) + 360) % 360
    }

    companion object {
        const val LOOP_TAIL_M = 300
        const val SWAY_DEG = 12.0
        const val SWAY_PERIOD_M = 700.0
        private val TYPES = setOf("left", "right", "uturn", "keepLeft", "keepRight")

        private fun delta(type: String): Double = when (type) {
            "right" -> 90.0
            "left" -> -90.0
            "uturn" -> 180.0
            else -> 0.0
        }

        /** "right:220,left:560,uturn:900" → RouteSim. 형식이 틀리면 null */
        fun parse(spec: String, startHeading: Double = 0.0): RouteSim? {
            val plan = spec.split(',').map { it.trim() }.filter { it.isNotEmpty() }.map { part ->
                val (type, at) = part.split(':').takeIf { it.size == 2 } ?: return null
                val m = at.trim().toIntOrNull()?.takeIf { it > 0 } ?: return null
                if (type.trim() !in TYPES) return null
                type.trim() to m
            }
            return if (plan.isEmpty()) null else RouteSim(plan.sortedBy { it.second }, startHeading)
        }
    }
}
