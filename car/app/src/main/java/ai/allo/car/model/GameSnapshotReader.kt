package ai.allo.car.model

import kotlinx.serialization.json.*

object GameSnapshotReader {
    private val json = Json { ignoreUnknownKeys = true }
    private val blocks = setOf("affinity", "companion", "transferResult", "baseSummary", "travelRequest")
    private fun JsonObject.number(k: String): Long = (get(k) as? JsonPrimitive)?.takeUnless { it.isString }?.longOrNull?.takeIf { it >= 0 } ?: error(k)
    private fun JsonObject.word(k: String): String = (get(k) as? JsonPrimitive)?.takeIf { it.isString }?.content?.takeIf { it.isNotBlank() } ?: error(k)
    private fun JsonObject.optional(k: String): String? = if (get(k) == null || get(k) == JsonNull) null else word(k)
    private fun JsonObject.flag(k: String): Boolean = (get(k) as? JsonPrimitive)?.takeUnless { it.isString }?.booleanOrNull ?: error(k)
    private fun JsonObject.int(k: String): Int = number(k).also { require(it <= Int.MAX_VALUE) }.toInt()
    fun parse(raw: JsonObject): GameState? = runCatching {
        val version = (raw["contractVersion"] as? JsonPrimitive)?.takeUnless { it.isString }?.intOrNull
        val revision = if (version == 2) raw.number("gameRevision") else null
        val core = JsonObject(raw.filterKeys { it !in blocks && it != "contractVersion" && it != "gameRevision" })
        val base = json.decodeFromJsonElement<GameState>(core)
        require(base.ts > 0)
        require(base.stage in if (version == 2) setOf("idle", "incubating", "hatched", "failed") else setOf("idle", "incubating", "hatched"))
        require(base.progress.isFinite() && base.progress in 0.0..1.0)
        if (version != 2) return@runCatching base.copy(contractVersion = version)
        val invalid = mutableSetOf<String>()
        fun <T> block(key: String, read: (JsonObject) -> T): T? {
            val value = raw[key] ?: return null
            if (value == JsonNull) return null
            return runCatching { read(value as JsonObject) }.getOrElse { invalid.add(key); null }
        }
        val affinity = block("affinity") { AffinitySummary(it.int("score"), it.int("target").also { n -> require(n > 0) }, it.flag("ready")) }
        val companion = block("companion") { CompanionDisplay(it.word("displayId"), it.number("displayRevision"), it.word("speciesId"), it.word("location").also { v -> require(v in setOf("car", "phone")) }) }
        val transfer = block("transferResult") { TransferResult(it.word("requestId"), it.word("displayId"), it.number("requestRevision"), it.word("status").also { v -> require(v in setOf("accepted", "alreadyOnPhone", "busy", "staleSelection")) }, it.optional("resultLocation").also { v -> require(v == null || v in setOf("car", "phone")) }) }
        val home = block("baseSummary") {
            val structures = if (it["structureIds"] == null) emptyList() else (it["structureIds"] as JsonArray).map { item ->
                (item as JsonPrimitive).also { p -> require(p.isString && p.content.isNotBlank()) }.content
            }
            BaseSummary(it.optional("builderSpeciesId"), it.optional("cookSpeciesId"), it.optional("trainerSpeciesId"), structures, it.optional("lastMealId"), it.optional("activeTaskKind"))
        }
        val travel = block("travelRequest") { TravelRequest(it.word("wishId"), it.word("targetRegion").also { v -> require(v in setOf("coast", "mountain", "city")) }) }
        base.copy(contractVersion = version, gameRevision = revision, affinity = affinity, companion = companion,
            transferResult = transfer, baseSummary = home, travelRequest = travel, invalidBlocks = invalid)
    }.getOrNull()
}

/** Reconnect requires a fresh root. game.ts is not a connection heartbeat. */
class GameSnapshotReducer {
    var game: GameState = GameState(); private set
    var connected: Boolean = false; private set
    private var snapshot: JsonObject? = null
    fun apply(raw: JsonObject, root: Boolean): Boolean {
        if (!connected && !root) return false
        val next = GameSnapshotReader.parse(raw) ?: run { disconnect(); return false }
        if (game.hasV2Contract) {
            if (!next.hasV2Contract) return false
            if (next.gameRevision!! < game.gameRevision!!) return false
            if (next.gameRevision == game.gameRevision && raw != snapshot) return false
        }
        game = next; snapshot = raw; connected = true
        return true
    }
    fun disconnect() { connected = false }
    fun reset() { game = GameState(); snapshot = null; connected = false }
}
