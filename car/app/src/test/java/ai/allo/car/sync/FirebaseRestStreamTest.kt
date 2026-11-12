package ai.allo.car.sync

import java.io.IOException
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import kotlin.test.Test
import kotlin.test.assertTrue

class FirebaseRestStreamTest {
    @Test fun `auth revocation and cancel do not silently keep a live subscription`() = runBlocking {
        for (event in listOf("cancel", "auth_revoked")) {
            MockWebServer().use { server ->
                server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream")
                    .setBody("event: $event\ndata: \"access ended\"\n\n"))
                server.start()
                val result = runCatching {
                    withTimeout(3000) { FirebaseRest(server.url("/").toString()).stream("sessions/test/game").toList() }
                }
                assertTrue(result.exceptionOrNull() is IOException, "Expected stream failure for $event")
            }
        }
    }

    @Test fun `clean socket close and malformed SSE end liveness`() = runBlocking {
        for (body in listOf("", "event: put\ndata: invalid-json\n\n")) {
            MockWebServer().use { server ->
                server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream").setBody(body))
                server.start()
                val result = runCatching {
                    withTimeout(3000) { FirebaseRest(server.url("/").toString()).stream("sessions/test/game").toList() }
                }
                assertTrue(result.exceptionOrNull() is IOException)
            }
        }
    }
}
