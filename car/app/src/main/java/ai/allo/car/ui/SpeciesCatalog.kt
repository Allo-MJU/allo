package ai.allo.car.ui

import kotlinx.serialization.json.*

data class PetSpecies(val id: String, val name: String, val attribute: String, val sprite: String?)

/** Display-only metadata from shared species.json, never a second game rules engine. */
class SpeciesCatalog private constructor(val entries: Map<String, PetSpecies>) {
    operator fun get(id: String?): PetSpecies? = entries[id]
    companion object {
        val EMPTY = SpeciesCatalog(emptyMap())
        fun parse(text: String): SpeciesCatalog = runCatching {
            val list = Json.parseToJsonElement(text).jsonObject["species"]?.jsonArray ?: return EMPTY
            SpeciesCatalog(list.mapNotNull { item ->
                val obj = item as? JsonObject ?: return@mapNotNull null
                val id = (obj["id"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
                val name = (obj["nameKo"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
                if (id.isBlank() || name.isBlank()) return@mapNotNull null
                val sprite = (obj["sprite"] as? JsonPrimitive)?.contentOrNull
                    ?.takeIf { Regex("species/[a-z0-9_]+\\.png").matches(it) }
                id to PetSpecies(id, name.take(20), (obj["attribute"] as? JsonPrimitive)?.contentOrNull ?: "normal", sprite)
            }.toMap())
        }.getOrDefault(EMPTY)
    }
}
