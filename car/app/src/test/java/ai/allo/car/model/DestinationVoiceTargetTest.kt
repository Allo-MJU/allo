package ai.allo.car.model

import ai.allo.car.dialogue.DialogueBank
import kotlin.test.*

class DestinationVoiceTargetTest {
    private val dialogue = CompanionDialogue(DialogueBank.EMPTY)
    private val companion = CompanionDisplay("pet-a", 4, "puddle_pip", "car")
    private val game = GameState(contractVersion = 2, gameRevision = 3,
        stage = "incubating", speciesId = "road_sprout", companion = companion,
        collectionSummary = CollectionSummary(wood = 0, stone = 0, ingredient = 0, speciesIds = listOf("road_sprout", "puddle_pip")))

    @Test fun `story guest and destination companion keep separate species and identity`() {
        val story = assertNotNull(dialogue.subject(game, true, "road_sprout"))
        val destination = assertNotNull(dialogue.subject(game, true))
        assertEquals("road_sprout", story.speciesId)
        assertEquals("puddle_pip", destination.speciesId)
        val target = DestinationVoiceTarget("session-a", destination)
        assertTrue(target.matches("session-a", dialogue.subject(game, true)))
        assertFalse(target.matches("session-a", story))
        // A guest of the same species is still not the phone-selected individual.
        assertFalse(target.matches("session-a", dialogue.subject(game, true, "puddle_pip")))
    }

    @Test fun `selected individual revision species location and session changes invalidate voice`() {
        val target = DestinationVoiceTarget("session-a", assertNotNull(dialogue.subject(game, true)))
        for (replacement in listOf(
            companion.copy(displayId = "pet-b"), companion.copy(displayRevision = 5),
            companion.copy(speciesId = "road_sprout"), companion.copy(location = "phone"),
        )) assertFalse(target.matches("session-a", dialogue.subject(game.copy(companion = replacement), true)))
        assertFalse(target.matches("session-b", dialogue.subject(game, true)))
        assertFalse(target.matches("session-a", dialogue.subject(game, false)))
        assertFalse(target.matches("session-a", dialogue.subject(game.copy(companion = null), true)))
        assertFalse(target.matches("session-a", dialogue.subject(game.copy(invalidBlocks = setOf("companion")), true)))
    }

    @Test fun `unrelated egg and heartbeat changes do not switch selected voice`() {
        val target = DestinationVoiceTarget("session-a", assertNotNull(dialogue.subject(game, true)))
        val updated = game.copy(gameRevision = 4, progress = 0.7, speciesId = "sea_mist", stage = "hatched")
        assertTrue(target.matches("session-a", dialogue.subject(updated, true)))
        assertEquals("puddle_pip", dialogue.subject(updated, true)?.speciesId)
    }

    @Test fun `absent or phone-only companion never invents a destination speaker from an egg or guest`() {
        val noCompanion = game.copy(stage = "hatched", companion = null)
        assertNotNull(dialogue.subject(noCompanion, true, "road_sprout"))
        assertNull(dialogue.subject(noCompanion, true))
        assertNull(dialogue.subject(game.copy(companion = companion.copy(location = "phone")), true))
    }
}
