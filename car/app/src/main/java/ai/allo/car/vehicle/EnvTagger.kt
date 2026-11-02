package ai.allo.car.vehicle

import java.time.LocalTime
import java.time.ZoneId
import java.time.Instant

/**
 * 신호 → envTags (docs/schema.md 3.3 표). 순수 Kotlin.
 * ⚠️ 좌표는 받지 않는다. 지역 태그(coast/mountain/city)는 RegionTagger 가 차 안에서 판정해 문자열만 넘긴다.
 */
class EnvTagger(
    private val highwayKph: Double = 80.0,
    private val highwayHoldMs: Long = 60_000,
    private val zone: ZoneId = ZoneId.of("Asia/Seoul"),
    private val nightStart: LocalTime = LocalTime.of(19, 0),
    private val nightEnd: LocalTime = LocalTime.of(6, 0),
) {
    private var aboveHighwaySince: Long? = null

    fun tags(
        ts: Long,
        speedKph: Double,
        wiperLevel: Int,
        headlightOn: Boolean,
        regionTag: String? = null,
    ): List<String> {
        val out = ArrayList<String>(4)
        if (wiperLevel > 0) out += "rain"

        val night = isNight(ts)
        if (night) out += "night"
        if (headlightOn && !night) out += "tunnel"

        if (speedKph > highwayKph) {
            val since = aboveHighwaySince ?: ts.also { aboveHighwaySince = it }
            if (ts - since >= highwayHoldMs) out += "highway"
        } else aboveHighwaySince = null

        regionTag?.takeIf { it in REGION_TAGS }?.let { out += it }
        return out
    }

    private fun isNight(ts: Long): Boolean {
        val t = Instant.ofEpochMilli(ts).atZone(zone).toLocalTime()
        return t >= nightStart || t < nightEnd
    }

    companion object {
        val REGION_TAGS = setOf("coast", "mountain", "city")
    }
}
