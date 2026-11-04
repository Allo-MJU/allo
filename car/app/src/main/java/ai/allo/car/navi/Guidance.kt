package ai.allo.car.navi

/**
 * 내비 경로 안내 상태. ETA 와 따로 둔다 (PR #24 리뷰): ROUTE_DRIVE 를 받았어도 남은 시간이 아직 안 왔으면 ETA 는 null 이다.
 * 목적지 제안·수락은 [IDLE] 일 때만 내비를 바꾼다. [UNKNOWN](앱 시작 직후, 내비 미초기화)은 바꾸지 않는다.
 * 순수 Kotlin, 단위 테스트 대상.
 */
enum class Guidance {
    UNKNOWN, IDLE, GUIDING;

    companion object {
        /** NavigationStatus 이름. INACTIVE·INITIALIZING 은 내비가 아직 준비되지 않은 것 → UNKNOWN */
        fun fromStatus(name: String?): Guidance = when (name) {
            "ROUTE_DRIVE" -> GUIDING
            "FREE_DRIVE" -> IDLE
            else -> UNKNOWN
        }

        /**
         * RouteStateInfo.naviMode 이름. 에뮬레이터 실측: 안내 중에 ROUTE_GUIDING (isRouting 은 false 라 쓰지 않는다).
         * SAFE_GUIDING(안전운전 안내)·NOT_WORKING 은 경로 안내가 아니다.
         */
        fun fromNaviMode(name: String?): Guidance = when (name) {
            "ROUTE_GUIDING", "SIMULATION_GUIDING" -> GUIDING
            "SAFE_GUIDING", "NOT_WORKING" -> IDLE
            else -> UNKNOWN
        }
    }
}
