package ai.allo.car.sync

import ai.allo.car.model.TransferRequest
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import java.io.IOException
import kotlin.test.*

class FeatureWireTest {
    @Test fun `transfer wire revision and timestamp are numbers while ids survive retries`() {
        val request = TransferRequest("request-1", "display-2", 7)
        val first = companionTransferEvent(request, 100)
        val retry = companionTransferEvent(request, 200)
        assertEquals("companionTransferRequested", first["type"]!!.jsonPrimitive.content)
        val payload = first["payload"]!!.jsonObject
        assertFalse(payload["displayRevision"]!!.jsonPrimitive.isString)
        assertEquals(7L, payload["displayRevision"]!!.jsonPrimitive.long)
        assertEquals("phone", payload["target"]!!.jsonPrimitive.content)
        assertEquals(payload, retry["payload"])
        assertFalse(first["ts"]!!.jsonPrimitive.isString)
    }

    @Test fun `timeout reread uses bounded GET and reads complete snapshot`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("""{"contractVersion":2,"gameRevision":9}"""))
            server.start()
            val actual = FirebaseRest(server.url("/").toString()).get("sessions/s/game")
            assertEquals(9L, actual.jsonObject["gameRevision"]!!.jsonPrimitive.long)
            val request = server.takeRequest()
            assertEquals("GET", request.method)
            assertEquals("/sessions/s/game.json", request.path)
            assertEquals(0L, request.bodySize)
        }
    }

    @Test fun `failed GET cannot be mistaken for a persisted result`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(401).setBody("{}"))
            server.start()
            assertFailsWith<IOException> { FirebaseRest(server.url("/").toString()).get("sessions/s/game") }
        }
    }

    @Test fun `GET timeout cannot block indefinitely when no response arrives`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            server.start()
            assertFailsWith<IOException> {
                FirebaseRest(server.url("/").toString(), restCallTimeoutMs = 150).get("sessions/s/game")
            }
        }
    }
}
