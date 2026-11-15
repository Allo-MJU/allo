package ai.allo.car.navi

import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

class VisitOutbox(private val read: () -> String, private val write: (String) -> Boolean) {
    @Synchronized fun pending(): List<DestinationVisit> = Json.decodeFromString(read())
    @Synchronized fun add(visit: DestinationVisit): Boolean {
        val current = pending()
        if (current.any { it.visitId == visit.visitId }) {
            if (current.none { it == visit }) return false
            return write(Json.encodeToString(current))
        }
        return write(Json.encodeToString(current + visit))
    }
    @Synchronized fun remove(id: String): Boolean = write(Json.encodeToString(pending().filterNot { it.visitId == id }))
}
