package ai.allo.car.model

import ai.allo.car.dialogue.DialogueBank
import kotlin.test.*

class CompanionDialogueTest {
    private val bank = DialogueBank(
        mapOf(
            "ask_name|puddle_pip|hatched" to listOf("나는 {name}!"),
            "ask_name|road_sprout|hatched" to listOf("다른 친구"),
            "ask_mood|@water|hatched" to listOf("물 기분"),
            "ask_mood|@normal|hatched" to listOf("알의 기분"),
        ),
        mapOf("puddle_pip" to DialogueBank.Species("물방울", "water"),
            "road_sprout" to DialogueBank.Species("새싹", "normal")),
    )
    private val dialogue = CompanionDialogue(bank)
    private val car = CompanionDisplay("pet-a", 4, "puddle_pip", "car")
    private val v2 = GameState(contractVersion = 2, gameRevision = 3,
        stage = "incubating", speciesId = "road_sprout", attribute = "normal", companion = car)

    @Test fun `v2 selects current companion instead of unrelated legacy egg`() {
        assertEquals("puddle_pip", dialogue.subject(v2, true)?.speciesId)
        assertEquals(DialogueAnswer("ask_name", "나는 물방울!", true), dialogue.answer("ask_name", v2, true))
        assertEquals("물 기분", dialogue.answer("ask_mood", v2, true)?.text)
    }

    @Test fun `legacy only allows hatched nonblank species and catalog attribute`() {
        val legacy = GameState(stage = "hatched", speciesId = "puddle_pip", attribute = "normal")
        assertEquals("물 기분", dialogue.answer("ask_mood", legacy, true)?.text)
        listOf("idle", "incubating", "failed").forEach { assertNull(dialogue.subject(legacy.copy(stage = it), true)) }
        assertNull(dialogue.subject(legacy.copy(speciesId = " "), true))
        assertNull(dialogue.subject(legacy.copy(speciesId = null), true))
    }

    @Test fun `unavailable v2 companion never falls back to legacy species`() {
        val game = v2.copy(stage = "hatched")
        listOf(game.copy(companion = null), game.copy(invalidBlocks = setOf("companion")),
            game.copy(companion = car.copy(location = "phone")), game.copy(companion = car.copy(location = "unknown")),
            game.copy(companion = car.copy(displayId = "")), game.copy(companion = car.copy(displayRevision = -1)),
            game.copy(companion = car.copy(speciesId = " "))).forEach {
            assertNull(dialogue.subject(it, true))
            assertNull(dialogue.answer("ask_name", it, true))
        }
        assertNull(dialogue.subject(game, false))
        assertNull(dialogue.answer("ask_name", game, false))
    }

    @Test fun `each answer validates current state and allowed question`() {
        assertNotNull(dialogue.answer("ask_name", v2, true))
        assertNull(dialogue.answer("ask_name", v2.copy(companion = car.copy(location = "phone")), true))
        assertNull(dialogue.answer("car_accept", v2, true))
        assertEquals(listOf("ask_name", "ask_origin", "ask_like", "ask_mood"), CompanionDialogue.QUESTIONS.map { it.id })
    }

    @Test fun `identity changes reset dialogue when companion changes`() {
        val key = dialogue.subject(v2, true)!!.key
        listOf(car.copy(displayId = "pet-b"), car.copy(displayRevision = 5), car.copy(speciesId = "road_sprout"))
            .forEach { assertNotEquals(key, dialogue.subject(v2.copy(companion = it), true)!!.key) }
        assertEquals(key, dialogue.subject(v2.copy(progress = .7, gameRevision = 4), true)!!.key)
    }

    @Test fun `missing bank returns honest generic fallback`() {
        val empty = CompanionDialogue(DialogueBank.EMPTY)
        assertEquals(DialogueAnswer("ask_name", "이 질문의 답변은 아직 준비 중이에요.", false), empty.answer("ask_name", v2, true))
        assertEquals(false, dialogue.answer("ask_origin", v2, true)?.fromBank)
    }

    @Test fun `reviewed bank policy is preserved`() {
        val filtered = DialogueBank.parse("""{"entries":[{"key":"ask_name|*|hatched","lines":["미검수"],"reviewedBy":null}]}""", null, false)
        assertFalse(CompanionDialogue(filtered).answer("ask_name", v2, true)!!.fromBank)
    }
}
