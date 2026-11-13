package ai.allo.car.voice

import android.content.Context
import ai.pleos.playground.tts.TextToSpeech
import ai.pleos.playground.tts.constant.Mode
import ai.pleos.playground.tts.constant.ErrorType
import ai.pleos.playground.tts.listener.EventListener
import ai.pleos.playground.tts.listener.OnInitializeListener
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class DialogueVoiceState(
    val ready: Boolean = false,
    val speaking: Boolean = false,
    val error: String? = null,
)

/** Tap-only Pleos speech. Never remembers text requested before initialization. */
class DialogueVoice internal constructor(private val createEngine: () -> DialogueSpeechEngine) {
    constructor(context: Context) : this({ PleosDialogueSpeechEngine(context.applicationContext) })

    private val lock = Any()
    private val mutableState = MutableStateFlow(DialogueVoiceState())
    val state: StateFlow<DialogueVoiceState> = mutableState.asStateFlow()
    private var engine: DialogueSpeechEngine? = null
    private var started = false
    private var released = false
    private var awaitingStop = false
    private var replacement: String? = null

    fun start() = synchronized(lock) {
        if (started || released) return@synchronized
        started = true
        runCatching {
            val current = createEngine()
            engine = current
            current.initialize { error -> synchronized(lock) {
                if (released) {
                    // A bind can finish after release; clean up that late service too.
                    runCatching { current.release() }
                } else if (error != null) {
                    mutableState.value = DialogueVoiceState(error = error)
                } else {
                    runCatching {
                        current.listen { event -> synchronized(lock) {
                            if (!released) {
                                when (event) {
                                    DialogueSpeechEvent.Done -> if (!awaitingStop) {
                                        mutableState.value = mutableState.value.copy(speaking = false)
                                    }
                                    DialogueSpeechEvent.Stopped -> {
                                        awaitingStop = false
                                        val next = replacement
                                        replacement = null
                                        mutableState.value = mutableState.value.copy(speaking = false)
                                        if (next != null) submit(next)
                                    }
                                    is DialogueSpeechEvent.Failed -> {
                                        awaitingStop = false
                                        replacement = null
                                        mutableState.value = mutableState.value.copy(speaking = false, error = event.message)
                                    }
                                }
                            }
                        } }
                        mutableState.value = DialogueVoiceState(ready = true)
                    }.onFailure { fail("음성을 준비하지 못했어요.") }
                }
            } }
        }.onFailure { fail("음성을 준비하지 못했어요.") }
    }

    /** Accept a tap to speak (or wait for a prior stop); another tap cancels playback. */
    fun speak(text: String): Boolean = synchronized(lock) {
        if (released || !state.value.ready || text.isBlank()) return false
        if (state.value.speaking) {
            stop()
            return false
        }
        if (awaitingStop) {
            replacement = text
            mutableState.value = state.value.copy(speaking = true, error = null)
            return true
        }
        submit(text)
    }

    /** A new character tap replaces speech only after the engine acknowledges stopping it. */
    fun replace(text: String): Boolean = synchronized(lock) {
        if (released || !state.value.ready || text.isBlank()) return false
        if (awaitingStop) {
            replacement = text // Rapid character taps keep only the newest line.
            mutableState.value = state.value.copy(speaking = true, error = null)
            return true
        }
        if (!state.value.speaking) return submit(text)
        replacement = text
        requestStop()
    }

    private fun submit(text: String): Boolean {
        mutableState.value = state.value.copy(speaking = true, error = null)
        return runCatching { engine!!.speak(text) }
            .onFailure { mutableState.value = state.value.copy(speaking = false, error = "음성을 재생하지 못했어요.") }
            .isSuccess
    }

    private fun requestStop(): Boolean {
        awaitingStop = true // Set before calling the engine: callbacks may be synchronous.
        return runCatching { engine?.stop() }
            .onFailure {
                awaitingStop = false
                replacement = null
                mutableState.value = state.value.copy(speaking = false, error = "음성을 중지하지 못했어요.")
            }.isSuccess
    }

    fun stop() = synchronized(lock) {
        replacement = null
        if (released || !state.value.ready) return@synchronized
        val wasSpeaking = state.value.speaking
        mutableState.value = state.value.copy(speaking = false)
        if (!awaitingStop && wasSpeaking) requestStop()
    }

    fun release() = synchronized(lock) {
        if (released) return@synchronized
        released = true
        replacement = null
        awaitingStop = false
        mutableState.value = DialogueVoiceState()
        runCatching { engine?.stop() }
        runCatching { engine?.release() }
    }

    private fun fail(message: String) {
        mutableState.value = DialogueVoiceState(error = message)
    }
}

internal sealed interface DialogueSpeechEvent {
    data object Done : DialogueSpeechEvent
    data object Stopped : DialogueSpeechEvent
    data class Failed(val message: String) : DialogueSpeechEvent
}

internal interface DialogueSpeechEngine {
    fun initialize(result: (String?) -> Unit)
    fun listen(event: (DialogueSpeechEvent) -> Unit)
    fun speak(text: String)
    fun stop()
    fun release()
}

private class PleosDialogueSpeechEngine(context: Context) : DialogueSpeechEngine {
    private val tts = TextToSpeech(context, Mode.ON_DEVICE)
    private var listener: EventListener? = null
    override fun initialize(result: (String?) -> Unit) {
        tts.initialize(object : OnInitializeListener {
            override fun onSuccess() = result(null)
            override fun onFailure(error: ErrorType) = result("음성을 준비하지 못했어요. ($error)")
        })
    }
    override fun listen(event: (DialogueSpeechEvent) -> Unit) {
        val next = object : EventListener {
            override fun onStart() { android.util.Log.d("DialogueVoice", "speech started") }
            override fun onReady() {}
            override fun onDone() {
                android.util.Log.d("DialogueVoice", "speech completed")
                event(DialogueSpeechEvent.Done)
            }
            override fun onStop() = event(DialogueSpeechEvent.Stopped)
            override fun onError(error: ErrorType) = event(DialogueSpeechEvent.Failed("음성을 재생하지 못했어요. ($error)"))
            override fun onUpdatedRms(rms: Double) {}
        }
        tts.addEventListener(next) // SDK service exists only after initialize succeeds.
        listener = next
    }
    override fun speak(text: String) = tts.speak(text, true)
    override fun stop() = tts.stop()
    override fun release() {
        listener?.let { runCatching { tts.removeEventListener(it) } }
        listener = null
        tts.release()
    }
}
