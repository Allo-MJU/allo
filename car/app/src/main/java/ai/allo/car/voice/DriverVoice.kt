package ai.allo.car.voice

import android.content.Context
import android.util.Log
import ai.pleos.playground.tts.TextToSpeech
import ai.pleos.playground.tts.constant.ErrorType
import ai.pleos.playground.tts.constant.Mode
import ai.pleos.playground.tts.listener.EventListener
import ai.pleos.playground.tts.listener.OnInitializeListener

/**
 * 운전자에게 음성으로만 말한다 (차 화면에 게임을 띄우지 않는 규제 대응).
 * Pleos TTS SDK 온디바이스 모드. Android 기본 TTS 엔진은 Pleos Connect 에 없다 (architecture.md).
 * 초기화 전에 들어온 문장은 하나만 기억했다가 초기화가 끝나면 말한다.
 */
class DriverVoice(context: Context) {
    private val tts = TextToSpeech(context.applicationContext, Mode.ON_DEVICE)

    @Volatile private var ready = false
    @Volatile private var pending: String? = null

    private val events = object : EventListener {
        override fun onStart() { Log.i(TAG, "tts start") }
        override fun onReady() {}
        override fun onDone() { Log.i(TAG, "tts done") }
        override fun onError(error: ErrorType) { Log.w(TAG, "tts error $error") }
        override fun onStop() {}
        override fun onUpdatedRms(rms: Double) {}
    }

    fun start() {
        runCatching {
            // addEventListener 는 initialize 성공 뒤에. 먼저 부르면 SDK 내부 lateinit 예외
            tts.initialize(object : OnInitializeListener {
                override fun onSuccess() {
                    Log.i(TAG, "tts initialized")
                    runCatching { tts.addEventListener(events) }
                    ready = true
                    pending?.let { pending = null; speak(it) }
                }
                override fun onFailure(error: ErrorType) { Log.w(TAG, "tts init failed $error") }
            })
        }.onFailure { Log.e(TAG, "tts start failed", it) }
    }

    /** 앞 문장을 끊고 새 문장을 말한다. 운전자에게 쌓인 말을 늘어놓지 않기 위해. */
    fun speak(text: String) {
        if (!ready) { pending = text; return }
        runCatching { tts.speak(text, true) }.onFailure { Log.w(TAG, "speak failed", it) }
    }

    /**
     * 지금 바로 말할 수 있으면 말하고 true. 준비 전이면 기억하지 않고 false.
     * Gleo 응답을 silent 로 바꿀지 정할 때 쓴다: false 면 Gleo 가 대신 말해야 한다.
     * (엔진에 넘긴 뒤 비동기로 나는 오류는 여기서 알 수 없다)
     */
    fun speakNow(text: String): Boolean {
        if (!ready) return false
        return runCatching { tts.speak(text, true) }.onFailure { Log.w(TAG, "speak failed", it) }.isSuccess
    }

    fun release() {
        runCatching { tts.removeEventListener(events); tts.release() }
        ready = false
    }

    private companion object { const val TAG = "DriverVoice" }
}
