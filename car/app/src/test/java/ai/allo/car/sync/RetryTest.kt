package ai.allo.car.sync

import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import java.io.IOException
import kotlin.test.*

class RetryTest {
    @Test fun `succeeds after transient failures with backoff`() = runBlocking {
        val sleeps = mutableListOf<Long>()
        var calls = 0
        val ok = retrying(5, sleep = { sleeps += it }) { if (++calls < 3) throw IOException("HTTP 503") }
        assertTrue(ok)
        assertEquals(3, calls)
        assertEquals(listOf(1_000L, 2_000L), sleeps)
    }

    @Test fun `gives up after the limit without a trailing sleep`() = runBlocking {
        val sleeps = mutableListOf<Long>()
        var calls = 0
        val ok = retrying(3, sleep = { sleeps += it }) { calls++; throw IOException("offline") }
        assertFalse(ok)
        assertEquals(3, calls)
        assertEquals(listOf(1_000L, 2_000L), sleeps)
    }

    @Test fun `a hanging attempt times out and the next step still runs`() = runBlocking {
        var calls = 0
        val failures = mutableListOf<String>()
        val wrote = retrying(3, attemptTimeoutMs = 50, sleep = {}, onFailure = { _, e -> failures += e.message.orEmpty() }) {
            calls++; awaitCancellation()   // 요청을 받고 응답하지 않는 서버
        }
        assertFalse(wrote)
        assertEquals(3, calls)
        assertTrue(failures.all { "timed out" in it })
        // 최종 쓰기를 포기한 뒤 sessionEnd 단계로 넘어간다
        assertTrue(retrying(1, sleep = {}) { })
    }

    @Test fun `outer cancellation is not swallowed`() {
        assertFailsWith<kotlinx.coroutines.TimeoutCancellationException> {
            runBlocking { withTimeout(100) { retrying(100, attemptTimeoutMs = 10_000, sleep = { delay(it) }) { awaitCancellation() } } }
        }
    }
}

