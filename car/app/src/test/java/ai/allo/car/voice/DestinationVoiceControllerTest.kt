package ai.allo.car.voice

import org.junit.Assert.*
import org.junit.Test

class DestinationVoiceControllerTest {
    private class Recognition : DestinationRecognition {
        lateinit var ready: () -> Unit
        lateinit var final: (String) -> Unit
        lateinit var failure: (String) -> Unit
        var closed = false
        var whenClosing: (() -> Unit)? = null
        override fun start(onReady: () -> Unit, onFinal: (String) -> Unit, onFailure: (String) -> Unit) {
            ready = onReady; final = onFinal; failure = onFailure
        }
        override fun close() { closed = true; whenClosing?.invoke() }
    }

    private class Prompt : DestinationPrompt {
        lateinit var done: () -> Unit
        lateinit var failure: () -> Unit
        var text = ""
        var closed = false
        var whenClosing: (() -> Unit)? = null
        override fun speak(text: String, onDone: () -> Unit, onFailure: () -> Unit) {
            this.text = text; done = onDone; failure = onFailure
        }
        override fun close() { closed = true; whenClosing?.invoke() }
    }

    private class Timer(val fire: () -> Unit) { var cancelled = false }
    private class Harness {
        var permitted = true
        val recognitions = mutableListOf<Recognition>()
        val prompts = mutableListOf<Prompt>()
        val timers = mutableListOf<Timer>()
        val commands = mutableListOf<DestinationVoiceCommand>()
        val states = mutableListOf<DestinationVoiceState>()
        var execute: (DestinationVoiceCommand) -> DestinationVoiceReply = { command ->
            DestinationVoiceReply(if (command == DestinationVoiceCommand.ACCEPT) "안내를 요청했어요." else "이곳까지 안내할까요?",
                listenAgain = command != DestinationVoiceCommand.ACCEPT)
        }
        val controller = DestinationVoiceController(
            createRecognition = { Recognition().also { recognitions += it } },
            createPrompt = { Prompt().also { prompts += it } },
            execute = {
                assertTrue("Microphone must close before navigation", recognitions.last().closed)
                commands += it
                execute(it)
            },
            allowed = { permitted },
            scheduleTimeout = { callback -> Timer(callback).also { timers += it }.let { timer -> { timer.cancelled = true } } },
            onState = { states += it },
        )
    }

    @Test fun `whole Korean phrases map to suggestion acceptance and alternative only`() {
        val expected = mapOf(
            "목적지 추천" to DestinationVoiceCommand.SUGGEST,
            "목적지 추천해 주세요." to DestinationVoiceCommand.SUGGEST,
            "어디로 갈까?" to DestinationVoiceCommand.SUGGEST,
            "여행지 추천해줘" to DestinationVoiceCommand.SUGGEST,
            " 응! " to DestinationVoiceCommand.ACCEPT,
            "네" to DestinationVoiceCommand.ACCEPT,
            "안내해 주세요" to DestinationVoiceCommand.ACCEPT,
            "거기로 안내해 줘" to DestinationVoiceCommand.ACCEPT,
            "응, 안내해 줘" to DestinationVoiceCommand.ACCEPT,
            "응 안내해줘" to DestinationVoiceCommand.ACCEPT,
            "네 안내해 주세요" to DestinationVoiceCommand.ACCEPT,
            "네, 안내해 주세요" to DestinationVoiceCommand.ACCEPT,
            "다른 데는?" to DestinationVoiceCommand.NEXT,
            "다음 후보 보여줘" to DestinationVoiceCommand.NEXT,
            "다른 곳 추천해 줘" to DestinationVoiceCommand.NEXT,
        )
        expected.forEach { (text, command) -> assertEquals(text, command, DestinationVoiceController.parse(text)) }
        listOf("", " ", "아니", "아니요", "거절", "취소", "안내하지 마", "안내해 주지 마", "네 아니요",
            "응, 취소해", "응 아니", "추천하지 마", "다음 후보 말고", "다른 데는 싫어", "네?", "좋아요?",
            "네가 정해", "응급실", "아니 다음 후보", "목적지 추천하고 안내해줘", "응, 안내해 주지 마", "네, 안내하지 마세요",
            "응 안내해줘 아니 취소", "네, 안내해주세요 말고 다음 후보").forEach {
            assertNull(it, DestinationVoiceController.parse(it))
        }
    }

    @Test fun `suggest then next then accept waits for each prompt to finish`() {
        val h = Harness()
        h.controller.start()
        assertTrue(h.controller.state.busy)
        assertFalse(h.controller.state.listening)
        h.recognitions[0].ready()
        assertTrue(h.controller.state.listening)
        h.recognitions[0].final("목적지 추천")
        assertEquals(listOf(DestinationVoiceCommand.SUGGEST), h.commands)
        assertFalse(h.controller.state.listening)
        assertEquals(1, h.recognitions.size)
        assertTrue(h.timers[0].cancelled)
        h.prompts[0].done()
        assertTrue(h.prompts[0].closed)
        assertEquals(2, h.recognitions.size)
        h.recognitions[1].final("다른 데는?")
        assertEquals(2, h.recognitions.size)
        h.prompts[1].done()
        h.recognitions[2].final("응")
        h.prompts[2].done()
        assertEquals(listOf(DestinationVoiceCommand.SUGGEST, DestinationVoiceCommand.NEXT, DestinationVoiceCommand.ACCEPT), h.commands)
        assertFalse(h.controller.state.busy)
        assertEquals("안내를 요청했어요.", h.controller.state.message)
        assertEquals(3, h.recognitions.size)
    }

