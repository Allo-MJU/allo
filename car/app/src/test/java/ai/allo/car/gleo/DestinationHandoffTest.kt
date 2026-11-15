package ai.allo.car.gleo

import ai.allo.car.model.TravelRequest
import ai.allo.car.navi.DestinationVisitTracker
import ai.allo.car.navi.Guidance
import ai.allo.car.voice.DestinationPrompt
import ai.allo.car.voice.DestinationRecognition
import ai.allo.car.voice.DestinationVoiceCommand
import ai.allo.car.voice.DestinationVoiceController
import ai.allo.car.voice.DestinationVoiceReply
import kotlin.test.*

class DestinationHandoffTest {
    private class Harness {
        val destinations = DestinationFlow()
        val travel = TravelRequestFlow()
        val handoff = DestinationHandoff(destinations, travel)
        val context = TravelRequestFlow.Context("session", true, false, true,
            TravelRequest("wish", "coast"), "city", true)
        val recommendation = assertIs<DestinationFlow.Offer.Made>(destinations.offer(null, "city"))
            .suggestion.destination
        val quest = assertIs<TravelRequestFlow.Offer.Made>(travel.offer(context, null))
        val requests = mutableListOf<Destination>()
        val tracker = DestinationVisitTracker()
        var succeeds = true
        // GUIDING/start/destination callbacks are deliberately withheld until after both accept attempts.
        var guidance = Guidance.IDLE
        val request: (Destination) -> Boolean = {
            tracker.expect(it)
            requests += it
            if (!succeeds) tracker.cancel()
            succeeds
        }
        fun acceptDestination() = handoff.acceptDestination(guidance, { true }, request)
        fun acceptTravel() = handoff.acceptTravel(quest.token, 0, context, guidance, request)
        fun assertVisit(expected: Destination) {
            guidance = Guidance.GUIDING
            tracker.start("session")
            // 222 m offset: inside the explicit expectation match, outside the catalog fallback.
            tracker.destination("session", expected.name, null, null, null,
                expected.latitude + 0.002, expected.longitude)
            val visit = assertNotNull(tracker.arrive("session", expected.name, 1000L, emptyList()))
            assertEquals(expected.placeId, visit.placeId)
        }
    }

    @Test fun `quest handoff invalidates recommendation before delayed guiding callback`() {
        val h = Harness()
        val spokenRevision = h.destinations.revision
        val accepted = h.quest.suggestions[0].destination
        assertIs<AcceptResult.Started>(h.acceptTravel())
        assertEquals(AcceptResult.NoOffer, h.acceptDestination())
        assertNotEquals(spokenRevision, h.destinations.revision)
        assertEquals(listOf(accepted), h.requests)
        h.assertVisit(accepted)
    }

    @Test fun `recommendation handoff invalidates quest token before delayed guiding callback`() {
        val h = Harness()
        assertIs<AcceptResult.Started>(h.acceptDestination())
        assertEquals(AcceptResult.NoOffer, h.acceptTravel())
        assertEquals(listOf(h.recommendation), h.requests)
        h.assertVisit(h.recommendation)
    }

    @Test fun `failed quest request preserves recommendation and its voice revision`() {
        val h = Harness()
        val spokenRevision = h.destinations.revision
        h.succeeds = false
        assertEquals(AcceptResult.NaviNotReady, h.acceptTravel())
        assertEquals(spokenRevision, h.destinations.revision)
        assertEquals(h.recommendation, h.destinations.pending())
        h.succeeds = true
        assertIs<AcceptResult.Started>(h.acceptDestination())
        h.assertVisit(h.recommendation)
    }

    @Test fun `failed recommendation request preserves quest offer`() {
        val h = Harness()
        h.succeeds = false
        assertEquals(AcceptResult.NaviNotReady, h.acceptDestination())
        h.succeeds = true
        assertEquals(AcceptResult.Started(h.quest.suggestions[0].destination), h.acceptTravel())
        h.assertVisit(h.quest.suggestions[0].destination)
    }

    private class Recognition : DestinationRecognition {
        lateinit var final: (String) -> Unit
        override fun start(onReady: () -> Unit, onFinal: (String) -> Unit, onFailure: (String) -> Unit) {
            final = onFinal
            onReady()
        }
        override fun close() = Unit
    }

    private class Prompt : DestinationPrompt {
        lateinit var done: () -> Unit
        var text = ""
        override fun speak(text: String, onDone: () -> Unit, onFailure: () -> Unit) {
            this.text = text
            done = onDone
        }
        override fun close() = Unit
    }

    @Test fun `late spoken yes cannot replace quest handoff while guidance is still idle`() {
        val h = Harness()
        val recognition = Recognition()
        val revision = h.destinations.revision
        val voice = DestinationVoiceController(
            createRecognition = { recognition }, createPrompt = { Prompt() },
            allowed = { revision == h.destinations.revision },
            execute = {
                h.acceptDestination()
                DestinationVoiceReply("안내를 요청했어요.")
            }, scheduleTimeout = { {} }, onState = {},
        )
        voice.start()
        assertTrue(voice.state.listening)
        assertIs<AcceptResult.Started>(h.acceptTravel())
        recognition.final("네")
        assertFalse(voice.state.busy)
        assertEquals(listOf(h.quest.suggestions[0].destination), h.requests)
    }

    @Test fun `successful spoken acceptance still plays its own confirmation`() {
        val h = Harness()
        val recognition = Recognition()
        val prompt = Prompt()
        var revision = h.destinations.revision
        val voice = DestinationVoiceController(
            createRecognition = { recognition }, createPrompt = { prompt },
            allowed = { revision == h.destinations.revision },
            execute = {
                assertEquals(DestinationVoiceCommand.ACCEPT, it)
                assertIs<AcceptResult.Started>(h.acceptDestination())
                // SessionManager advances the voice revision after its own successful acceptance.
                revision = h.destinations.revision
                DestinationVoiceReply("안내를 요청했어요.")
            }, scheduleTimeout = { {} }, onState = {},
        )
        voice.start()
        recognition.final("네")
        assertTrue(voice.state.busy)
        assertEquals("안내를 요청했어요.", prompt.text)
        prompt.done()
        assertFalse(voice.state.busy)
        assertEquals("안내를 요청했어요.", voice.state.message)
        assertEquals(AcceptResult.NoOffer, h.acceptTravel())
        assertEquals(listOf(h.recommendation), h.requests)
    }
}
