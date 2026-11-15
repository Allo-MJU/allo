package ai.allo.car.model

/** A destination conversation keeps the phone-selected car companion, never a local story guest. */
data class DestinationVoiceTarget(val sessionId: String, val subject: DialogueSubject) {
    fun matches(currentSessionId: String, currentSubject: DialogueSubject?): Boolean =
        sessionId == currentSessionId && subject == currentSubject
}
