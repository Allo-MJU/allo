package ai.allo.car.model

import kotlinx.serialization.Serializable

/** 차 화면 모드. CarUxRestrictions + 기어로 결정한다. */
enum class CarScreen { Pairing, Driving, Parked }

/** /sessions/{sid}/meta — docs/schema.md 3.2 */
@Serializable
data class SessionMeta(
    val createdAt: Long,
    val pairCode: String,
    val paired: Boolean = false,
    val carAppVersion: String,
)

/**
 * /sessions/{sid}/vehicle — docs/schema.md 3.3
 * 차량 앱이 1초마다 쓴다. 판정하지 않고 raw + 파생 카운트만 올린다.
 * ⚠️ 위도·경도 필드는 이 클래스에 절대 추가하지 않는다.
 */
@Serializable
data class VehicleSnapshot(
    val ts: Long,
    val gear: String,                 // "P" | "R" | "N" | "D"
    val speedKph: Double,
    val distanceM: Double,            // 세션 누적
    val harshBrake: Int,              // 세션 누적 횟수
    val harshSteer: Int,
    val wiperLevel: Int,              // 0..3
    val headlightOn: Boolean,
    val seatRow2: Boolean,            // 반전 처리 후
    val etaSec: Long? = null,         // 내비 미사용 시 null
    val envTags: List<String>,
    val turns: List<Turn> = emptyList(), // 내비 다음 회전, 가까운 순 최대 3개. 안내 중이 아니면 빈 목록
    val headingDeg: Double? = null,   // 차 진행 방향(도, 0~360, 북쪽 0·시계 방향). 모르면 null. 좌표는 보내지 않는다
    val capabilities: List<String>,
    val fishingPresence: FishingPresence? = null,
)

/**
 * /vehicle/turns 원소 — docs/schema.md 3.3. 차 창밖이 회전을 그리는 데만 쓴다 (판정 아님).
 * ⚠️ 도로명·교차로명(TBTInfo.description)과 좌표는 넣지 않는다.
 */
@Serializable
data class Turn(
    val type: String,                 // "left" | "right" | "uturn" | "keepLeft" | "keepRight"
    val inM: Int,                     // 그 회전까지 남은 거리(m), 0 이상
)

/** /sessions/{sid}/game — docs/schema.md 3.4. 폰이 쓰고 차는 읽기만 한다. */
@Serializable
data class GameState(
    val ts: Long = 0,
    val eggTier: String = "small",
    val stage: String = "idle",       // "idle" | "incubating" | "hatched" | v2 "failed"
    val progress: Double = 0.0,
    val speciesId: String? = null,
    val attribute: String? = null,
    val tier: Int? = null,
    val careCount: Int = 0,
    val lookOutCount: Int = 0,
    val hatchAtM: Double? = null,
    val hatchAtSec: Long? = null,
    // Proposed v2 display contract (#54). New blocks are read-only and version-gated.
    val contractVersion: Int? = null,
    val gameRevision: Long? = null,
    val affinity: AffinitySummary? = null,
    val companion: CompanionDisplay? = null,
    val transferResult: TransferResult? = null,
    val baseSummary: BaseSummary? = null,
    val travelRequest: TravelRequest? = null,
    val fishing: FishingSnapshot? = null,
    @kotlinx.serialization.Transient val invalidBlocks: Set<String> = emptySet(),
) {
    val hasV2Contract: Boolean get() = contractVersion == 2 && gameRevision != null && gameRevision >= 0
}

@Serializable
data class AffinitySummary(
    val score: Double,
    val target: Int,
    val ready: Boolean = false,
    val phase: String? = null,
    val photoCompleted: Boolean? = null,
) {
    constructor(score: Int, target: Int, ready: Boolean) : this(score.toDouble(), target, ready)
    val scoreText: String get() = java.math.BigDecimal.valueOf(score).stripTrailingZeros().toPlainString()
}
@Serializable
data class CompanionDisplay(val displayId: String, val displayRevision: Long, val speciesId: String, val location: String)
@Serializable
data class TransferResult(val requestId: String, val displayId: String, val requestRevision: Long,
    val status: String, val resultLocation: String?)
@Serializable
data class BaseSummary(val builderSpeciesId: String? = null, val cookSpeciesId: String? = null,
    val trainerSpeciesId: String? = null, val structureIds: List<String> = emptyList(),
    val lastMealId: String? = null, val activeTaskKind: String? = null)
@Serializable
data class TravelRequest(val wishId: String, val targetRegion: String)


/** /sessions/{sid}/events/{pushId} — docs/schema.md 3.5 */
@Serializable
data class GameEvent(
    val ts: Long,
    val type: String,                 // paired | hatched | lookOutPrompt | gleoSpeak | destinationSuggest | sessionEnd
    val by: String,                   // "phone" | "car"
    val payload: Map<String, String> = emptyMap(),
)

/** 신호 이름. /vehicle/capabilities 에 그대로 들어간다. */
object Capability {
    const val WIPER = "wiper"
    const val LIGHT = "light"
    const val SEAT = "seat"
    const val ODOMETER = "odometer"
    const val BRAKE = "brake"
    const val STEERING = "steering"
    const val SPEED = "speed"
    const val GEAR = "gear"
    const val ETA = "eta"
    const val TURNS = "turns"
}
