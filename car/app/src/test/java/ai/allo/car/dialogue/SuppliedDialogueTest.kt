package ai.allo.car.dialogue

import ai.allo.car.model.CompanionDialogue
import ai.allo.car.model.GameState
import ai.allo.car.ui.SpeciesCatalog
import java.io.File
import kotlin.test.*

class SuppliedDialogueTest {
    private val original = File("../../data/species.json").readText()
    private val display = File("../../data/characters.json").readText()
    private val main = File("../../data/dialogue.json").readText()
    private val extra = File("src/main/assets/companion-dialogue.json").readText()
    private fun bank(debug: Boolean) = DialogueBank.parse(main, original, debug)
        .supplementedBy(DialogueBank.parse(extra, display, debug))

    @Test fun `all supplied friends answer all four story questions without fallback`() {
        val bank = bank(true)
        val dialogue = CompanionDialogue(bank)
        SpeciesCatalog.parse(display).entries.forEach { (id, species) ->
            assertEquals(species.name, bank.speciesName(id))
            val game = GameState(stage = "hatched", speciesId = id)
            CompanionDialogue.QUESTIONS.forEach { question ->
                val first = assertNotNull(dialogue.answer(question.id, game, true))
                val second = assertNotNull(dialogue.answer(question.id, game, true))
                assertTrue(first.fromBank, "$id/${question.id}")
                assertTrue(second.fromBank, "$id/${question.id}")
                assertNotEquals(first.text, second.text, "$id/${question.id}")
                assertTrue(first.text.length in 1..50)
                assertFalse(first.text.contains('{'))
                if (question.id == "ask_name") assertTrue(first.text.contains(species.name))
            }
        }
    }

    @Test fun `supplement retains legacy species and does not bypass release review`() {
        val newIds = SpeciesCatalog.parse(display).entries.keys - SpeciesCatalog.parse(original).entries.keys
        val release = bank(false)
        newIds.forEach { id ->
            CompanionDialogue.QUESTIONS.forEach { question ->
                assertNull(release.line(question.id, id, "unassigned", "hatched"), "$id/${question.id}")
            }
        }
        assertNotNull(bank(true).line("ask_name", "bridge_hopper", null, "hatched"))
        assertNotNull(bank(true).speciesName("bridge_hopper"))
    }
}
