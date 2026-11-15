package ai.allo.car.sync

import ai.allo.car.model.SessionMeta
import ai.allo.car.navi.DestinationVisit
import kotlinx.serialization.encodeToString
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import java.io.IOException
import java.util.concurrent.TimeUnit

internal class SessionUnavailableException : SecurityException("Session is unavailable")

/** The server owns session ACLs and pairing secrets. Clients cannot create meta directly. */
class FirebaseSessionApi(
    private val tokens: FirebaseTokenProvider,
    project: String,
    region: String,
    private val endpoint: String = "https://$region-$project.cloudfunctions.net/createVehicleSession",
    private val client: OkHttpClient = OkHttpClient.Builder().callTimeout(15, TimeUnit.SECONDS).build(),
) {
    val configured = project.matches(Regex("[a-z][a-z0-9-]{4,61}[a-z0-9]")) && region.matches(Regex("[a-z]+-[a-z]+[0-9]")) && tokens.configured
    suspend fun create(sessionId: String, appVersion: String): SessionMeta = call(sessionId, appVersion, null)
    suspend fun renew(sessionId: String, appVersion: String, requestId: String): SessionMeta = call(sessionId, appVersion, requestId)

    suspend fun recordVisit(visit: DestinationVisit) {
        if (!configured) throw IOException("Firebase session service is not configured")
        val payload = buildJsonObject { put("data", Json.encodeToJsonElement(DestinationVisit.serializer(), visit)) }
        val target = endpoint.substringBeforeLast('/') + "/recordDestinationVisit"
        for (attempt in 0..1) {
            val token = tokens.token(forceRefresh = attempt > 0)
            val result = withContext(Dispatchers.IO) {
                client.newCall(Request.Builder().url(target).header("Authorization", "Bearer $token")
                    .post(payload.toString().toRequestBody("application/json".toMediaType())).build()).execute().use { response ->
                    if (response.code == 401 && attempt == 0) return@use null
                    if (!response.isSuccessful) throw IOException("Visit service rejected request")
                    Json.parseToJsonElement(response.body?.string().orEmpty()).jsonObject
                }
            } ?: continue
            val value = (result["result"] ?: result["data"])?.jsonObject ?: throw IOException("Invalid visit response")
            if (value["visitId"]?.jsonPrimitive?.content != visit.visitId || value["recorded"]?.jsonPrimitive?.booleanOrNull != true)
                throw IOException("Invalid visit acknowledgement")
            return
        }
        throw IOException("Firebase authentication was rejected")
    }

    private suspend fun call(sessionId: String, appVersion: String, requestId: String?): SessionMeta {
        if (!configured) throw IOException("Firebase session service is not configured")
        val data = buildJsonObject { put("data", buildJsonObject {
            put("sessionId", sessionId)
            if (requestId == null) put("carAppVersion", appVersion) else put("requestId", requestId)
        }) }
        val target = if (requestId == null) endpoint else endpoint.substringBeforeLast('/') + "/renewVehiclePairing"
        for (attempt in 0..1) {
            val token = tokens.token(forceRefresh = attempt > 0)
            val result = withContext(Dispatchers.IO) {
                try { client.newCall(Request.Builder().url(target).header("Authorization", "Bearer $token")
                    .post(data.toString().toRequestBody("application/json".toMediaType())).build()).execute().use { response ->
                    if (response.code == 401 && attempt == 0) return@use null
                    val body = response.body?.string().orEmpty()
                    if (response.code == 403 && runCatching {
                        Json.parseToJsonElement(body).jsonObject["error"]?.jsonObject
                            ?.get("status")?.jsonPrimitive?.content == "PERMISSION_DENIED"
                    }.getOrDefault(false)) throw SessionUnavailableException()
                    if (!response.isSuccessful) throw IOException("Session service rejected request")
                    Json.parseToJsonElement(body).jsonObject
                } } catch (unavailable: SessionUnavailableException) { throw unavailable }
                catch (_: Exception) { throw IOException("Firebase session service unavailable") }
            } ?: continue
            val value = (result["result"] ?: result["data"])?.jsonObject ?: throw IOException("Invalid session service response")
            if (value["sessionId"]?.jsonPrimitive?.content != sessionId) throw IOException("Session identity mismatch")
            val code = value["pairCode"]?.jsonPrimitive?.content.orEmpty()
            val created = value["createdAt"]?.jsonPrimitive?.longOrNull ?: 0
            if (!code.matches(Regex("[0-9]{6}")) || created <= 0) throw IOException("Invalid session metadata")
            return SessionMeta(created, code, value["paired"]?.jsonPrimitive?.booleanOrNull ?: false,
                value["carAppVersion"]?.jsonPrimitive?.content ?: appVersion)
        }
        throw IOException("Firebase authentication was rejected")
    }
}
