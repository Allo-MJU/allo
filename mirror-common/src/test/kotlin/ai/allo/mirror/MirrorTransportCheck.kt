package ai.allo.mirror

import java.io.File

/** JVM exercises the same TLS transport compiled into both Android debug apps. */
fun main(args: Array<String>) {
    val transport = MirrorTransport(MirrorConfig.parse(File(args[0]).readText()))
    if (args[1] == "reject") {
        check(runCatching { transport.fetch() }.isFailure) { "Unsafe endpoint accepted" }
        println("Rejected invalid endpoint identity or authorization")
        return
    }
    check(transport.fetch() == null)
    val jpeg = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 4, 5, 6, 0xff.toByte(), 0xd9.toByte())
    check(transport.upload(jpeg))
    val frame = checkNotNull(transport.fetch())
    check(frame.bytes.contentEquals(jpeg))
    check(frame.sequence == 1L && frame.ageMs in 0..1500)
    transport.clear()
    check(transport.fetch() == null)
    println("Kotlin HTTPS upload/fetch/clear passed")
}
