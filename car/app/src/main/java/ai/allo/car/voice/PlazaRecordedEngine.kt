package ai.allo.car.voice

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import java.io.File
import kotlinx.coroutines.*

internal interface PlazaClipPlayer {
    fun prepare(asset: String, ready: () -> Unit, done: () -> Unit, failed: () -> Unit)
    fun play()
    fun release()
}

internal class PlazaRecordedEngine(private val createPlayer: () -> PlazaClipPlayer) : DialogueSpeechEngine {
    private var player: PlazaClipPlayer? = null
    private var event: (DialogueSpeechEvent) -> Unit = {}
    override fun initialize(result: (String?) -> Unit) = result(null)
    override fun listen(event: (DialogueSpeechEvent) -> Unit) { this.event = event }
    override fun speak(text: String) {
        val entry = requireNotNull(PlazaRecordings.find(text)) { "No matching plaza recording" }
        clear()
        val current = createPlayer()
        player = current
        try {
            current.prepare(entry.asset,
                ready = {
                    if (player === current) {
                        runCatching { current.play() }.onFailure { fail(current) }
                    }
                },
                done = { if (player === current) { clear(); event(DialogueSpeechEvent.Done) } },
                failed = { fail(current) })
        } catch (error: Exception) {
            clear()
            throw error
        }
    }
    private fun fail(current: PlazaClipPlayer) {
        if (player !== current) return
        clear()
        event(DialogueSpeechEvent.Failed("음성을 재생하지 못했어요."))
    }
    private fun clear() {
        val old = player
        player = null // Ignore late prepare/completion callbacks before releasing.
        runCatching { old?.release() }
    }
    override fun stop() { clear(); event(DialogueSpeechEvent.Stopped) }
    override fun release() { clear(); event = {} }
}

internal fun plazaRecordedVoice(context: Context): DialogueVoice {
    val app = context.applicationContext
    return DialogueVoice { PlazaRecordedEngine {
        val config = PlazaCloudVoice.config
        if (config == null) AndroidPlazaClipPlayer(app)
        else CloudPlazaClipPlayer(app, PlazaCloudCache(File(app.cacheDir, "plaza-voice"), config))
    } }
}

private class AndroidPlazaClipPlayer(private val context: Context, private val file: File? = null) : PlazaClipPlayer {
    private val media = MediaPlayer()
    override fun prepare(asset: String, ready: () -> Unit, done: () -> Unit, failed: () -> Unit) {
        media.setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
        media.setOnPreparedListener { ready() }
        media.setOnCompletionListener { done() }
        media.setOnErrorListener { _, _, _ -> failed(); true }
        if (file != null) media.setDataSource(file.absolutePath)
        else context.assets.openFd(asset).use { media.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
        media.prepareAsync()
    }
    override fun play() = media.start()
    override fun release() = media.release()
}

/** Lifecycle-owned download: cancellation cannot trigger either remote playback or local fallback. */
private class CloudPlazaClipPlayer(private val context: Context, private val cache: PlazaCloudCache) : PlazaClipPlayer {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var released = false
    private var delegate: PlazaClipPlayer? = null
    override fun prepare(asset: String, ready: () -> Unit, done: () -> Unit, failed: () -> Unit) {
        val entry = PlazaRecordings.entries.firstOrNull { it.asset == asset }
        scope.launch {
            val file = try { if (entry == null) null else cache.resolve(entry) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { null }
            if (released) return@launch
            try {
                delegate = AndroidPlazaClipPlayer(context, file)
                delegate?.prepare(asset, ready, done, failed)
            } catch (_: Exception) { if (!released) failed() }
        }
    }
    override fun play() { if (!released) delegate?.play() }
    override fun release() {
        released = true
        scope.cancel()
        delegate?.release()
        delegate = null
    }
}
