package ai.allo.car.gleo

import ai.allo.car.navi.Guidance

/** Serializes route requests from recommendations and explicit phone travel requests. */
internal class DestinationHandoff(
    private val destinations: DestinationFlow,
    private val travel: TravelRequestFlow,
) {
    @Synchronized
    fun acceptDestination(
        guidance: Guidance,
        stillValid: (Destination) -> Boolean,
        request: (Destination) -> Boolean,
    ): AcceptResult {
        val result = destinations.accept(guidance, stillValid, request)
        // SDK guidance can remain IDLE after accepting a request; old offers must expire now.
        if (result is AcceptResult.Started) travel.reset()
        return result
    }

    @Synchronized
    fun acceptTravel(
        token: Long,
        index: Int,
        context: TravelRequestFlow.Context,
        guidance: Guidance,
        request: (Destination) -> Boolean,
    ): AcceptResult {
        val result = travel.accept(token, index, context, guidance, request)
        if (result is AcceptResult.Started) destinations.reset()
        return result
    }
}
