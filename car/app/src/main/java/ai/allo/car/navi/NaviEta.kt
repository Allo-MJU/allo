package ai.allo.car.navi

/** 내비 상태 → etaSec. 순수 Kotlin, 단위 테스트 대상. 경로 안내 중이 아니면 null (폰은 거리 폴백). */
object NaviEta {
    fun etaSec(status: String?, remainSec: Int?): Long? =
        if (status == "ROUTE_DRIVE" && remainSec != null && remainSec > 0) remainSec.toLong() else null
}
