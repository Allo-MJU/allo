package ai.allo.car.sync

import kotlinx.coroutines.runBlocking
import ai.allo.car.model.SessionMeta
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import java.io.IOException
import kotlin.test.*

class PairingRecoveryTest {
    private val tokens = object : FirebaseTokenProvider {
        override val configured = true
        override suspend fun token(forceRefresh: Boolean) = "test-token"
        override fun invalidate() = Unit
    }
    private val meta = SessionMeta(1_000L, "123456", false, "test")
    private val expiredAt = 86_401_000L

    @Test fun `normal renewal keeps same session and returns fresh code without recheck`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setBody("""{"result":{"sessionId":"s","pairCode":"654321","createdAt":1000,"paired":false,"carAppVersion":"test"}}"""))
            val renewed = api(server).renewOrCheckExpired("s", meta, "retry", expiredAt - 1)!!
            assertEquals("654321", renewed.pairCode)
            assertEquals(1_000L, renewed.createdAt)
            assertEquals(1, server.requestCount)
            assertEquals("/renewVehiclePairing", server.takeRequest().path)
        }
    }

    @Test fun `expired unavailable session is eligible for replacement only after server recheck`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(unavailable())
            server.enqueue(unavailable())
            assertNull(api(server).renewOrCheckExpired("s", meta, "retry", expiredAt))
            assertEquals("/renewVehiclePairing", server.takeRequest().path)
            val recheck = server.takeRequest()
            assertEquals("/createVehicleSession", recheck.path)
            assertTrue(recheck.body.readUtf8().contains("\"sessionId\":\"s\""))
        }
    }

    @Test fun `server paired state wins over delayed local metadata and clock skew`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(unavailable())
            server.enqueue(MockResponse().setBody("""{"result":{"sessionId":"s","pairCode":"123456","createdAt":1000,"paired":true,"carAppVersion":"test"}}"""))
            assertTrue(api(server).renewOrCheckExpired("s", meta, "retry", expiredAt)!!.paired)
            assertEquals(2, server.requestCount)
        }
    }

    @Test fun `live unpaired recheck preserves renewal failure when local clock is ahead`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(unavailable())
            server.enqueue(MockResponse().setBody("""{"result":{"sessionId":"s","pairCode":"123456","createdAt":1000,"paired":false,"carAppVersion":"test"}}"""))
            assertFailsWith<SessionUnavailableException> {
                api(server).renewOrCheckExpired("s", meta, "retry", expiredAt)
            }
            assertEquals(2, server.requestCount)
        }
    }

    @Test fun `unavailable session before ttl keeps existing renewal failure`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(unavailable())
            assertFailsWith<SessionUnavailableException> {
                api(server).renewOrCheckExpired("s", meta, "retry", expiredAt - 1)
            }
            assertEquals(1, server.requestCount)
        }
    }

    @Test fun `transport failure cannot authorize replacing an expired session`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setResponseCode(503))
            assertFailsWith<IOException> { api(server).renewOrCheckExpired("s", meta, "retry", expiredAt) }
            assertEquals(1, server.requestCount)
        }
    }

    @Test fun `authentication failure during authoritative recheck cannot replace session`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(unavailable())
            repeat(2) { server.enqueue(MockResponse().setResponseCode(401)) }
            assertFailsWith<IOException> { api(server).renewOrCheckExpired("s", meta, "retry", expiredAt) }
            assertEquals(3, server.requestCount)
        }
    }

    @Test fun `network failure during authoritative recheck cannot replace session`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(unavailable())
            server.enqueue(MockResponse().setResponseCode(503))
            assertFailsWith<IOException> { api(server).renewOrCheckExpired("s", meta, "retry", expiredAt) }
            assertEquals(2, server.requestCount)
        }
    }

    @Test fun `unclassified forbidden response cannot authorize session replacement`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setResponseCode(403).setBody("forbidden"))
            assertFailsWith<IOException> { api(server).renewOrCheckExpired("s", meta, "retry", expiredAt) }
            assertEquals(1, server.requestCount)
        }
    }

    @Test fun `replacement rechecks live identity pairing parking end and ttl`() {
        assertTrue(canReplaceExpiredPairing("s", "s", meta, expiredAt, true, false))
        assertFalse(canReplaceExpiredPairing("old", "s", meta, expiredAt, true, false))
        assertFalse(canReplaceExpiredPairing("s", "s", meta.copy(paired = true), expiredAt, true, false))
        assertFalse(canReplaceExpiredPairing("s", "s", meta, expiredAt, false, false))
        assertFalse(canReplaceExpiredPairing("s", "s", meta, expiredAt, true, true))
        assertFalse(canReplaceExpiredPairing("s", "s", meta, expiredAt - 1, true, false))
        assertFalse(canReplaceExpiredPairing("s", "s", meta, 999L, true, false))
    }

    @Test fun `permission denied callable is distinguishable from transport failure`() = runBlocking<Unit> {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(unavailable())
            val api = api(server)
            assertFailsWith<SecurityException> { api.create("s", "test") }
            server.enqueue(MockResponse().setResponseCode(503))
            assertFailsWith<IOException> { api.create("s", "test") }
        }
    }

    private fun api(server: MockWebServer) = FirebaseSessionApi(tokens, "allo-test", "asia-northeast3",
        server.url("/createVehicleSession").toString())
    private fun unavailable() = MockResponse().setResponseCode(403)
        .setBody("""{"error":{"status":"PERMISSION_DENIED","message":"Session is unavailable."}}""")
}
