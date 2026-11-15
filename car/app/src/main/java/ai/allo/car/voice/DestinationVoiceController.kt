package ai.allo.car.voice

/** Commands are local intents, never recognition transcripts sent to another service. */
enum class DestinationVoiceCommand { SUGGEST, ACCEPT, NEXT }

data class DestinationVoiceReply(val message: String, val listenAgain: Boolean = false)
data class DestinationVoiceState(
    val busy: Boolean = false,
    val listening: Boolean = false,
    val message: String = "",
)

interface DestinationRecognition {
    fun start(onReady: () -> Unit, onFinal: (String) -> Unit, onFailure: (String) -> Unit)
    fun close()
}

interface DestinationPrompt {
    fun speak(text: String, onDone: () -> Unit, onFailure: () -> Unit)
    fun close()
}

/**
 * One bounded recognition turn at a time. Call this controller and its callbacks on the main thread.
 * A fresh generation owns every resource and callback; closing a resource may itself deliver callbacks.
 * The caller must revalidate the pending destination and navigation state in [execute].
 */
class DestinationVoiceController(
    private val createRecognition: () -> DestinationRecognition,
    private val createPrompt: () -> DestinationPrompt,
    private val execute: (DestinationVoiceCommand) -> DestinationVoiceReply,
    private val allowed: () -> Boolean,
    private val scheduleTimeout: (() -> Unit) -> (() -> Unit),
    private val onState: (DestinationVoiceState) -> Unit,
) {
    var state = DestinationVoiceState()
        private set
    private var generation = 0L
    private var recognition: DestinationRecognition? = null
    private var prompt: DestinationPrompt? = null
    private var cancelTimeout: (() -> Unit)? = null

    fun start() {
        cancel()
        listen()
    }

    fun cancel() = finish("")

    private fun listen() {
        if (!allowed()) { finish("음성 입력을 사용할 수 없어요."); return }
        val token = ++generation
        publish(DestinationVoiceState(busy = true, message = "목적지 추천, 안내해 줘, 다른 데는 중 하나를 말해 주세요."))
        if (!active(token)) return
        try {
            val engine = createRecognition()
            if (!active(token)) { runCatching { engine.close() }; return }
            recognition = engine
            armTimeout(token)
            if (!active(token)) return
            engine.start(
                onReady = {
                    if (active(token)) {
                        if (!allowed()) finish("음성 입력을 사용할 수 없어요.")
                        else publish(state.copy(listening = true))
                    }
                },
                onFinal = { text ->
                    if (active(token)) {
                        // Invalidate first: close() may synchronously report an end/error/result.
                        val next = ++generation
                        releaseResources()
                        if (active(next)) {
                            if (!allowed()) finish("음성 입력을 사용할 수 없어요.")
                            else {
                                val command = parse(text)
                                if (command == null) finish("말씀을 이해하지 못했어요. 다시 음성 입력을 시작해 주세요.")
                                else {
                                    publish(state.copy(listening = false))
                                    if (active(next) && allowed()) {
                                        try {
                                            val reply = execute(command)
                                            if (active(next)) speak(reply)
                                        } catch (_: Exception) {
                                            if (active(next)) finish("목적지 요청을 처리하지 못했어요.")
                                        }
                                    } else if (active(next)) finish("음성 입력을 사용할 수 없어요.")
                                }
                            }
                        }
                    }
                },
                onFailure = { message ->
                    if (active(token)) finish(message.ifBlank { "음성을 인식하지 못했어요." })
                },
            )
        } catch (_: Exception) {
            if (active(token)) finish("음성 인식을 시작하지 못했어요.")
        }
    }

    private fun speak(reply: DestinationVoiceReply) {
        if (!allowed()) { finish("음성 입력을 사용할 수 없어요."); return }
        val token = ++generation
        publish(DestinationVoiceState(busy = true, message = reply.message))
        if (!active(token)) return
        try {
            val engine = createPrompt()
            if (!active(token)) { runCatching { engine.close() }; return }
            prompt = engine
            armTimeout(token)
            if (!active(token)) return
            engine.speak(reply.message,
                onDone = {
                    if (active(token)) {
                        val next = ++generation
                        releaseResources()
                        if (active(next)) {
                            if (reply.listenAgain) listen()
                            else finish(reply.message)
                        }
                    }
                },
                onFailure = {
                    if (active(token)) finish("음성 안내를 재생하지 못했어요. ${reply.message}")
                },
            )
        } catch (_: Exception) {
            if (active(token)) finish("음성 안내를 재생하지 못했어요. ${reply.message}")
        }
    }

    private fun active(token: Long) = generation == token && state.busy

    private fun armTimeout(token: Long) {
        val cancel = scheduleTimeout {
            if (active(token)) finish("음성 응답 시간이 지났어요. 다시 시작해 주세요.")
        }
        if (active(token)) cancelTimeout = cancel else runCatching { cancel() }
    }

    private fun finish(message: String) {
        ++generation
        releaseResources()
        publish(DestinationVoiceState(message = message))
    }

    private fun releaseResources() {
        val timer = cancelTimeout
        val oldRecognition = recognition
        val oldPrompt = prompt
        cancelTimeout = null
        recognition = null
        prompt = null
        runCatching { timer?.invoke() }
        runCatching { oldRecognition?.close() }
        runCatching { oldPrompt?.close() }
    }

    private fun publish(next: DestinationVoiceState) {
        state = next
        onState(next)
    }

    companion object {
        private val suggest = setOf("목적지추천", "목적지추천해줘", "목적지추천해주세요", "목적지제안해줘",
            "여행지추천해줘", "갈곳추천해줘", "추천해줘", "추천해주세요", "어디로갈까", "어디로갈까요")
        private val accept = setOf("응", "네", "예", "좋아", "좋아요", "안내해줘", "안내해주세요",
            "거기로안내해줘", "수락", "수락할게", "수락할게요",
            "응안내해줘", "응,안내해줘", "네안내해주세요", "네,안내해주세요")
        private val next = setOf("다른데는", "다른데", "다른곳은", "다른곳", "다른곳추천해줘",
            "다음", "다음후보", "다음후보보여줘", "다른후보", "다음장소")

        /** Whole utterances only: a positive word inside a negative or compound phrase is not consent. */
        fun parse(text: String): DestinationVoiceCommand? {
            val trimmed = text.trim()
            val phrase = trimmed.trimEnd('.', '!', '?', '。', '！', '？')
                .filterNot { it.isWhitespace() }
            return when {
                phrase in suggest -> DestinationVoiceCommand.SUGGEST
                phrase in next -> DestinationVoiceCommand.NEXT
                phrase in accept && '?' !in trimmed && '？' !in trimmed -> DestinationVoiceCommand.ACCEPT
                else -> null
            }
        }
    }
}
