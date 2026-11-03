package ai.allo.car.voice

/** 부화 알림 시점 판정. 순수 Kotlin, 단위 테스트 대상. */
object HatchAnnouncement {
    /** incubating → hatched 로 바뀌는 순간에만 true. 처음 받은 상태가 이미 hatched 면 지난 일이라 말하지 않는다. */
    fun shouldAnnounce(prevStage: String?, stage: String): Boolean =
        prevStage == "incubating" && stage == "hatched"
}
