package ai.allo.car.vehicle

/**
 * Pleos SDK 원본 값 → VehicleSnapshot 필드. 순수 Kotlin, 단위 테스트 대상.
 * SDK enum 은 이름(String)으로 받아 SDK 없이 테스트한다. 근거는 docs/verification.md #1 · #2 · #4.
 */
object SignalMapping {
    /**
     * WiperSwitch 이름 → wiperLevel(0~3). AUTO 는 "우천 감지 대기"라 실제로 닦는 중(WiperState ON)일 때만 1.
     * 스위치를 못 읽으면 WiperState 로 판단한다. ⚠️ C 합의 전 제안 매핑.
     */
    fun wiperLevel(switch: String?, wiperOn: Boolean?): Int = when {
        switch == null || switch == "AUTO" -> if (wiperOn == true) 1 else 0
        switch.startsWith("INTERMITTENT_LEVEL_") -> 1
        switch == "CONTINUOUS_LEVEL_1" || switch == "CONTINUOUS_LEVEL_2" -> 2
        switch.startsWith("CONTINUOUS_LEVEL_") -> 3
        else -> 0 // OFF · MIST(1회 분사) · OTHER · SERVICE
    }

    /** 하향등 실제 점등 상태. 주간주행등(DAYTIME_RUNNING)은 터널 신호가 아니다. */
    fun headlightOn(lowBeamState: String?): Boolean = lowBeamState == "ON"

    /** SDK DistanceDriven 은 km(Float). SignalDerivation 은 m 를 받는다. */
    fun odometerM(km: Float?): Double? = km?.let { it.toDouble() * 1000.0 }
}
