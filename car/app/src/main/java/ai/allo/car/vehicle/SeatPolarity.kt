package ai.allo.car.vehicle

/**
 * 좌석 점유값이 반전돼 오는 SDK 버그 대응. 검증 #8 결과에 따라 이 상수 하나만 바꾼다.
 * SDK가 "점유"를 false로 주면 SDK_OCCUPIED = false.
 */
object SeatPolarity {
    const val SDK_OCCUPIED: Boolean = false

    fun isOccupied(rawSdkValue: Boolean?): Boolean = rawSdkValue == SDK_OCCUPIED
}
