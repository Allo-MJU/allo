package ai.allo.allo_phone.mirror

/** Standalone JVM check: compile together with LatestFrameBuffer.kt and run this main. */
fun main() {
    val buffer = LatestFrameBuffer()
    val initial = byteArrayOf(1)
    val final = byteArrayOf(2)
    buffer.offer(initial)
    check(buffer.beginUpload(0)!!.contentEquals(initial))
    buffer.offer(final) // Last visual update arrives while an upload is still busy.
    check(buffer.beginUpload(200) == null)
    buffer.finishUpload()
    check(buffer.beginUpload(200)!!.contentEquals(final)) // No further capture is needed.
    buffer.finishUpload()
    check(buffer.beginUpload(399) == null)
    check(buffer.beginUpload(400)!!.contentEquals(final)) // Static screen heartbeat.
    buffer.finishUpload()
    buffer.clear()
    check(buffer.beginUpload(1000) == null) // Rotation cannot repeat the old aspect/frame.
    buffer.offer(initial)
    check(buffer.beginUpload(1000) != null)
    buffer.stop()
    buffer.finishUpload()
    buffer.offer(final)
    check(buffer.beginUpload(1200) == null) // Late callbacks cannot revive capture.
    println("Latest frame mailbox: in-flight update, heartbeat, clear and stop passed")
}
