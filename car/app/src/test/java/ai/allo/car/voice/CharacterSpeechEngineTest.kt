package ai.allo.car.voice

import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File

@OptIn(ExperimentalCoroutinesApi::class)
class CharacterSpeechEngineTest {
    private class Player : PlazaClipPlayer {
        lateinit var ready: () -> Unit
        lateinit var done: () -> Unit
        lateinit var failed: () -> Unit
        var plays = 0
        var releases = 0
        override fun prepare(asset: String, ready: () -> Unit, done: () -> Unit, failed: () -> Unit) {
            this.ready = ready; this.done = done; this.failed = failed
        }
        override fun play() { plays++ }
        override fun release() { releases++ }
    }
    @Test fun `stop cancels pending synthesis and cannot play late audio`() = runTest {
        val pending = CompletableDeferred<File>()
        var players = 0
        val engine = CharacterSpeechEngine(backgroundScope, { pending.await() }, { players++; Player() })
        val events = mutableListOf<DialogueSpeechEvent>()
        engine.listen { events += it }
        engine.speak("안녕")
        runCurrent()
        engine.stop()
        pending.complete(File("late.wav"))
        runCurrent()
        assertEquals(0, players)
        assertEquals(listOf(DialogueSpeechEvent.Stopped), events)
        engine.release()
    }
    @Test fun `replacement ignores old player callbacks and reports completion only after playback`() = runTest {
        val players = mutableListOf<Player>()
        val engine = CharacterSpeechEngine(backgroundScope, { File("clip.wav") }, { Player().also { players += it } })
        val events = mutableListOf<DialogueSpeechEvent>()
        engine.listen { events += it }
        engine.speak("첫 문장"); runCurrent()
        engine.speak("다음 문장"); runCurrent()
        players[0].ready(); players[0].done(); players[0].failed()
        assertEquals(0, players[0].plays)
        assertEquals(1, players[0].releases)
        assertTrue(events.isEmpty())
        players[1].ready(); assertEquals(1, players[1].plays)
        assertTrue(events.isEmpty())
        players[1].done(); assertEquals(listOf(DialogueSpeechEvent.Done), events)
        engine.release()
    }
    @Test fun `synthesis failure reports failure without using another voice`() = runTest {
        var players = 0
        val engine = CharacterSpeechEngine(backgroundScope, { throw java.io.IOException() }, { players++; Player() })
        val events = mutableListOf<DialogueSpeechEvent>()
        engine.listen { events += it }
        engine.speak("안녕"); runCurrent()
        assertEquals(0, players)
        assertTrue(events.single() is DialogueSpeechEvent.Failed)
        engine.release()
    }

    private class Prompt : DestinationPrompt {
        var text: String? = null
        lateinit var done: () -> Unit
        lateinit var failed: () -> Unit
        var closes = 0
        override fun speak(text: String, onDone: () -> Unit, onFailure: () -> Unit) {
            this.text = text; done = onDone; failed = onFailure
        }
        override fun close() { closes++ }
    }
    @Test fun `cloud error falls back once with identical text and waits for actual completion`() = runTest {
        val fallback = Prompt()
        val events = mutableListOf<DialogueSpeechEvent>()
        val engine = CharacterSpeechEngine(backgroundScope, { error("HTTP 503") }, { Player() }, { fallback })
        engine.listen { events += it }
        engine.speak("바다로 안내할게요"); runCurrent()
        assertEquals("바다로 안내할게요", fallback.text)
        assertTrue(events.isEmpty())
        fallback.done(); fallback.failed(); fallback.done()
        assertEquals(listOf(DialogueSpeechEvent.Done), events)
        assertEquals(1, fallback.closes)
        engine.release()
    }
    @Test fun `cloud preparation timeout cancels request and late callbacks cannot overlap fallback`() = runTest {
        val pending = CompletableDeferred<File>()
        val fallback = Prompt()
        var players = 0
        val engine = CharacterSpeechEngine(backgroundScope, { pending.await() }, { players++; Player() }, { fallback })
        engine.speak("다음 후보"); runCurrent()
        advanceTimeBy(6_000); runCurrent()
        assertEquals("다음 후보", fallback.text)
        pending.complete(File("late.wav")); runCurrent()
        assertEquals(0, players)
        engine.release()
    }
    @Test fun `player failure releases cloud and ignores its late completion`() = runTest {
        val p = Player(); val fallback = Prompt()
        val events = mutableListOf<DialogueSpeechEvent>()
        val engine = CharacterSpeechEngine(backgroundScope, { File("clip.wav") }, { p }, { fallback })
        engine.listen { events += it }
        engine.speak("안녕"); runCurrent()
        p.ready(); p.failed(); p.failed(); p.done()
        assertEquals(1, p.releases)
        assertEquals("안녕", fallback.text)
        assertTrue(events.isEmpty())
        fallback.done()
        assertEquals(listOf(DialogueSpeechEvent.Done), events)
        engine.release()
    }
    @Test fun `stop during fallback closes it and suppresses late completion`() = runTest {
        val fallback = Prompt(); val events = mutableListOf<DialogueSpeechEvent>()
        val engine = CharacterSpeechEngine(backgroundScope, { error("offline") }, { Player() }, { fallback })
        engine.listen { events += it }
        engine.speak("안녕"); runCurrent(); engine.stop()
        fallback.done(); fallback.failed()
        assertEquals(1, fallback.closes)
        assertEquals(listOf(DialogueSpeechEvent.Stopped), events)
        engine.release()
    }
    @Test fun `fallback failure and timeout terminate without retry`() = runTest {
        for (timeout in listOf(false, true)) {
            val fallback = Prompt(); var creates = 0
            val events = mutableListOf<DialogueSpeechEvent>()
            val engine = CharacterSpeechEngine(CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler)), { error("offline") }, { Player() }, { creates++; fallback })
            engine.listen { events += it }
            engine.speak("안녕"); runCurrent()
            if (timeout) { advanceTimeBy(12_000); runCurrent() } else fallback.failed()
            fallback.done()
            assertEquals(1, creates)
            assertTrue(events.single() is DialogueSpeechEvent.Failed)
            assertEquals(1, fallback.closes)
            engine.release()
        }
    }
    @Test fun `successful cloud playback never creates fallback`() = runTest {
        val p = Player(); var creates = 0
        val engine = CharacterSpeechEngine(backgroundScope, { File("clip.wav") }, { p }, { creates++; Prompt() })
        engine.speak("안녕"); runCurrent(); p.ready()
        advanceTimeBy(7_000); runCurrent()
        assertEquals(0, creates)
        p.done(); engine.release()
    }
}
