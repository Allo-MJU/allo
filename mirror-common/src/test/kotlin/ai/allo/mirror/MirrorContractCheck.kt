package ai.allo.mirror

/** No Android runtime needed. Run using scripts/check_mirror_kotlin.py. */
fun main() {
    val token = "a".repeat(43)
    val pin = "ab".repeat(32)
    val config = MirrorConfig.parse("""{"token":"$token","url":"https://127.0.0.1:8443","certificateSha256":"$pin"}""")
    check(config.url == "https://127.0.0.1:8443")
    check(!config.toString().contains(token))
    fun rejects(json: String) { check(runCatching { MirrorConfig.parse(json) }.isFailure) }
    for (url in listOf("http://localhost", "https://u:p@localhost", "https://localhost/path", "https://localhost?token=x", "https://localhost/#x", "https://localhost:0", "https://localhost:99999")) {
        rejects("""{"url":"$url","token":"$token","certificateSha256":"$pin"}""")
    }
    rejects("""{"url":"https://localhost","token":"short","certificateSha256":"$pin"}""")
    rejects("""{"url":"https://localhost","token":"$token","certificateSha256":"invalid"}""")
    rejects("""{"url":"https://localhost","url":"https://other","token":"$token","certificateSha256":"$pin"}""")
    rejects("""{"url":"https://localhost","token":"$token","certificateSha256":"$pin","extra":"x"}""")
    rejects("""{"url":"https://localhost" "token":"$token","certificateSha256":"$pin"}""")
    rejects("""{"url":"https://localhost","token":"$token","certificateSha256":"$pin",}""")
    check(MirrorTransport.validJpeg(byteArrayOf(0xff.toByte(), 0xd8.toByte(), 1, 0xff.toByte(), 0xd9.toByte())))
    check(!MirrorTransport.validJpeg(byteArrayOf(1, 2, 3)))
    println("Mirror contract checks passed")
}
