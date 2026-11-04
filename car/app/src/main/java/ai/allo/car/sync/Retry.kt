package ai.allo.car.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

/**
 * [block] 을 성공할 때까지 최대 [attempts] 번 시도한다. 시도 사이에 [backoffMs] (1s, 2s, 4s …) 쉰다.
 * 취소는 그대로 전파한다. 순수 Kotlin, 단위 테스트 대상 ([sleep] 주입).
 * @return 성공하면 true
 */
suspend fun retrying(
    attempts: Int,
    backoffMs: (attempt: Int) -> Long = { 1_000L shl it },
    sleep: suspend (Long) -> Unit = { delay(it) },
    onFailure: (attempt: Int, Throwable) -> Unit = { _, _ -> },
    block: suspend () -> Unit,
): Boolean {
    for (i in 0 until attempts) {
        try {
            block()
            return true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            onFailure(i, e)
            if (i < attempts - 1) sleep(backoffMs(i))
        }
    }
    return false
}
