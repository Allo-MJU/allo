package ai.allo.car.model

import ai.allo.car.dialogue.DialogueBank

data class DialogueSubject(val key: String, val speciesId: String)
data class DialogueQuestion(val id: String, val label: String)
data class DialogueAnswer(val questionId: String, val text: String, val fromBank: Boolean)

/** Read-only dialogue for the currently displayed companion. The UI validates catalog membership. */
class CompanionDialogue(private val bank: DialogueBank) {
    fun subject(game: GameState, connected: Boolean, guestSpeciesId: String? = null): DialogueSubject? {
        if (!connected) return null
        // A guest is a local conversation target, never a replacement for the car companion.
        if (guestSpeciesId != null) {
            if (guestSpeciesId.isBlank() || guestSpeciesId !in PlazaPopulation.residents(game)) return null
            return DialogueSubject("guest:${guestSpeciesId.length}:$guestSpeciesId", guestSpeciesId)
        }
        if (game.hasV2Contract) {
            if ("companion" in game.invalidBlocks) return null
            val companion = game.companion ?: return null
            if (companion.location != "car" || companion.displayId.isBlank() ||
                companion.displayRevision < 0 || companion.speciesId.isBlank()) return null
            return DialogueSubject(
                // Length-prefix identifiers so embedded delimiters cannot alias another companion.
                "v2:${companion.displayId.length}:${companion.displayId}:${companion.displayRevision}:" +
                    "${companion.speciesId.length}:${companion.speciesId}:${companion.location}",
                companion.speciesId,
            )
        }
        val speciesId = game.speciesId?.takeIf { it.isNotBlank() } ?: return null
        if (game.stage != "hatched") return null
        return DialogueSubject("legacy:$speciesId", speciesId)
    }

    fun answer(questionId: String, game: GameState, connected: Boolean, guestSpeciesId: String? = null): DialogueAnswer? {
        if (QUESTIONS.none { it.id == questionId }) return null
        val selected = subject(game, connected, guestSpeciesId) ?: return null
        val vars = bank.speciesName(selected.speciesId)?.let { mapOf("name" to it) }.orEmpty()
        // game.attribute describes the current egg, which can differ from the selected companion.
        val text = bank.line(questionId, selected.speciesId, bank.attributeOf(selected.speciesId), "hatched", vars)
        return DialogueAnswer(questionId, text ?: "이 질문의 답변은 아직 준비 중이에요.", text != null)
    }

    companion object {
        val QUESTIONS = listOf(
            DialogueQuestion("ask_name", "너 이름이 뭐야?"),
            DialogueQuestion("ask_origin", "어디서 왔어?"),
            DialogueQuestion("ask_like", "뭐 좋아해?"),
            DialogueQuestion("ask_mood", "지금 기분 어때?"),
        )
    }
}
