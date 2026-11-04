package ai.allo.car.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import java.io.IOException

/**
 * [block] 을 성공할 때까지 최대 [attempts] 번 시도한다. 시도 사이에 [backoffMs] (1s, 2s, 4s …) 쉰다.
 * 한 번의 시도가 [attemptTimeoutMs] 를 넘으면 그 시도를 실패로 보고 다음으로 간다 (응답이 멈춘 요청, PR #27 리뷰).
 * 시간 초과는 withTimeoutOrNull 로 처리하므로 바깥 취소와 섞이지 않는다. 바깥 취소는 그대로 전파한다.
 * 순수 Kotlin, 단위 테스트 대상 ([sleep] 주입).
 * @return 성공하면 true
 */
suspend fun retrying(
    attempts: Int,
    attemptTimeoutMs: Long = 15_000,
    backoffMs: (attempt: Int) -> Long = { 1_000L shl it },
    sleep: suspend (Long) -> Unit = { delay(it) },
    onFailure: (attempt: Int, Throwable) -> Unit = { _, _ -> },
    block: suspend () -> Unit,
): Boolean {
    for (i in 0 until attempts) {
        try {
            withTimeoutOrNull(attemptTimeoutMs) { block() } ?: throw IOException("attempt timed out after ${attemptTimeoutMs}ms")
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
