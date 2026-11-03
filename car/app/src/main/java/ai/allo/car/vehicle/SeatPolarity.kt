package ai.allo.car.vehicle

/**
 * 좌석 점유값이 반전돼 오는 SDK 버그 대응. 검증 #8 결과에 따라 이 상수 하나만 바꾼다.
 * SDK가 "점유"를 false로 주면 SDK_OCCUPIED = false.
 */
object SeatPolarity {
    const val SDK_OCCUPIED: Boolean = false

    fun isOccupied(rawSdkValue: Boolean?): Boolean = rawSdkValue == SDK_OCCUPIED

    /** 2열 좌석 여러 개의 SDK 원본값 중 하나라도 점유면 true. 모르는 값(null)은 빈자리로 본다. */
    fun anyOccupied(rawSdkValues: Collection<Boolean?>): Boolean = rawSdkValues.any(::isOccupied)
}
