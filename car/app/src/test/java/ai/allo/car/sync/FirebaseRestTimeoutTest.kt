package ai.allo.car.sync

import kotlinx.coroutines.runBlocking
import java.io.IOException
import java.net.ServerSocket
import kotlin.concurrent.thread
import kotlin.test.*

class FirebaseRestTimeoutTest {
    @Test fun `put fails instead of hanging when the server accepts but never answers`() {
        ServerSocket(0).use { server ->
            val held = mutableListOf<java.net.Socket>()
            thread(isDaemon = true) { runCatching { while (true) held += server.accept() } }   // 받기만 하고 응답 없음
            val rest = FirebaseRest("http://127.0.0.1:${server.localPort}", restCallTimeoutMs = 300)
            val t0 = System.currentTimeMillis()
            assertFailsWith<IOException> { runBlocking { rest.put("sessions/x/vehicle", "{}") } }
            assertTrue(System.currentTimeMillis() - t0 < 5_000)
            held.forEach { runCatching { it.close() } }
        }
    }
}
