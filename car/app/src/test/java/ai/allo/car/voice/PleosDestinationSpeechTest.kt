package ai.allo.car.voice

import ai.pleos.playground.stt.constant.ErrorType
import ai.pleos.playground.stt.listener.ResultListener
import org.junit.Assert.*
import org.junit.Test

class PleosDestinationSpeechTest {
    private class Recognition : DestinationRecognition {
        lateinit var listener: ResultListener
        var closed = false
        override fun start(onReady: () -> Unit, onFinal: (String) -> Unit, onFailure: (String) -> Unit) {
            listener = DestinationResultListener(
                dispatch = { action -> if (!closed) action() },
                ready = onReady, finalResult = onFinal, failure = onFailure,
            )
        }
        override fun close() { closed = true }
    }

    private class Prompt : DestinationPrompt {
        override fun speak(text: String, onDone: () -> Unit, onFailure: () -> Unit) = Unit
        override fun close() = Unit
    }

    private class Harness {
        val recognition = Recognition()
        val commands = mutableListOf<DestinationVoiceCommand>()
        var timeout: () -> Unit = {}
        val controller = DestinationVoiceController(
            createRecognition = { recognition },
            createPrompt = { Prompt() },
            execute = { commands += it; DestinationVoiceReply("안내할까요?", listenAgain = true) },
            allowed = { true },
            scheduleTimeout = { action -> timeout = action; {} },
            onState = {},
        )
        init { controller.start() }
    }

    @Test fun `EPD ended before completed STT does not discard the final utterance`() {
        val h = Harness()
        h.recognition.listener.onStartedRecognition()
        h.recognition.listener.onUpdated("목적지 추천", false)
        h.recognition.listener.onEndedRecognition()
        assertTrue("Keep waiting for UpdateSttCompleted", h.controller.state.busy)
        assertFalse(h.recognition.closed)
        assertTrue(h.commands.isEmpty())
        h.recognition.listener.onUpdated("목적지 추천해 줘", true)
        assertEquals(listOf(DestinationVoiceCommand.SUGGEST), h.commands)
        assertTrue(h.recognition.closed)
        h.recognition.listener.onUpdated("응", true)
        assertEquals(1, h.commands.size)
    }

    @Test fun `partial and ended events alone never execute a command and remain timeout bounded`() {
        val h = Harness()
        h.recognition.listener.onReady()
        h.recognition.listener.onUpdated("응", false)
        h.recognition.listener.onUpdatedEpdData(1, 2)
        h.recognition.listener.onEndedRecognition()
        assertTrue(h.commands.isEmpty())
        assertTrue(h.controller.state.busy)
        h.timeout()
        assertTrue(h.recognition.closed)
        assertFalse(h.controller.state.busy)
        h.recognition.listener.onUpdated("응", true)
        assertTrue(h.commands.isEmpty())
    }

    @Test fun `completed transcript before ended still executes exactly once`() {
        val h = Harness()
        h.recognition.listener.onUpdated("다른 데는?", true)
        h.recognition.listener.onEndedRecognition()
        h.recognition.listener.onUpdated("다른 데는?", true)
        assertEquals(listOf(DestinationVoiceCommand.NEXT), h.commands)
        assertTrue(h.controller.state.busy)
    }

    @Test fun `SDK error remains terminal and ignores a later final transcript`() {
        val h = Harness()
        h.recognition.listener.onError(ErrorType.values().first())
        assertTrue(h.recognition.closed)
        assertFalse(h.controller.state.busy)
        h.recognition.listener.onUpdated("응", true)
        assertTrue(h.commands.isEmpty())
    }
}
