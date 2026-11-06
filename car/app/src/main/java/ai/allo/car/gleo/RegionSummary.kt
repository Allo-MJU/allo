package ai.allo.car.gleo

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * 폰 도감의 지역 수집 요약 (`/game` 의 `regionCollectionKnown`·`uncollectedRegions`, docs/schema.md "지역 추천 요약").
 * 추천 기준은 **수집 기록**이다. 실제 방문 이력이 아니다.
 */
sealed interface RegionSummary {
    /** 모름 → 기본 추천 */
    data object Unknown : RegionSummary
    /** 폰이 확인한 미수집 지역. 빈 집합 = 세 지역 모두 수집 (후보 없음, 기본 추천으로 되돌리지 않음) */
    data class Known(val uncollected: Set<String>) : RegionSummary

    companion object {
        private val REGIONS = DestinationSuggester.ORDER.toSet()

        /**
         * raw `/game` JSON 을 schema.md 표대로 정규화한다. 손상 값은 지우지 않고 통째로 Unknown 이다.
         * - known 누락·false·타입 오류 → Unknown (목록이 있어도 쓰지 않음)
         * - true + 목록 키 없음·null·빈 배열 → Known(빈 집합)
         * - true + 문자열 배열이고 모두 알려진 지역 → Known(중복 제거)
         * - true + 그 밖의 목록(타입·원소·알 수 없는 지역) → Unknown
         * - game 자체가 null·객체 아님 → Unknown
         */
        fun parse(game: JsonElement?): RegionSummary {
            val obj = game as? JsonObject ?: return Unknown
            val known = (obj["regionCollectionKnown"] as? JsonPrimitive)
                ?.takeIf { !it.isString }?.booleanOrNull ?: return Unknown
            if (!known) return Unknown
            return when (val list = obj["uncollectedRegions"]) {
                null, JsonNull -> Known(emptySet())
                is JsonArray -> {
                    val regions = list.map { e ->
                        val p = e as? JsonPrimitive ?: return Unknown
                        if (!p.isString || p.content !in REGIONS) return Unknown
                        p.content
                    }
                    Known(regions.toSet())
                }
                else -> Unknown
            }
        }
    }
}
