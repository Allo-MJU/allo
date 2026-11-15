package ai.allo.car.dialogue

import android.content.res.AssetManager
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlin.random.Random

/**
 * 대사 뱅크 (`data/dialogue.json`, 규칙은 docs/dialogue-style.md). 순수 Kotlin, 단위 테스트 대상.
 *
 * - 키 `질문ID|대상|상황`. 조회 순서 종 id → `@속성` → `*`
 * - `{name}` 같은 플레이스홀더는 [vars] 로 채운다. 값이 없는 플레이스홀더가 남는 문장은 고르지 않는다
 * - `{name:이/가}` 는 바로 앞 값의 받침으로 조사를 고른다 (받침 있으면 앞, 없으면 뒤. `으로/로` 는 ㄹ 받침도 뒤)
 * - 같은 키에서 바로 전에 쓴 문장은 피한다
 * - [line] 이 null 이면 호출 측(GleoFunctions)이 고정 문장을 쓴다
 */
class DialogueBank(
    private val entries: Map<String, List<String>>,
    private val species: Map<String, Species> = emptyMap(),
    private val random: Random = Random.Default,
) {
    data class Species(val nameKo: String, val attribute: String)

    private val lastByKey = HashMap<String, String>()

    val size: Int get() = entries.size

    /** Add display-only character copy without changing the gameplay species catalog. */
    fun supplementedBy(other: DialogueBank): DialogueBank =
        DialogueBank(entries + other.entries, species + other.species, random)

    fun speciesName(id: String?): String? = id?.let { species[it]?.nameKo }
    fun attributeOf(id: String?): String? = id?.let { species[it]?.attribute }

    @Synchronized
    fun line(question: String, speciesId: String?, attribute: String?, situation: String, vars: Map<String, String> = emptyMap()): String? {
        val targets = listOfNotNull(speciesId, (attribute ?: attributeOf(speciesId))?.let { "@$it" }, "*")
        for (t in targets) {
            val key = "$question|$t|$situation"
            val rendered = entries[key]?.mapNotNull { render(it, vars) }?.takeIf { it.isNotEmpty() } ?: continue
            val pool = rendered.filter { it != lastByKey[key] }.ifEmpty { rendered }
            return pool[random.nextInt(pool.size)].also { lastByKey[key] = it }
        }
        return null
    }

    companion object {
        val EMPTY = DialogueBank(emptyMap())
        private val JOSA = Regex("""\{([a-z_]+):([^/{}]+)/([^/{}]+)\}""")
        private val PLACEHOLDER = Regex("""\{[a-z_]+\}""")

        /** 플레이스홀더를 채운다. 채우지 못한 것이 남으면 null. */
        fun render(template: String, vars: Map<String, String>): String? {
            val withJosa = JOSA.replace(template) { m ->
                val v = vars[m.groupValues[1]] ?: return@replace m.value
                josa(v, m.groupValues[2], m.groupValues[3])
            }
            var out = withJosa
            PLACEHOLDER.findAll(withJosa).forEach { m ->
                val v = vars[m.value.trim('{', '}')] ?: return null
                out = out.replace(m.value, v)
            }
            return out.takeIf { !it.contains('{') }
        }

        /** 받침이 있으면 [withBatchim], 없으면 [without]. "으로/로" 는 ㄹ 받침도 [without]. 한글이 아니면 [without] */
        fun josa(word: String, withBatchim: String, without: String): String {
            val c = word.lastOrNull { !it.isWhitespace() } ?: return without
            if (c !in '가'..'힣') return without
            val jong = (c - '가') % 28
            if (jong == 0) return without
            if (withBatchim == "으로" && jong == 8) return without   // ㄹ 받침: 서울로
            return withBatchim
        }

        /**
         * @param includeUnreviewed true 면 reviewedBy 가 없는 문장도 쓴다 (디버그 빌드). release 는 검수된 것만
         */
        fun parse(dialogueJson: String, speciesJson: String?, includeUnreviewed: Boolean): DialogueBank {
            val json = Json { ignoreUnknownKeys = true }
            val entries = json.parseToJsonElement(dialogueJson).jsonObject["entries"]!!.jsonArray
                .map { it.jsonObject }
                .filter { includeUnreviewed || !it["reviewedBy"]?.jsonPrimitive?.contentOrNull.isNullOrBlank() }
                .associate { e -> e["key"]!!.jsonPrimitive.content to e["lines"]!!.jsonArray.map { it.jsonPrimitive.content } }
            val species = speciesJson?.let { s ->
                json.parseToJsonElement(s).jsonObject["species"]!!.jsonArray.associate { o: kotlinx.serialization.json.JsonElement ->
                    val sp = o as JsonObject
                    sp["id"]!!.jsonPrimitive.content to Species(sp["nameKo"]!!.jsonPrimitive.content, sp["attribute"]!!.jsonPrimitive.content)
                }
            } ?: emptyMap()
            return DialogueBank(entries, species)
        }

        /** assets 의 dialogue.json · species.json (빌드 때 레포 data/ 가 assets 로 들어간다). 실패하면 빈 뱅크 */
        fun load(assets: AssetManager, includeUnreviewed: Boolean): DialogueBank = runCatching {
            val d = assets.open("dialogue.json").bufferedReader().use { it.readText() }
            val s = runCatching { assets.open("species.json").bufferedReader().use { it.readText() } }.getOrNull()
            val base = parse(d, s, includeUnreviewed)
            val extra = runCatching {
                val copy = assets.open("companion-dialogue.json").bufferedReader().use { it.readText() }
                val display = assets.open("characters.json").bufferedReader().use { it.readText() }
                parse(copy, display, includeUnreviewed)
            }.getOrDefault(EMPTY)
            base.supplementedBy(extra)
        }.getOrElse { EMPTY }
    }
}
