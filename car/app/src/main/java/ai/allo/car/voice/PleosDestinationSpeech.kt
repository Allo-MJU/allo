package ai.allo.car.voice

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import ai.pleos.playground.stt.SpeechToText
import ai.pleos.playground.stt.constant.Mode
import ai.pleos.playground.stt.constant.ErrorType
import ai.pleos.playground.stt.listener.OnInitializeListener
import ai.pleos.playground.stt.listener.ResultListener
import java.util.Locale

/** SDK event adapter with no Android dependency; callbacks run through the owner's closed gate. */
internal class DestinationResultListener(
    private val dispatch: (() -> Unit) -> Unit,
    private val ready: () -> Unit,
    private val finalResult: (String) -> Unit,
    private val failure: (String) -> Unit,
) : ResultListener {
    override fun onReady() = dispatch(ready)
    override fun onStartedRecognition() = dispatch(ready)
    override fun onUpdated(stt: String, completed: Boolean) {
        if (completed) dispatch { finalResult(stt) }
    }
    override fun onUpdatedEpdData(on: Long, off: Long) = Unit
    override fun onUpdatedRms(rms: Double) = Unit
    // SDK 3.3.1 emits this for EPD_OFF; UpdateSttCompleted may arrive afterwards.
    // Keep the listener until the final text, an explicit error, cancellation, or controller timeout.
    override fun onEndedRecognition() = Unit
    override fun onError(error: ErrorType) = dispatch { failure("음성 인식을 사용할 수 없어요. ($error)") }
}

/** One bounded, on-device utterance. Never records or forwards microphone bytes. */
internal class PleosDestinationRecognition(context: Context) : DestinationRecognition {
    private val main = Handler(Looper.getMainLooper())
    private val sdk = SpeechToText(context.applicationContext, Mode.ON_DEVICE)
    private var closed = false
    private var initialized = false
    private var listener: ResultListener? = null

    override fun start(onReady: () -> Unit, onFinal: (String) -> Unit, onFailure: (String) -> Unit) {
        fun dispatch(action: () -> Unit) { main.post { if (!closed) action() } }
        val next = DestinationResultListener(::dispatch, onReady, onFinal, onFailure)
        listener = next
        try {
            sdk.initialize(object : OnInitializeListener {
                override fun onSuccess() {
                    main.post {
                        initialized = true
                        if (closed) { cleanup(); return@post }
                        try {
                            sdk.addListener(next)
                            sdk.setLocale(Locale.KOREA)
                            Log.d("DestinationSpeech", "request on-device recognition")
                            sdk.request()
                        } catch (_: Exception) { onFailure("음성 인식을 시작하지 못했어요.") }
                    }
                }
                override fun onFailure(error: ErrorType) = dispatch {
                    onFailure("음성 인식을 준비하지 못했어요. ($error)")
                }
            })
        } catch (_: Exception) { onFailure("음성 인식을 준비하지 못했어요.") }
    }

    override fun close() {
        closed = true
        cleanup()
    }
    private fun cleanup() {
        if (initialized) {
            runCatching { sdk.stop() }
            listener?.let { runCatching { sdk.removeListener(it) } }
        }
        runCatching { sdk.release() }
    }
}

/** On-device fallback for vehicle character speech; completion follows actual SDK playback. */
internal class PleosDestinationPrompt(context: Context) : DestinationPrompt {
    private val main = Handler(Looper.getMainLooper())
    private val sdk = ai.pleos.playground.tts.TextToSpeech(context.applicationContext,
        ai.pleos.playground.tts.constant.Mode.ON_DEVICE)
    private var closed = false
    private var initialized = false
    private var listener: ai.pleos.playground.tts.listener.EventListener? = null

    override fun speak(text: String, onDone: () -> Unit, onFailure: () -> Unit) {
        fun dispatch(action: () -> Unit) { main.post { if (!closed) action() } }
        val completedCallback = onDone
        val failedCallback = onFailure
        val next = object : ai.pleos.playground.tts.listener.EventListener {
            override fun onStart() = Unit
            override fun onReady() = Unit
            override fun onDone() = dispatch(completedCallback)
            override fun onStop() = dispatch(failedCallback)
            override fun onError(error: ai.pleos.playground.tts.constant.ErrorType) = dispatch(failedCallback)
            override fun onUpdatedRms(rms: Double) = Unit
        }
        listener = next
        try {
            sdk.initialize(object : ai.pleos.playground.tts.listener.OnInitializeListener {
                override fun onSuccess() {
                    main.post {
                        initialized = true
                        if (closed) { cleanup(); return@post }
                        try { sdk.addEventListener(next); sdk.speak(text, true) }
                        catch (_: Exception) { onFailure() }
                    }
                }
                override fun onFailure(error: ai.pleos.playground.tts.constant.ErrorType) = dispatch(failedCallback)
            })
        } catch (_: Exception) { onFailure() }
    }
    override fun close() { closed = true; cleanup() }
    private fun cleanup() {
        if (initialized) {
            listener?.let { runCatching { sdk.removeEventListener(it) } }
            runCatching { sdk.stop() }
        }
        runCatching { sdk.release() }
    }
}
