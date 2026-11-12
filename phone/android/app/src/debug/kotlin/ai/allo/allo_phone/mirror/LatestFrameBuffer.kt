package ai.allo.allo_phone.mirror

/** One latest pending frame plus at most one upload. Caller treats byte arrays as immutable. */
class LatestFrameBuffer {
    private var latest: ByteArray? = null
    private var uploading = false
    private var nextUploadAt = 0L
    private var stopped = false

    @Synchronized fun offer(frame: ByteArray) {
        require(frame.size in 1..512 * 1024)
        if (!stopped) latest = frame
    }
    @Synchronized fun beginUpload(nowMs: Long): ByteArray? {
        if (stopped || uploading || nowMs < nextUploadAt) return null
        val frame = latest ?: return null
        uploading = true
        nextUploadAt = nowMs + 200
        return frame
    }
    @Synchronized fun finishUpload() { uploading = false }
    @Synchronized fun clear() { latest = null }
    @Synchronized fun stop() { stopped = true; latest = null }
}
