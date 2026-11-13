package ai.allo.car.voice

import ai.allo.car.dialogue.PlazaDialogue
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class PlazaRecordedEngineTest {
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
    @Test fun `catalog matches live dialogue exactly and files exist`() {
        assertEquals(24, PlazaRecordings.entries.size)
        assertEquals(12, PlazaRecordings.entries.map { it.species }.toSet().size)
        assertEquals(24, PlazaRecordings.entries.map { it.asset }.toSet().size)
        for (e in PlazaRecordings.entries) {
            assertTrue(PlazaDialogue.lines.getValue(e.species).contains(e.text))
            assertTrue(File("src/main/assets", e.asset).length() > 44)
            assertEquals(e, PlazaRecordings.find(PlazaRecordings.request(e.species,e.text)))
            assertNull(PlazaRecordings.find(PlazaRecordings.request("unknown",e.text)))
            assertNull(PlazaRecordings.find(PlazaRecordings.request(e.species,e.text+"!")))
        }
    }
    @Test fun `replacement rejects late prepare and completion from previous character`() {
        val players = mutableListOf<Player>()
        val voice = DialogueVoice { PlazaRecordedEngine { Player().also { players += it } } }
        voice.start()
        val entries = PlazaRecordings.entries
        voice.replace(PlazaRecordings.request(entries[0].species,entries[0].text))
        voice.replace(PlazaRecordings.request(entries[2].species,entries[2].text))
        assertEquals(2,players.size)
        players[0].ready(); players[0].done(); players[0].failed()
        assertEquals(0,players[0].plays); assertEquals(1,players[0].releases)
        assertTrue(voice.state.value.speaking)
        players[1].ready(); assertEquals(1,players[1].plays)
        players[1].done(); assertFalse(voice.state.value.speaking)
        voice.release()
    }
    @Test fun `repeated tap and release prevent pending playback`() {
        val p = Player()
        val voice = DialogueVoice { PlazaRecordedEngine { p } }
        val e = PlazaRecordings.entries.first()
        val request = PlazaRecordings.request(e.species,e.text)
        voice.start(); assertTrue(voice.speak(request)); assertFalse(voice.speak(request))
        p.ready(); assertEquals(0,p.plays); assertFalse(voice.state.value.speaking)
        voice.release(); p.done(); assertFalse(voice.state.value.ready)
    }
    @Test fun `playback error returns to ready state`() {
        val p = Player()
        val voice = DialogueVoice { PlazaRecordedEngine { p } }
        val e = PlazaRecordings.entries.first()
        voice.start(); voice.speak(PlazaRecordings.request(e.species,e.text)); p.failed()
        assertFalse(voice.state.value.speaking); assertNotNull(voice.state.value.error)
        assertTrue(voice.state.value.ready); voice.release()
    }
}
