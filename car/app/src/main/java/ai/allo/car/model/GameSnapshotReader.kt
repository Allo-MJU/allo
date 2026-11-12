package ai.allo.car.model

import kotlinx.serialization.json.*

object GameSnapshotReader {
    private val json = Json { ignoreUnknownKeys = true }
    private val blocks = setOf("affinity", "companion", "transferResult", "baseSummary", "travelRequest", "fishing", "collectionSummary")
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
        val affinity = block("affinity") {
            if (it["phase"] == null) {
                val score = it.int("score"); val target = it.int("target")
                require(target > 0 && score <= target)
                AffinitySummary(score, target, it.flag("ready"))
            } else {
                val score = (it["score"] as? JsonPrimitive)?.takeUnless { p -> p.isString }?.doubleOrNull ?: error("score")
                require(score.isFinite() && score in 0.0..100.0 && it.int("target") == 100)
                val phase = it.word("phase"); val photo = it.flag("photoCompleted")
                require(when (phase) {
                    "incubating", "photoRequired", "resultPending" -> base.stage == "incubating"
                    "hatched" -> base.stage == "hatched"
                    "failed", "discarded" -> base.stage == "failed"
                    else -> false
                })
                require(phase != "photoRequired" || score == 50.0 && !photo)
                require(phase !in setOf("hatched", "resultPending") || score == 100.0 && photo)
                AffinitySummary(score, 100, phase = phase, photoCompleted = photo)
            }
        }
        val companion = block("companion") { CompanionDisplay(it.word("displayId"), it.number("displayRevision"), it.word("speciesId"), it.word("location").also { v -> require(v in setOf("car", "phone")) }) }
        val transfer = block("transferResult") { TransferResult(it.word("requestId"), it.word("displayId"), it.number("requestRevision"), it.word("status").also { v -> require(v in setOf("accepted", "alreadyOnPhone", "busy", "staleSelection")) }, it.optional("resultLocation").also { v -> require(v == null || v in setOf("car", "phone")) }) }
        val home = block("baseSummary") {
            val structures = if (it["structureIds"] == null) emptyList() else (it["structureIds"] as JsonArray).map { item ->
                (item as JsonPrimitive).also { p -> require(p.isString && p.content.isNotBlank()) }.content
            }
            fun numbers(key: String): Map<String, Long> = when (val value = it[key]) {
                null, JsonNull -> emptyMap()
                else -> (value as JsonObject).keys.associateWith { name -> value.number(name) }
            }
            val levels = numbers("facilityLevels").mapValues { (name, level) ->
                require(name in setOf("workshop", "kitchen", "training") && level <= 3)
                level.toInt()
            }
            val tasks = when (val value = it["activeTaskKinds"]) {
                null, JsonNull -> emptyList()
                else -> (value as JsonArray).map { item ->
                    (item as JsonPrimitive).also { p -> require(p.isString && p.content in setOf("building", "cooking", "training")) }.content
                }.also { list -> require(list.distinct().size == list.size) }
            }
            BaseSummary(it.optional("builderSpeciesId"), it.optional("cookSpeciesId"), it.optional("trainerSpeciesId"), structures,
                it.optional("lastMealId"), it.optional("activeTaskKind"), levels, tasks, numbers("foodInventory"), numbers("recipeBook"))
        }
        val collection = block("collectionSummary") {
            require(it.int("version") == 1)
            // RTDB drops empty arrays. An explicit count distinguishes empty from missing data.
            val rawIds = it["speciesIds"]
            val ids = if (rawIds == null || rawIds == JsonNull) {
                require(it.number("speciesCount") == 0L)
                emptyList()
            } else (rawIds as JsonArray).map { item ->
                (item as JsonPrimitive).also { p -> require(p.isString && Regex("[a-z][a-z0-9_]{0,63}").matches(p.content)) }.content
            }
            if (it["speciesCount"] != null) require(it.number("speciesCount") == ids.size.toLong())
            require(ids.size <= 1000 && ids.distinct().size == ids.size)
            CollectionSummary(1, it.number("wood"), it.number("stone"), it.number("ingredient"), ids)
        }
        val travel = block("travelRequest") { TravelRequest(it.word("wishId"), it.word("targetRegion").also { v -> require(v in setOf("coast", "mountain", "city")) }) }
        val fishing = block("fishing") {
            require(it.int("version") == 1)
            val activity = (it["activityId"] as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: error("activityId")
            val state = it.word("state").also { v -> require(v in setOf("ready", "running", "paused", "saving", "reward", "saveFailed")) }
            val elapsed = it.number("elapsedMs"); val target = it.number("targetMs")
            require(target == 60_000L && elapsed <= target)
            require(state in setOf("ready", "saving", "saveFailed") || activity.isNotBlank())
            val total = it.number("totalRecords"); val reward = it.optional("rewardName")
            require(state != "reward" || reward != null && total > 0)
            FishingSnapshot(1, it.word("leaseId"), it.word("displayId"), it.number("displayRevision"),
                activity, it.number("cycle"), state, elapsed, target, total, reward, it.optional("requestId")).also { f ->
                require(companion?.location == "car" && companion.displayId == f.displayId && companion.displayRevision == f.displayRevision)
            }
        }
        base.copy(contractVersion = version, gameRevision = revision, affinity = affinity, companion = companion,
            transferResult = transfer, baseSummary = home, travelRequest = travel, fishing = fishing, collectionSummary = collection, invalidBlocks = invalid)
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
