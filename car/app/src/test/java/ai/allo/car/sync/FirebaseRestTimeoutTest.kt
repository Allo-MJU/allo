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

    /** 헤더는 오고 본문이 중간에 멈추는 경우. 본문 읽기 예외가 callback 밖으로 새면 put() 이 끝나지 않는다 (PR #27 리뷰) */
    @Test fun `put fails instead of hanging when the body stalls after headers`() {
        ServerSocket(0).use { server ->
            val held = mutableListOf<java.net.Socket>()
            thread(isDaemon = true) {
                runCatching {
                    while (true) {
                        val s = server.accept(); held += s
                        val r = s.getInputStream().bufferedReader()
                        while (true) { val line = r.readLine() ?: break; if (line.isEmpty()) break }   // 요청 헤더 소비
                        s.getOutputStream().apply {
                            write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n{}".toByteArray())
                            flush()
                        }   // 100바이트라더니 2바이트만 보내고 멈춤
                    }
                }
            }
            val rest = FirebaseRest("http://127.0.0.1:${server.localPort}", restCallTimeoutMs = 300)
            val t0 = System.currentTimeMillis()
            val result = runBlocking {
                kotlinx.coroutines.withTimeoutOrNull(3_000) { runCatching { rest.put("sessions/x/vehicle", "{}") } }
            }
            assertNotNull(result, "put() 이 끝나지 않았다")
            assertTrue(result.exceptionOrNull() is IOException, "IOException 이어야 한다: $result")
            assertTrue(System.currentTimeMillis() - t0 < 3_000)
            held.forEach { runCatching { it.close() } }
        }
    }
}
