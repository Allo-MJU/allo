package ai.allo.car.sync

import kotlinx.coroutines.runBlocking
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
}
