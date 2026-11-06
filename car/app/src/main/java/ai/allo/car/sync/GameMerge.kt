package ai.allo.car.sync

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject

/**
 * `/game` SSE 이벤트(put/patch)를 마지막 전체 상태에 합친다. 순수 Kotlin, 단위 테스트 대상.
 * 폰은 `/game` 전체를 set 으로 쓴다 (docs/schema.md). 그 밖의 모양은 안전한 쪽(지역 요약 모름)으로 처리한다.
 */
object GameMerge {
    private val REGION_KEYS = setOf("regionCollectionKnown", "uncollectedRegions")

    fun apply(base: JsonObject, type: String, path: String, data: JsonElement): JsonObject {
        val keys = path.trim('/').split('/').filter { it.isNotEmpty() }
        if (keys.isEmpty()) {
            // root null·객체 아님 = 노드 삭제·손상 → 이전 상태(지역 요약 포함)를 버린다
            val obj = data as? JsonObject ?: return EMPTY
            return if (type == "patch") JsonObject(base.toMutableMap().apply { putAll(obj); obj.filterValues { it is JsonNull }.keys.forEach { remove(it) } })
                   else obj
        }
        val top = keys.first()
        val shallowPut = keys.size == 1 && type == "put"
        return JsonObject(base.toMutableMap().apply {
            if (shallowPut) { if (data is JsonNull) remove(top) else put(top, data); return@apply }
            // 깊은 경로 patch 는 계약 밖이다. 해당 키를 버리고, 지역 요약이면 두 필드를 함께 버려 다음 전체 set 까지 모름으로 둔다
            remove(top)
            if (top in REGION_KEYS) REGION_KEYS.forEach { remove(it) }
        })
    }

    private val EMPTY = JsonObject(emptyMap())
}
