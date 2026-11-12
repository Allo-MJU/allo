package ai.allo.car.sync

import kotlin.test.*

class GameFreshnessTest {
    @Test fun `initial old missing future and out of order snapshots are not live`() {
        val state = GameFreshness()
        assertFalse(state.isFresh(0))
        assertFalse(state.observe(0, 100_000, 0))
        assertFalse(state.observe(80_000, 100_000, 0))
        assertFalse(state.observe(106_000, 100_000, 0))
        assertTrue(state.observe(100_000, 100_000, 100))
        assertFalse(state.observe(99_999, 100_000, 101))
    }

    @Test fun `duplicate timestamp does not renew heartbeat or revive a dropped stream`() {
        val state = GameFreshness()
        assertTrue(state.observe(100_000, 100_000, 0))
        assertTrue(state.observe(100_000, 105_000, 5_000))
        assertFalse(state.isFresh(15_000))
        assertTrue(state.observe(115_001, 115_001, 15_001))
        state.disconnect()
        assertFalse(state.isFresh(15_002))
        assertFalse(state.observe(115_001, 115_002, 15_002))
        assertTrue(state.observe(115_003, 115_003, 15_003))
    }

    @Test fun `freshness uses monotonic elapsed time and rejects clock reversal`() {
        val state = GameFreshness()
        assertTrue(state.observe(100_000, 100_000, 10_000))
        assertTrue(state.isFresh(24_999))
        assertFalse(state.isFresh(25_000))
        assertFalse(state.isFresh(9_999))
    }
}
