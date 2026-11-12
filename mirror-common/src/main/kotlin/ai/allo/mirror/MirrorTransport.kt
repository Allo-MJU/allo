package ai.allo.mirror

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.URL
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

data class MirrorFrame(val bytes: ByteArray, val sequence: Long, val ageMs: Long)

/** Debug prototype: authenticated HTTPS, explicit leaf certificate pin + normal hostname check. */
class MirrorTransport(private val config: MirrorConfig) {
    private val socketFactory = SSLContext.getInstance("TLSv1.2").apply {
        init(null, arrayOf(object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {
                throw CertificateException("Client trust not supported")
            }
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                val cert = chain.firstOrNull() ?: throw CertificateException("Missing certificate")
                cert.checkValidity()
                val actual = MessageDigest.getInstance("SHA-256").digest(cert.encoded)
                val expected = config.certificateSha256.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
                if (!MessageDigest.isEqual(actual, expected)) throw CertificateException("Certificate mismatch")
            }
        }), null)
    }.socketFactory

    fun upload(jpeg: ByteArray): Boolean {
        require(jpeg.size <= MAX_FRAME_BYTES && validJpeg(jpeg)) { "Invalid frame" }
        return request("POST") { connection, _ ->
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "image/jpeg")
            connection.setFixedLengthStreamingMode(jpeg.size)
            connection.outputStream.use { it.write(jpeg) }
            when (connection.responseCode) {
                200, 201, 204 -> true
                else -> throw IOException("Frame upload failed")
            }
        }
    }

    fun clear() { request("DELETE") { connection, _ ->
        if (connection.responseCode !in listOf(200, 204)) throw IOException("Frame clear failed")
    } }

    fun fetch(): MirrorFrame? = request("GET") { connection, started ->
        when (connection.responseCode) {
            204 -> null
            200 -> {
                if (connection.contentType?.substringBefore(';') != "image/jpeg") throw IOException("Invalid frame type")
                val size = connection.contentLength
                if (size !in 4..MAX_FRAME_BYTES) throw IOException("Invalid frame length")
                val sequence = connection.getHeaderField("X-Frame-Sequence")?.toLongOrNull()
                val age = connection.getHeaderField("X-Frame-Age-Ms")?.toLongOrNull()
                if (sequence == null || sequence < 1 || age == null || age !in 0..MAX_FRAME_AGE_MS) throw IOException("Invalid frame metadata")
                val bytes = connection.inputStream.use { stream ->
                    val out = ByteArrayOutputStream(size)
                    val buffer = ByteArray(8192)
                    while (out.size() < size) {
                        if (elapsedMs(started) > REQUEST_TIMEOUT_MS) throw IOException("Frame expired")
                        val read = stream.read(buffer, 0, minOf(buffer.size, size - out.size()))
                        if (read < 0) throw IOException("Incomplete frame")
                        out.write(buffer, 0, read)
                    }
                    out.toByteArray()
                }
                val effectiveAge = age + elapsedMs(started)
                if (!validJpeg(bytes)) throw IOException("Invalid JPEG")
                if (effectiveAge > MAX_FRAME_AGE_MS) null else MirrorFrame(bytes, sequence, effectiveAge)
            }
            else -> throw IOException("Frame receive failed")
        }
    }

    private fun <T> request(method: String, operation: (HttpsURLConnection, Long) -> T): T {
        val connection = URL(config.url.trimEnd('/') + "/frame").openConnection() as HttpsURLConnection
        connection.sslSocketFactory = socketFactory
        // Keep the platform hostname verifier. A pinned certificate still must match the endpoint.
        connection.instanceFollowRedirects = false
        connection.useCaches = false
        connection.connectTimeout = REQUEST_TIMEOUT_MS.toInt()
        connection.readTimeout = REQUEST_TIMEOUT_MS.toInt()
        connection.requestMethod = method
        connection.setRequestProperty("Authorization", "Bearer ${config.token}")
        connection.setRequestProperty("Cache-Control", "no-store")
        val started = System.nanoTime()
        val timeout = deadlines.schedule({ connection.disconnect() }, REQUEST_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        return try { operation(connection, started) } finally {
            timeout.cancel(false)
            connection.disconnect()
        }
    }

    companion object {
        const val MAX_FRAME_BYTES = 512 * 1024
        const val MAX_FRAME_AGE_MS = 1500L
        const val REQUEST_TIMEOUT_MS = 1500L
        private val deadlines = Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "mirror-network-deadline").apply { isDaemon = true }
        }
        private fun elapsedMs(started: Long) = (System.nanoTime() - started) / 1_000_000
        fun validJpeg(bytes: ByteArray): Boolean = bytes.size >= 4 &&
            bytes[0] == 0xff.toByte() && bytes[1] == 0xd8.toByte() &&
            bytes[bytes.size - 2] == 0xff.toByte() && bytes.last() == 0xd9.toByte()
    }
}
