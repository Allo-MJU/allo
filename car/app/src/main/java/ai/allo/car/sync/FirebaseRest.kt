package ai.allo.car.sync

import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonObject
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Firebase Realtime Database 를 REST + SSE 로 쓴다.
 * Firebase Android SDK / Google Play services / google-services.json 이 필요 없다 → Pleos 에뮬레이터 호환 리스크 0.
 *
 *   PUT    {db}/sessions/{sid}/vehicle.json     1초마다 덮어쓰기
 *   PATCH  {db}/sessions/{sid}/meta.json        부분 갱신
 *   POST   {db}/sessions/{sid}/events.json      pushId 생성
 *   GET    {db}/sessions/{sid}/game.json  Accept: text/event-stream   → put/patch 이벤트
 */
class FirebaseRest(
    private val dbUrl: String,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .writeTimeout(5, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)   // SSE 는 무기한
        .build(),
    /** 일반 REST(PUT/PATCH/POST) 한 번의 전체 limit. 응답이 멈추면 IOException (PR #27 리뷰) */
    restCallTimeoutMs: Long = 10_000,
) {
    /**
     * SSE 와 같은 연결 풀을 쓰되 응답 대기를 제한한 클라이언트. readTimeout(0) 을 그대로 쓰면
     * 서버가 요청을 받고 응답하지 않을 때 PUT 이 끝나지 않아 1초 발행 루프와 sessionEnd 전송이 멈춘다.
     */
    private val restClient: OkHttpClient = client.newBuilder()
        .readTimeout(restCallTimeoutMs, TimeUnit.MILLISECONDS)
        .callTimeout(restCallTimeoutMs, TimeUnit.MILLISECONDS)
        .build()

    val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = true }
    val isConfigured: Boolean get() = dbUrl.isNotBlank()

    private fun url(path: String) = "${dbUrl.trimEnd('/')}/${path.trimStart('/')}.json"

    suspend fun put(path: String, body: String) = send("PUT", path, body)
    suspend fun patch(path: String, body: String) = send("PATCH", path, body)
    suspend fun post(path: String, body: String) = send("POST", path, body)

    private suspend fun send(method: String, path: String, body: String): String =
        suspendCancellableCoroutine { cont ->
            val req = Request.Builder().url(url(path)).method(method, body.toRequestBody(JSON)).build()
            val call = restClient.newCall(req)
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) { cont.resumeWithException(e) }
                override fun onResponse(call: Call, response: Response) {
                    response.use {
                        if (it.isSuccessful) cont.resume(it.body?.string().orEmpty())
                        else cont.resumeWithException(IOException("HTTP ${it.code} $method $path"))
                    }
                }
            })
        }

    /**
     * 노드 전체를 JsonElement 로 흘려준다. put 이벤트는 전체, patch 는 변경분만 오므로
     * 호출 측에서 최근 전체 상태에 머지한다.
     */
    fun stream(path: String): Flow<SseEvent> = callbackFlow {
        val req = Request.Builder().url(url(path)).header("Accept", "text/event-stream").build()
        val source = EventSources.createFactory(client).newEventSource(req, object : EventSourceListener() {
            override fun onEvent(eventSource: EventSource, id: String?, type: String?, data: String) {
                if (type != "put" && type != "patch") return   // keep-alive, cancel, auth_revoked 무시
                val obj = runCatching { json.parseToJsonElement(data).jsonObject }.getOrNull() ?: return
                val p = obj["path"]?.toString()?.trim('"') ?: "/"
                val d = obj["data"] ?: return
                trySend(SseEvent(type, p, d))
            }
            override fun onFailure(eventSource: EventSource, t: Throwable?, response: Response?) {
                close(t ?: IOException("SSE closed ${response?.code}"))
            }
        })
        awaitClose { source.cancel() }
    }

    data class SseEvent(val type: String, val path: String, val data: JsonElement)

    private companion object { val JSON = "application/json; charset=utf-8".toMediaType() }
}
