package ai.allo.car.dialogue

import ai.allo.car.model.CompanionDialogue
import ai.allo.car.model.GameState
import ai.allo.car.ui.SpeciesCatalog
import java.io.File
import kotlin.test.*
import kotlinx.serialization.json.*

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

    @Test fun `all twelve supplied friends have explicit vehicle answers matching the style contract`() {
        val entries = Json.parseToJsonElement(extra).jsonObject.getValue("entries").jsonArray.map { it.jsonObject }
        val ids = SpeciesCatalog.parse(display).entries.keys
        val questions = setOf("ask_name", "ask_origin", "ask_like", "ask_mood")
        assertEquals(ids.flatMap { id -> questions.map { "$it|$id|hatched" } }.toSet(),
            entries.map { it.getValue("key").jsonPrimitive.content }.toSet())
        entries.forEach { entry ->
            val key = entry.getValue("key").jsonPrimitive.content
            val lines = entry.getValue("lines").jsonArray.map { it.jsonPrimitive.content }
            assertEquals(2, lines.distinct().size, key)
            assertEquals(JsonNull, entry["reviewedBy"], "Editing copy does not approve it for release")
            lines.forEach { line ->
                assertTrue(line.length in 1..50, "$key: $line")
                assertFalse('?' in line || '？' in line, "$key: $line")
                assertTrue(Regex("[.!?]+").findAll(line).count() <= 3, "$key: $line")
                if (key.startsWith("ask_mood|")) {
                    listOf("비가 와", "비 오는", "빗소리가", "밤이라", "지금 밤", "오늘 처음").forEach {
                        assertFalse(it in line, "$key: unsupported current-context claim: $line")
                    }
                }
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
