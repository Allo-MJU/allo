package ai.allo.car.sync

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import java.io.IOException
import java.util.concurrent.TimeUnit

interface FirebaseTokenProvider {
    val configured: Boolean
    suspend fun token(forceRefresh: Boolean = false): String
    fun invalidate()
}
interface RefreshTokenStore { fun read(): String?; fun write(value: String) }

/** Anonymous UID survives process restarts via a protected refresh token. Never falls back to a new UID on refresh failure. */
class FirebaseIdentity(
    private val apiKey: String,
    private val store: RefreshTokenStore,
    private val client: OkHttpClient = OkHttpClient.Builder().callTimeout(10, TimeUnit.SECONDS).build(),
    private val identityUrl: String = "https://identitytoolkit.googleapis.com/v1/accounts:signUp",
    private val refreshUrl: String = "https://securetoken.googleapis.com/v1/token",
    private val clockMs: () -> Long = { System.nanoTime() / 1_000_000 },
) : FirebaseTokenProvider {
    private val mutex = Mutex()
    @Volatile private var idToken: String? = null
    @Volatile private var expiry = 0L
    override val configured get() = apiKey.isNotBlank()
    override fun invalidate() { expiry = 0 }
    override suspend fun token(forceRefresh: Boolean): String = mutex.withLock {
        if (!configured) throw IOException("Firebase authentication is not configured")
        if (!forceRefresh && clockMs() < expiry) idToken?.let { return@withLock it }
        withContext(Dispatchers.IO) {
            val refresh = store.read()
            val req = if (refresh == null) Request.Builder().url("$identityUrl?key=$apiKey")
                .post("{\"returnSecureToken\":true}".toRequestBody("application/json".toMediaType())).build()
            else Request.Builder().url("$refreshUrl?key=$apiKey")
                .post(FormBody.Builder().add("grant_type", "refresh_token").add("refresh_token", refresh).build()).build()
            val body = try { client.newCall(req).execute().use { response ->
                if (!response.isSuccessful) {
                    if (ai.allo.car.BuildConfig.DEBUG) {
                        val errorCode = runCatching { Json.parseToJsonElement(response.body?.string().orEmpty())
                            .jsonObject["error"]?.jsonObject?.get("message")?.jsonPrimitive?.content }
                            .getOrNull()?.takeIf { it.matches(Regex("[A-Z_]{1,80}")) } ?: "UNKNOWN"
                        android.util.Log.w("FirebaseIdentity", "Authentication HTTP ${response.code}; code=$errorCode; refreshing=${refresh != null}")
                    }
                    throw IOException("Firebase authentication failed (${response.code})")
                }
                Json.parseToJsonElement(response.body?.string().orEmpty()).jsonObject
            } } catch (error: Exception) {
                // Class names only: exception messages can include credential-bearing URLs.
                if (ai.allo.car.BuildConfig.DEBUG) android.util.Log.w("FirebaseIdentity",
                    "Authentication transport failed: ${error.javaClass.simpleName}; cause=${error.cause?.javaClass?.simpleName}")
                throw IOException("Firebase authentication unavailable; existing identity retained")
            }
            val nextId = body[if (refresh == null) "idToken" else "id_token"]?.jsonPrimitive?.content
            val nextRefresh = body[if (refresh == null) "refreshToken" else "refresh_token"]?.jsonPrimitive?.content
            val seconds = body[if (refresh == null) "expiresIn" else "expires_in"]?.jsonPrimitive?.longOrNull
            if (nextId.isNullOrBlank() || nextRefresh.isNullOrBlank() || seconds == null || seconds <= 0) {
                throw IOException("Invalid Firebase authentication response")
            }
            // Persist before using this identity remotely: a failed write must not strand ownership.
            store.write(nextRefresh)
            idToken = nextId
            expiry = clockMs() + (seconds * 1000 - 60_000).coerceAtLeast(0)
            nextId
        }
    }
}
