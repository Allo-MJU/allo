package ai.allo.car.navi

import ai.allo.car.model.Turn
import kotlin.math.roundToLong

/**
 * 내비 회전 안내(TBTInfo) → 스냅샷 `turns` (docs/schema.md 3.3). 순수 Kotlin, 단위 테스트 대상.
 * SDK 타입에 의존하지 않도록 TurnType 이름 문자열과 거리만 받는다.
 * ⚠️ TBTInfo.description(도로명·교차로명)과 좌표는 받지도 내보내지도 않는다 (CLAUDE.md 규칙 2).
 */
object NaviTurns {
    const val MAX = 3

    /** TurnType 이름 → wire type. 계약의 다섯 가지 외(직진·터널·톨게이트·합류 등)는 null 로 버린다 */
    fun type(turnTypeName: String?): String? = when (turnTypeName) {
        "TURN_LEFT", "TURN_SHARP_L" -> "left"
        "TURN_RIGHT", "TURN_SHARP_R" -> "right"
        "TURN_UTURN" -> "uturn"
        "TURN_KEEP_L", "TURN_ENTER_IC_L", "TURN_EXIT_IC_L" -> "keepLeft"
        "TURN_KEEP_R", "TURN_ENTER_IC_R", "TURN_EXIT_IC_R" -> "keepRight"
        else -> null
    }

    /** 남은 거리(m) → 0 이상 정수. NaN·무한대는 null 로 버린다 */
    fun inM(distance: Double): Int? {
        if (!distance.isFinite()) return null
        return distance.roundToLong().coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
    }

    /**
     * @param guiding 경로 안내 중([Guidance.GUIDING])일 때만 싣는다. 아니면 빈 목록
     * @param raw (TurnType 이름, 남은 거리 m) — onTBTInfo 가 준 순서 그대로
     * @return 정규화된 회전, 가까운 순 최대 [MAX]개
     */
    fun turns(guiding: Boolean, raw: List<Pair<String?, Double>>): List<Turn> {
        if (!guiding) return emptyList()
        return raw.mapNotNull { (name, distance) ->
            val t = type(name) ?: return@mapNotNull null
            val m = inM(distance) ?: return@mapNotNull null
            Turn(type = t, inM = m)
        }.sortedBy { it.inM }.take(MAX)
    }
}
