package ai.allo.car.voice

import org.junit.Assert.*
import org.junit.Test

class DialogueVoiceTest {
    private class Engine : DialogueSpeechEngine {
        lateinit var initialized: (String?) -> Unit
        lateinit var event: (DialogueSpeechEvent) -> Unit
        val spoken = mutableListOf<String>()
        var stops = 0
        var releases = 0
        var listens = 0
        var throwSpeak = false
        var throwListen = false
        override fun initialize(result: (String?) -> Unit) { initialized = result }
        override fun listen(event: (DialogueSpeechEvent) -> Unit) {
            if (throwListen) error("service unavailable")
            listens++
            this.event = event
        }
        override fun speak(text: String) {
            if (throwSpeak) error("service unavailable")
            spoken += text
        }
        override fun stop() { stops++ }
        override fun release() { releases++ }
    }

    @Test fun `not ready speech is discarded and listeners wait for initialization`() {
        val engine = Engine()
        val voice = DialogueVoice { engine }
        voice.start()
        voice.start()
        assertFalse(voice.speak("not queued"))
        assertEquals(0, engine.listens)
        engine.initialized(null)
        assertTrue(voice.state.value.ready)
        assertTrue(engine.spoken.isEmpty())
        assertFalse(voice.speak("   "))
        assertTrue(voice.speak("hello"))
        assertEquals(listOf("hello"), engine.spoken)
        assertTrue(voice.state.value.speaking)
        engine.event(DialogueSpeechEvent.Done)
        assertFalse(voice.state.value.speaking)
    }

    @Test fun `second tap stops and asynchronous errors reach state`() {
        val engine = Engine()
        val voice = DialogueVoice { engine }
        voice.start()
        engine.initialized(null)
        assertTrue(voice.speak("hello"))
        assertFalse(voice.speak("hello"))
        assertEquals(1, engine.stops)
        assertFalse(voice.state.value.speaking)
        assertTrue(voice.speak("again"))
        engine.event(DialogueSpeechEvent.Failed("engine failed"))
        assertFalse(voice.state.value.speaking)
        assertEquals("engine failed", voice.state.value.error)
        engine.throwSpeak = true
        assertFalse(voice.speak("failure"))
        assertFalse(voice.state.value.speaking)
    }

    @Test fun `late initialize after release never attaches or becomes ready`() {
        val engine = Engine()
        val voice = DialogueVoice { engine }
        voice.start()
        voice.release()
        voice.release()
        engine.initialized(null)
        assertEquals(0, engine.listens)
        assertEquals(2, engine.releases)
        assertEquals(DialogueVoiceState(), voice.state.value)
        assertFalse(voice.speak("never"))
    }

    @Test fun `late playback callbacks cannot restore released state`() {
        val engine = Engine()
        val voice = DialogueVoice { engine }
        voice.start()
        engine.initialized(null)
        voice.speak("hello")
        voice.release()
        engine.event(DialogueSpeechEvent.Failed("late"))
        assertEquals(DialogueVoiceState(), voice.state.value)
    }

    @Test fun `initialization and listener failures never expose ready state`() {
        val engine = Engine()
        val voice = DialogueVoice { engine }
        voice.start()
        engine.initialized("unavailable")
        assertFalse(voice.state.value.ready)
        assertEquals("unavailable", voice.state.value.error)
        val other = Engine().apply { throwListen = true }
        val second = DialogueVoice { other }
        second.start()
        other.initialized(null)
        assertFalse(second.state.value.ready)
        assertNotNull(second.state.value.error)
        assertFalse(second.speak("never"))
    }
}
