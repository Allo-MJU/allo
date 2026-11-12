package ai.allo.car.model
import kotlinx.serialization.json.*
import kotlinx.serialization.encodeToString
import java.io.File
import org.junit.Assert.*
import org.junit.Test

class FishingControllerTest {
    private fun game(state: String = "ready", lease: String = "l", revision: Long = 1, receipt: String? = null) =
        GameState(ts = 1, contractVersion = 2, gameRevision = 1,
            companion = CompanionDisplay("d", revision, "road_sprout", "car"),
            fishing = FishingSnapshot(1, lease, "d", revision, if (state == "ready") "" else "a", 0,
                state, 35000, 60000, 1, if (state == "reward") "관찰 1" else null, receipt))
    private fun raw(field: String = "state", value: JsonElement = JsonPrimitive("running")): JsonObject {
        val root = Json.parseToJsonElement("""{"ts":1,"stage":"hatched","contractVersion":2,"gameRevision":1,
            "companion":{"displayId":"d","displayRevision":1,"speciesId":"road_sprout","location":"car"},
            "fishing":{"version":1,"leaseId":"l","displayId":"d","displayRevision":1,"activityId":"a","cycle":1,
            "state":"running","elapsedMs":35000,"targetMs":60000,"totalRecords":0}}""").jsonObject.toMutableMap()
        root["fishing"] = JsonObject(root["fishing"]!!.jsonObject + (field to value)); return JsonObject(root)
    }
    @Test fun parsesPhoneProgressWithoutPrediction() {
        val g = GameSnapshotReader.parse(raw())!!
        assertEquals(35, g.fishing!!.display().elapsedSeconds)
        assertEquals(PleosRoute.Fishing, g.fishing!!.route()); assertNull(g.fishing!!.display().rewardName)
    }
    @Test fun invalidCapabilityAndCrossSelectionFailClosed() {
        for ((field, value) in listOf("version" to JsonPrimitive(2), "targetMs" to JsonPrimitive(0),
            "elapsedMs" to JsonPrimitive(60001), "cycle" to JsonPrimitive("1"), "displayRevision" to JsonPrimitive(2),
            "displayId" to JsonPrimitive("other"), "state" to JsonPrimitive("mystery"), "activityId" to JsonPrimitive(""))) {
            val g = GameSnapshotReader.parse(raw(field, value))!!
            assertNull(field, g.fishing); assertTrue(field, "fishing" in g.invalidBlocks); assertNotNull(g.companion)
        }
    }
    @Test fun missingCapabilityAndPermissionCannotSend() {
        val c = FishingController { "r" }
        assertNull(c.request("s", GameState(), true, "start", 1))
        assertNull(c.request("s", game().copy(fishing = null), true, "start", 1))
        assertNull(c.request("s", game(), false, "start", 1))
        assertNull(c.request("s", game().copy(companion = null), true, "start", 1))
    }
    @Test fun retryUsesSameIdOnlyAfterTimeoutAndNumericPayload() {
        val c = FishingController { "r" }; val first = c.request("s", game(), true, "start", 100)!!
        assertNull(c.request("s", game(), true, "start", 200)); assertNull(c.retry("s", game(), true, 10099))
        assertEquals(first, c.retry("s", game(), true, 10100)); assertFalse(c.ui.unconfirmed)
        val payload = fishingRequestEvent(first, 12)["payload"]!!.jsonObject
        assertFalse(payload["displayRevision"]!!.jsonPrimitive.isString)
        assertEquals("", payload["activityId"]!!.jsonPrimitive.content)
    }
    @Test fun matchingReceiptCanAdvanceActivityButUnrelatedReceiptCannotConfirm() {
        val c = FishingController { "r" }; c.request("s", game(), true, "start", 0)
        c.observe("s", game(receipt = "wrong"), true, 1); assertNotNull(c.ui.pending)
        c.observe("s", game("running", receipt = "r"), true, 2); assertNull(c.ui.pending)
    }
    @Test fun sessionLeaseSelectionOrDisconnectDropsPendingWithoutReplay() {
        for (mode in 0..3) {
            val c = FishingController { "r" }; c.request("s", game(), true, "start", 0)
            c.observe(if (mode == 0) "new" else "s", game(lease = if (mode == 1) "new" else "l",
                revision = if (mode == 2) 2 else 1), mode != 3, 11000)
            assertNull(c.ui.pending); assertNull(c.retry("s", game(), true, 12000))
        }
    }
    @Test fun stateActionsAndRoutingRespectDrivingAndDisconnectPriority() {
        for ((state, action, route) in listOf(Triple("running", "pause", PleosRoute.Fishing),
            Triple("paused", "resume", PleosRoute.Paused), Triple("saveFailed", "retry", PleosRoute.SaveFailed),
            Triple("reward", "pause", PleosRoute.Reward))) {
            val c = FishingController { "r" }; val g = game(state)
            assertNotNull(c.request("s", g, true, action, 0))
            assertEquals(route, PleosFlow.route(true, true, false, true, true, false, g))
            assertEquals(PleosRoute.Driving, PleosFlow.route(true, false, false, true, true, false, g))
            assertEquals(PleosRoute.Disconnected, PleosFlow.route(true, true, false, true, false, false, g))
        }
        assertNull(FishingController().request("s", game("saving"), true, "retry", 0))
        assertNull(FishingController().request("s", game("running"), true, "start", 0))
    }
    @Test fun rewardNeedsCommittedNameAndCount() {
        val g = GameSnapshotReader.parse(raw("state", JsonPrimitive("reward")))!!
        assertNull(g.fishing); assertTrue("fishing" in g.invalidBlocks)
    }
    @Test fun sharedPhoneFixtureReadsAndProducesMatchingVehicleRequest() {
        val fixtureFile = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }
            .map { File(it, "data/fixtures/fishing-v1.json") }.first { it.isFile }
        val fixture = Json.parseToJsonElement(fixtureFile.readText()).jsonObject
        val g = GameSnapshotReader.parse(fixture["game"]!!.jsonObject)!!
        assertEquals("display-example", g.companion!!.displayId)
        assertEquals(35000L, g.fishing!!.elapsedMs)
        assertEquals(PleosRoute.Fishing, PleosFlow.route(true, true, false, true, true, false, g))
        val c = FishingController { "pause-example" }
        val request = c.request("fixture-session", g, true, "pause", 0)!!
        assertEquals(fixture["request"], fishingRequestEvent(request, fixture["request"]!!.jsonObject["ts"]!!.jsonPrimitive.long))
        val presence = FishingPresence(leaseId = "lease-example", epoch = "car-process-example",
            sequence = 10, active = true, parkedAllowed = true)
        val wire = Json { encodeDefaults = true }.encodeToString(presence)
        assertEquals(fixture["presence"], Json.parseToJsonElement(wire))
    }
    @Test fun failedInitialSaveCanRetryWithoutInventingActivity() {
        val root = raw("state", JsonPrimitive("saveFailed")).toMutableMap()
        root["fishing"] = JsonObject(root["fishing"]!!.jsonObject + ("activityId" to JsonPrimitive("")))
        val g = GameSnapshotReader.parse(JsonObject(root))!!
        assertNotNull(g.fishing)
        val request = FishingController { "retry" }.request("s", g, true, "retry", 1)!!
        assertEquals("", request.activityId)
    }
    @Test fun parkedHomeCanBeViewedWithoutChangingPhoneActivity() {
        val g = game("running")
        assertEquals(PleosRoute.Home, PleosFlow.route(true, true, false, true, true, false, g, dismissFishing = true))
        assertEquals("running", g.fishing!!.state)
    }

    @Test fun confirmedSaveFailureUnlocksStorageRetryInsteadOfRepeatingStart() {
        val c = FishingController { "r" }
        c.request("s", game(), true, "start", 1)
        val failed = game("saveFailed").let { it.copy(fishing = it.fishing!!.copy(activityId = "")) }
        c.observe("s", failed, true, 2)
        assertNull(c.ui.pending)
        assertEquals("retry", c.request("s", failed, true, "retry", 3)!!.action)
        c.observe("s", failed, true, 4)
        assertNotNull(c.ui.pending) // The old failure does not acknowledge a new retry.
        assertNull(c.request("s", failed, true, "retry", 5))
        assertNotNull(c.retry("s", failed, true, 10003))
    }

    @Test fun localRevisionLivenessExpiresAndDuplicateSnapshotsNeverRenewIt() {
        val f = FishingFreshness()
        assertTrue(f.observe(100, 0))
        assertTrue(f.observe(100, 4999))
        assertFalse(f.observe(100, 5000))
        assertTrue(f.observe(101, 5001))
        assertFalse(f.isFresh(4000))
        assertTrue(f.isFresh(9999))
    }
    @Test fun reconnectRequiresAdvancingRevisionAndInvalidRevisionFailsClosed() {
        val f = FishingFreshness()
        assertTrue(f.observe(100, 0)); f.disconnect()
        assertFalse(f.observe(100, 1)); assertTrue(f.observe(101, 2))
        assertFalse(f.observe(99, 3)); assertFalse(f.observe(null, 4))
        assertFalse(f.observe(-1, 5)); assertFalse(f.observe(102, -1))
        assertTrue(f.observe(102, 6))
    }

}
