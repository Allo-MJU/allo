package ai.allo.car.voice

import android.content.Context
import java.io.File
import kotlinx.coroutines.*

/** A fixed speaker owns each engine. Cancellation also invalidates late player callbacks. */
internal class CharacterSpeechEngine(
    private val scope: CoroutineScope,
    private val resolve: suspend (String) -> File,
    private val createPlayer: (File) -> PlazaClipPlayer,
    private val createFallback: (() -> DestinationPrompt)? = null,
) : DialogueSpeechEngine {
    private var event: (DialogueSpeechEvent) -> Unit = {}
    private var job: Job? = null
    private var player: PlazaClipPlayer? = null
    private var fallback: DestinationPrompt? = null
    private var deadline: Job? = null
    private var generation = 0L
    private var released = false
    override fun initialize(result: (String?) -> Unit) = result(null)
    override fun listen(event: (DialogueSpeechEvent) -> Unit) { this.event = event }
    override fun speak(text: String) {
        check(!released)
        clear()
        val token = generation
        deadline = scope.launch { delay(6_000); fail(token, text) }
        job = scope.launch {
            try {
                val file = resolve(text)
                ensureActive()
                if (!active(token)) return@launch
                val next = createPlayer(file)
                player = next
                next.prepare("",
                    ready = {
                        if (active(token) && player === next) {
                            deadline?.cancel(); deadline = null
                            runCatching { next.play() }.onFailure { fail(token, text) }
                        }
                    },
                    done = {
                        if (active(token) && player === next) {
                            clear(); event(DialogueSpeechEvent.Done)
                        }
                    },
                    failed = { fail(token, text) })
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { fail(token, text) }
        }
    }
    private fun active(token: Long) = !released && generation == token
    private fun fail(token: Long, text: String) {
        if (!active(token)) return
        clear() // Invalidate Qwen callbacks before releasing it or starting Pleos.
        val fallbackToken = generation
        fun finish(result: DialogueSpeechEvent) {
            if (active(fallbackToken)) { clear(); event(result) }
        }
        val failure = DialogueSpeechEvent.Failed("음성을 재생하지 못했어요.")
        if (createFallback == null) { finish(failure); return }
        try {
            val next = createFallback.invoke()
            fallback = next
            deadline = scope.launch { delay(12_000); finish(failure) }
            next.speak(text,
                onDone = { finish(DialogueSpeechEvent.Done) },
                onFailure = { finish(failure) })
        } catch (_: Exception) { finish(failure) }
    }
    private fun clear() {
        generation++
        val oldJob = job
        val oldPlayer = player
        val oldFallback = fallback
        deadline?.cancel(); deadline = null
        job = null; player = null; fallback = null
        oldJob?.cancel()
        runCatching { oldPlayer?.release() }
        runCatching { oldFallback?.close() }
    }
    override fun stop() {
        clear()
        if (!released) event(DialogueSpeechEvent.Stopped)
    }
    override fun release() {
        released = true
        clear()
        scope.cancel()
        event = {}
    }
}

private fun characterEngine(context: Context, species: String, purpose: String): DialogueSpeechEngine {
    val app = context.applicationContext
    val config = PlazaCloudVoice.config
    val cache = config?.let { PlazaCloudCache(File(app.cacheDir, "character-$purpose-voice"), it) }
    return CharacterSpeechEngine(CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
        resolve = { text ->
            requireNotNull(cache) { "Character speech is not configured" }
                .resolveCharacter(species, text, purpose)
        }, createPlayer = { AndroidPlazaClipPlayer(app, it) },
        createFallback = { PleosDestinationPrompt(app) })
}

internal fun characterDialogueVoice(context: Context, species: String): DialogueVoice =
    DialogueVoice { characterEngine(context, species, "dialogue") }

internal fun characterDestinationPrompt(context: Context, species: String): DestinationPrompt =
    CharacterDestinationPrompt { characterEngine(context, species, "destination") }

/** STT resumes only on actual playback completion, never when the download finishes. */
internal class CharacterDestinationPrompt(private val create: () -> DialogueSpeechEngine) : DestinationPrompt {
    private var engine: DialogueSpeechEngine? = null
    private var closed = false
    override fun speak(text: String, onDone: () -> Unit, onFailure: () -> Unit) {
        if (closed) return
        val current = create()
        engine = current
        current.initialize { error ->
            if (!closed) {
                if (error != null) onFailure()
                else {
                    current.listen { event ->
                        if (!closed) when (event) {
                            DialogueSpeechEvent.Done -> onDone()
                            DialogueSpeechEvent.Stopped, is DialogueSpeechEvent.Failed -> onFailure()
                        }
                    }
                    current.speak(text)
                }
            }
        }
    }
    override fun close() {
        closed = true
        engine?.release()
        engine = null
    }
}
