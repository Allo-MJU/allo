package ai.allo.car.voice

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.File
import java.io.IOException
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Runtime configuration contains an app-user token supplier, never a DashScope credential. */
internal data class PlazaCloudConfig(val baseUrl: String, val revision: String,
                                     val token: suspend () -> String)
internal object PlazaCloudVoice {
    @Volatile var config: PlazaCloudConfig? = null
    fun configure(baseUrl: String, revision: String, allowLocal: Boolean, token: suspend () -> String) {
        config = if (validBaseUrl(baseUrl, allowLocal))
            PlazaCloudConfig(baseUrl.trimEnd('/'), revision, token) else null
    }
    /** Debug-only local voice testing: a loopback gateway with TTS_DEV_TOKEN, no Firebase sign-in. */
    fun tokenSupplier(baseUrl: String, debug: Boolean, devToken: String,
                      firebase: suspend () -> String): suspend () -> String =
        if (debug && devToken.isNotBlank() && validBaseUrl(baseUrl, allowLocal = true) &&
            URI(baseUrl).scheme == "http") ({ devToken }) else firebase

    fun validBaseUrl(value: String, allowLocal: Boolean): Boolean = runCatching {
        val u = URI(value)
        u.host != null && u.rawUserInfo == null && u.rawQuery == null && u.rawFragment == null &&
            (u.scheme == "https" || (allowLocal && u.scheme == "http" &&
                u.host in setOf("localhost", "127.0.0.1", "10.0.2.2")))
    }.getOrDefault(false)
}

internal fun interface PlazaDownload {
    suspend fun fetch(url: String, token: String, species: String, text: String): ByteArray
}

/** Only fully validated WAVs are published. Cache keys include voice revision and server identity. */
internal class PlazaCloudCache(
    private val directory: File,
    private val config: PlazaCloudConfig,
    private val download: PlazaDownload = HttpPlazaDownload(),
) {
    suspend fun resolve(entry: PlazaRecordings.Entry): File {
        require(PlazaRecordings.entries.contains(entry)) { "Unknown plaza line" }
        return resolveClip(entry.species, entry.text, "plaza")
    }

    suspend fun resolveCharacter(species: String, text: String, purpose: String): File {
        require(purpose in setOf("dialogue", "destination"))
        require(PlazaRecordings.entries.any { it.species == species }) { "Unknown character" }
        require(text.isNotBlank() && text.length <= 600)
        // The gateway additionally checks the exact authored lines/templates for this purpose.
        return resolveClip(species, text, "car/$purpose")
    }

    private suspend fun resolveClip(species: String, text: String, route: String): File = withContext(Dispatchers.IO) {
        directory.mkdirs()
        val key = MessageDigest.getInstance("SHA-256").digest(
            listOf(config.baseUrl, config.revision, route, species, text).joinToString("\u0000").toByteArray())
            .joinToString("") { "%02x".format(it) }
        val destination = File(directory, "$key.wav")
        if (destination.isFile && destination.length() in 44..MAX_BYTES.toLong() &&
            validPcmWav(destination.readBytes())) return@withContext destination
        destination.delete()
        val token = config.token()
        require(token.isNotBlank()) { "Authentication unavailable" }
        val bytes = download.fetch("${config.baseUrl}/v1/$route/clip", token, species, text)
        coroutineContext.ensureActive()
        if (!validPcmWav(bytes)) throw IOException("Invalid speech audio")
        val temporary = File.createTempFile("clip-", ".part", directory)
        try {
            temporary.writeBytes(bytes)
            coroutineContext.ensureActive()
            if (!temporary.renameTo(destination)) throw IOException("Speech cache unavailable")
            // Bound each persistent voice cache to 48 complete clips.
            directory.listFiles { f -> f.extension == "wav" }?.sortedByDescending { it.lastModified() }
                ?.drop(48)?.forEach { it.delete() }
            destination
        } finally { temporary.delete() }
    }

    companion object {
        const val MAX_BYTES = 8 * 1024 * 1024
        fun validPcmWav(data: ByteArray): Boolean {
            if (data.size !in 44..MAX_BYTES) return false
            fun tag(i: Int, s: String) = i + 4 <= data.size && String(data, i, 4, Charsets.US_ASCII) == s
            fun u16(i: Int) = (data[i].toInt() and 255) or ((data[i + 1].toInt() and 255) shl 8)
            fun u32(i: Int): Long = (0..3).fold(0L) { v, n -> v or ((data[i + n].toLong() and 255) shl (n * 8)) }
            if (!tag(0, "RIFF") || !tag(8, "WAVE") || u32(4) + 8 != data.size.toLong()) return false
            var offset = 12
            var format = false
            var samples = false
            while (offset + 8 <= data.size) {
                val size = u32(offset + 4)
                if (size > data.size - offset - 8) return false
                if (tag(offset, "fmt ")) {
                    if (size < 16) return false
                    val p = offset + 8
                    format = u16(p) == 1 && u16(p + 2) == 1 && u32(p + 4) == 24000L &&
                        u32(p + 8) == 48000L && u16(p + 12) == 2 && u16(p + 14) == 16
                }
                if (tag(offset, "data")) samples = size > 0 && size % 2 == 0L
                offset += 8 + size.toInt() + (size.toInt() and 1)
            }
            return format && samples && offset == data.size
        }
    }
}

private class HttpPlazaDownload : PlazaDownload {
    private val client = OkHttpClient.Builder().callTimeout(25, TimeUnit.SECONDS)
        .connectTimeout(5, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS)
        .followRedirects(false).followSslRedirects(false).build()
    override suspend fun fetch(url: String, token: String, species: String, text: String): ByteArray =
        suspendCancellableCoroutine { continuation ->
            val json = buildJsonObject { put("species", species); put("text", text) }.toString()
            val call = client.newCall(Request.Builder().url(url)
                .header("Authorization", "Bearer $token")
                .post(json.toRequestBody("application/json".toMediaType())).build())
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(IOException("Speech unavailable"))
                }
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val bytes = response.use {
                            if (!it.isSuccessful || it.header("Content-Type")?.substringBefore(';') != "audio/wav")
                                throw IOException("Speech unavailable")
                            val body = it.body ?: throw IOException("Missing speech")
                            if (body.contentLength() > PlazaCloudCache.MAX_BYTES) throw IOException("Speech too large")
                            body.byteStream().use { stream ->
                                val output = java.io.ByteArrayOutputStream()
                                val buffer = ByteArray(8192)
                                while (true) {
                                    val count = stream.read(buffer)
                                    if (count < 0) break
                                    if (output.size() + count > PlazaCloudCache.MAX_BYTES) throw IOException("Speech too large")
                                    output.write(buffer, 0, count)
                                }
                                output.toByteArray()
                            }
                        }
                        if (continuation.isActive) continuation.resume(bytes)
                    } catch (_: Exception) {
                        if (continuation.isActive) continuation.resumeWithException(IOException("Speech unavailable"))
                    }
                }
            })
        }
}
