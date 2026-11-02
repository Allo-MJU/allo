package ai.allo.car.vehicle

import kotlin.math.abs

/**
 * raw 신호 → 파생 카운트. 순수 Kotlin, 단위 테스트 대상.
 * 임계값은 C와 합의한 값. 바꾸면 docs/schema.md 의 비고에도 적는다.
 */
class SignalDerivation(
    private val harshDecelKphPerSec: Double = 12.0,   // 1초에 12km/h 이상 감속 = 급제동
    private val harshSteerDegPerSec: Double = 90.0,   // 1초에 조향각 90도 이상 변화 = 급조향
    private val minSpeedForSteerKph: Double = 15.0,   // 주차 중 핸들 돌리기는 세지 않음
    private val cooldownMs: Long = 2_000,             // 한 이벤트가 연속으로 두 번 잡히지 않게
) {
    var harshBrakeCount: Int = 0; private set
    var harshSteerCount: Int = 0; private set
    var distanceM: Double = 0.0; private set

    private var lastTs: Long? = null
    private var lastSpeedKph: Double? = null
    private var lastSteerDeg: Double? = null
    private var lastOdometerM: Double? = null
    private var lastBrakeAt: Long = Long.MIN_VALUE
    private var lastSteerAt: Long = Long.MIN_VALUE

    /**
     * 1초마다 호출. odometerM 이 null 이거나 변하지 않으면 속도 적분으로 거리를 누적한다
     * (검증 #4: Odometer 해상도가 1km 단위일 때의 폴백).
     */
    fun update(ts: Long, speedKph: Double, steerDeg: Double?, odometerM: Double?) {
        val prevTs = lastTs
        if (prevTs != null && ts > prevTs) {
            val dtSec = (ts - prevTs) / 1000.0

            lastSpeedKph?.let { prev ->
                val decel = (prev - speedKph) / dtSec
                if (decel >= harshDecelKphPerSec && ts - lastBrakeAt >= cooldownMs) {
                    harshBrakeCount++; lastBrakeAt = ts
                }
            }

            if (steerDeg != null && lastSteerDeg != null && speedKph >= minSpeedForSteerKph) {
                val rate = abs(steerDeg - lastSteerDeg!!) / dtSec
                if (rate >= harshSteerDegPerSec && ts - lastSteerAt >= cooldownMs) {
                    harshSteerCount++; lastSteerAt = ts
                }
            }

            val odoDelta = if (odometerM != null && lastOdometerM != null) odometerM - lastOdometerM!! else null
            distanceM += if (odoDelta != null && odoDelta > 0) odoDelta
                         else (lastSpeedKph ?: speedKph) / 3.6 * dtSec
        }
        lastTs = ts
        lastSpeedKph = speedKph
        if (steerDeg != null) lastSteerDeg = steerDeg
        if (odometerM != null) lastOdometerM = odometerM
    }

    fun reset() {
        harshBrakeCount = 0; harshSteerCount = 0; distanceM = 0.0
        lastTs = null; lastSpeedKph = null; lastSteerDeg = null; lastOdometerM = null
        lastBrakeAt = Long.MIN_VALUE; lastSteerAt = Long.MIN_VALUE
    }
}
