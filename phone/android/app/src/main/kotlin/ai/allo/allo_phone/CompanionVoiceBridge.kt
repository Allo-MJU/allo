package ai.allo.allo_phone

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

object CompanionVoiceBridge {
    private const val MAX_TEXT_LENGTH = 1000
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var application: Application? = null
    private var tts: TextToSpeech? = null
    private var ready = false
    private var generation = 0
    private var attachmentGeneration = 0
    private var pendingText: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var startedActivities = 0
    private var foreground = true

    private val callbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityStarted(activity: Activity) {
            startedActivities++
            foreground = true
        }
        override fun onActivityStopped(activity: Activity) {
            startedActivities = (startedActivities - 1).coerceAtLeast(0)
            val stoppedGeneration = attachmentGeneration
            main.post {
                if (stoppedGeneration == attachmentGeneration && startedActivities == 0 && application != null) {
                    foreground = false
                    stop()
                }
            }
        }
        override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
        override fun onActivityResumed(activity: Activity) = Unit
        override fun onActivityPaused(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) = Unit
    }

    fun attach(engine: FlutterEngine, activity: Activity) {
        detach()
        foreground = true
        application = activity.application.also { it.registerActivityLifecycleCallbacks(callbacks) }
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "allo/companion-voice").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val text = ((call.arguments as? Map<*, *>)?.get("text") as? String)?.trim()
                        if (text.isNullOrEmpty() || text.length > MAX_TEXT_LENGTH || text.length > TextToSpeech.getMaxSpeechInputLength()) {
                            result.error("invalid_text", "Text must be between 1 and 1000 characters.", null)
                        } else if (!foreground) {
                            result.error("unavailable", "The application is in the background.", null)
                        } else {
                            speak(text, result)
                        }
                    }
                    "stop" -> {
                        stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun speak(text: String, result: MethodChannel.Result) {
        stop()
        if (ready) {
            enqueue(text, result)
            return
        }
        pendingText = text
        pendingResult = result
        if (tts != null) return
        val initGeneration = ++generation
        try {
            tts = TextToSpeech(application) { status ->
                main.post { onInitialized(initGeneration, status) }
            }
            main.postDelayed({
                if (initGeneration == generation && !ready) failInitialization()
            }, 10000)
        } catch (_: Exception) {
            failInitialization()
        }
    }

    private fun onInitialized(initGeneration: Int, status: Int) {
        if (initGeneration != generation || application == null) return
        if (status != TextToSpeech.SUCCESS || tts == null) {
            failInitialization()
            return
        }
        ready = true
        val text = pendingText
        val result = pendingResult
        pendingText = null
        pendingResult = null
        if (text != null && result != null) enqueue(text, result)
    }

    private fun enqueue(text: String, result: MethodChannel.Result) {
        val engine = tts
        if (engine == null) {
            result.error("unavailable", "Text-to-speech is unavailable.", null)
            return
        }
        val locale = if (text.any { it in '\uac00'..'\ud7a3' || it in '\u3131'..'\u318e' }) Locale.KOREAN
            else if (text.any { it in 'a'..'z' || it in 'A'..'Z' }) Locale.ENGLISH
            else Locale.KOREAN
        try {
            val language = engine.setLanguage(locale)
            if (language == TextToSpeech.LANG_MISSING_DATA || language == TextToSpeech.LANG_NOT_SUPPORTED ||
                engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "companion") != TextToSpeech.SUCCESS) {
                result.error("unavailable", "The requested voice is unavailable.", null)
            } else {
                result.success(null)
            }
        } catch (_: Exception) {
            result.error("unavailable", "Text-to-speech is unavailable.", null)
        }
    }

    private fun stop() {
        pendingResult?.error("interrupted", "Voice playback was interrupted.", null)
        pendingText = null
        pendingResult = null
        runCatching { tts?.stop() }
    }

    private fun failInitialization() {
        pendingResult?.error("unavailable", "Text-to-speech could not be initialized.", null)
        pendingResult = null
        pendingText = null
        runCatching { tts?.shutdown() }
        tts = null
        ready = false
        generation++
    }

    fun detach() {
        attachmentGeneration++
        stop()
        generation++
        runCatching { tts?.shutdown() }
        tts = null
        ready = false
        application?.unregisterActivityLifecycleCallbacks(callbacks)
        application = null
        startedActivities = 0
        foreground = false
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
