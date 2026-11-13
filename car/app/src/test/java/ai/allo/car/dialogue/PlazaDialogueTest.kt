package ai.allo.car.dialogue

import ai.allo.car.ui.SpeciesCatalog
import java.io.File
import kotlin.test.*

class PlazaDialogueTest {
    @Test fun `every actual species has two distinct short plaza lines`() {
        val source = sequenceOf(File("../../data/species.json"), File("data/species.json"))
            .first { it.exists() }
        val species = SpeciesCatalog.parse(source.readText()).entries.keys
        assertEquals(12, species.size)
        val supplied = SpeciesCatalog.parse(File("../../data/characters.json").readText()).entries.keys
        assertEquals(species + supplied, PlazaDialogue.lines.keys)
        PlazaDialogue.lines.forEach { (id, lines) ->
            assertEquals(2, lines.distinct().size, id)
            lines.forEach { line ->
                assertTrue(line.length in 1..25, "$id: $line")
                assertFalse(line.contains('?'), "Plaza greetings do not ask the child for an answer")
            }
        }
    }

    @Test fun `runtime plaza lines match the documented character lines`() {
        val game = SpeciesCatalog.parse(File("../../data/species.json").readText()).entries
        val display = SpeciesCatalog.parse(File("../../data/characters.json").readText()).entries
        val byName = (game + display).values.associate { it.name to it.id }
        val documented = File("../../docs/vehicle/plaza-dialogue.md").readLines().mapNotNull { row ->
            val cells = row.split('|').map { it.trim() }
            val id = cells.getOrNull(1)?.let { byName[it] } ?: return@mapNotNull null
            if (cells.size != 5) return@mapNotNull null
            id to listOf(cells[2], cells[3])
        }.toMap()
        assertEquals(PlazaDialogue.lines, documented)
    }

    @Test fun `each species alternates independently even when another friend is tapped`() {
        val dialogue = PlazaDialogue()
        repeat(4) { round ->
            PlazaDialogue.lines.forEach { (id, choices) ->
                assertEquals(choices[round % 2], dialogue.next(id))
            }
        }
    }

    @Test fun `unknown species never speaks another characters line or advances its sequence`() {
        val dialogue = PlazaDialogue()
        assertNull(dialogue.next("unknown"))
        assertEquals(PlazaDialogue.lines.getValue("road_sprout")[0], dialogue.next("road_sprout"))
        assertNull(dialogue.next("unknown"))
        assertEquals(PlazaDialogue.lines.getValue("road_sprout")[1], dialogue.next("road_sprout"))
    }
}