    @Test fun `unknown final consumes the turn without navigation or retained transcript`() {
        val h = Harness()
        h.controller.start()
        val engine = h.recognitions.single()
        engine.final("응, 아니 가지 말자")
        engine.final("응")
        engine.ready()
        assertTrue(engine.closed)
        assertTrue(h.commands.isEmpty())
        assertTrue(h.prompts.isEmpty())
        assertFalse(h.controller.state.busy)
        assertTrue(h.states.none { it.message.contains("가지 말자") })
    }

    @Test fun `late and duplicate recognition callbacks cannot navigate or end current prompt`() {
        val h = Harness()
        h.controller.start()
        val old = h.recognitions.single()
        old.whenClosing = { old.final("응"); old.failure("late close error") }
        old.final("목적지 추천")
        old.final("응")
        old.ready()
        old.failure("late error")
        h.timers[0].fire()
        assertEquals(listOf(DestinationVoiceCommand.SUGGEST), h.commands)
        assertEquals("이곳까지 안내할까요?", h.controller.state.message)
        assertTrue(h.controller.state.busy)
        h.prompts.single().done()
        assertEquals(2, h.recognitions.size)
        old.final("응")
        assertEquals(1, h.commands.size)
    }

    @Test fun `late prompt completion cannot create extra listening turns`() {
        val h = Harness()
        h.controller.start()
        h.recognitions.single().final("추천해줘")
        val old = h.prompts.single()
        old.whenClosing = { old.done(); old.failure() }
        old.done()
        old.done()
        old.failure()
        h.timers[1].fire()
        assertEquals(2, h.recognitions.size)
        assertTrue(h.controller.state.busy)
    }

    @Test fun `cancel and restart rejects every previous turn callback`() {
        val h = Harness()
        h.controller.start()
        val old = h.recognitions.single()
        h.controller.cancel()
        assertTrue(old.closed)
        old.ready(); old.final("응"); old.failure("late")
        assertEquals(DestinationVoiceState(), h.controller.state)
        h.controller.start()
        old.final("응")
        assertTrue(h.commands.isEmpty())
        h.recognitions.last().final("다른 데는")
        assertEquals(listOf(DestinationVoiceCommand.NEXT), h.commands)
        val prompt = h.prompts.single()
        h.controller.cancel()
        prompt.done()
        prompt.failure()
        assertTrue(prompt.closed)
        assertEquals(2, h.recognitions.size)
        assertEquals(DestinationVoiceState(), h.controller.state)
    }

    @Test fun `initialization and listening timeouts close microphone and ignore late results`() {
        for (ready in listOf(false, true)) {
            val h = Harness()
            h.controller.start()
            val engine = h.recognitions.single()
            if (ready) engine.ready()
            h.timers.single().fire()
            engine.final("응"); engine.ready()
            assertTrue(engine.closed)
            assertTrue(h.commands.isEmpty())
            assertFalse(h.controller.state.busy)
        }
    }

    @Test fun `prompt timeout never starts listening even after late successful playback`() {
        val h = Harness()
        h.controller.start()
        h.recognitions.single().final("추천해줘")
        val prompt = h.prompts.single()
        h.timers.last().fire()
        prompt.done()
        assertTrue(prompt.closed)
        assertFalse(h.controller.state.busy)
        assertEquals(1, h.recognitions.size)
    }

    @Test fun `SDK errors and prompt failures are terminal and late success is ignored`() {
        val h = Harness()
        h.controller.start()
        h.recognitions.single().failure("마이크를 사용할 수 없어요.")
        h.recognitions.single().final("응")
        assertTrue(h.commands.isEmpty())
        assertFalse(h.controller.state.busy)
        h.controller.start()
        h.recognitions.last().final("추천해줘")
        val prompt = h.prompts.single()
        prompt.failure(); prompt.done()
        assertTrue(prompt.closed)
        assertFalse(h.controller.state.busy)
        assertEquals(2, h.recognitions.size)
    }

    @Test fun `permission is checked at start final result and prompt completion`() {
        val h = Harness()
        h.permitted = false
        h.controller.start()
        assertTrue(h.recognitions.isEmpty())
        h.permitted = true
        h.controller.start()
        h.permitted = false
        h.recognitions.last().final("응")
        assertTrue(h.commands.isEmpty())
        assertTrue(h.recognitions.last().closed)
        h.permitted = true
        h.controller.start()
        h.recognitions.last().final("추천해줘")
        h.permitted = false
        h.prompts.single().done()
        assertEquals(2, h.recognitions.size)
        assertFalse(h.controller.state.busy)
    }

    @Test fun `execute failure closes microphone without reading another response`() {
        val h = Harness()
        h.execute = { error("navi unavailable") }
        h.controller.start()
        h.recognitions.single().final("응")
        assertTrue(h.recognitions.single().closed)
        assertTrue(h.prompts.isEmpty())
        assertFalse(h.controller.state.busy)
    }
}
