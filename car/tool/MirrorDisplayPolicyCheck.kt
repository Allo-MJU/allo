package ai.allo.car.mirror

/** Runs on a JVM without Android or an emulator. */
fun main() {
    val policy = MirrorDisplayPolicy()
    check(!policy.allowed(0)) { "Unknown startup state must be blocked" }
    policy.update(true, true, true, true, 100)
    check(policy.allowed(100))
    check(!policy.allowed(1100)) { "Expired vehicle verification must block" }
    policy.update(true, true, true, true, 200)
    val beforeDrive = policy.generation
    policy.update(true, true, false, true, 201)
    check(!policy.allowed(201)) { "D at zero speed must not display" }
    policy.update(true, true, true, true, 202)
    check(!policy.accepts(beforeDrive, 0, 200, 202)) { "Late pre-drive frame after repark" }
    val current = policy.generation
    check(policy.accepts(current, 100, 202, 300))
    check(!policy.accepts(current, 1400, 202, 302)) { "Include transfer time in frame age" }
    check(!policy.accepts(current, -1, 202, 300))
    check(!policy.accepts(current, 0, 301, 300))
    for ((connected, foreground, parked, ux) in listOf(
        listOf(false, true, true, true), listOf(true, false, true, true),
        listOf(true, true, null, true), listOf(true, true, true, null),
        listOf(true, true, true, false),
    )) {
        policy.update(connected == true, foreground == true, parked, ux, 400)
        check(!policy.allowed(400)) { "Disconnect, pause, unknown or UX restriction must block" }
    }
    policy.update(true, true, true, true, 500)
    val oldConnection = policy.generation
    policy.invalidate()
    check(!policy.accepts(oldConnection, 0, 500, 501)) { "Old configuration response must be rejected" }
    check(MirrorDisplayPolicy.remainingMs(200, 100, 300) == 1100L)
    // A returned age of 900ms already includes transfer; only 50ms decoding elapsed since receipt.
    check(MirrorDisplayPolicy.remainingMs(900, 1000, 1050) == 550L)
    check(MirrorDisplayPolicy.remainingMs(Long.MAX_VALUE, 0, 100) == 0L)
    println("MirrorDisplayPolicy checks passed: startup, P/D, UX, lifecycle, freshness, late response, overflow")
}
