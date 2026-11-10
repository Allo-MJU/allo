package ai.allo.car.navi

import ai.allo.car.model.Turn
import ai.allo.car.model.VehicleSnapshot
import ai.allo.car.sync.FirebaseRest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** schema.md 3.3 turns: 다섯 가지 type, inM 반올림 0 이상 정수, 가까운 순 최대 3개, 안내 중이 아니면 빈 목록 */
class NaviTurnsTest {
    @Test fun `turn type names map to the five wire types`() {
        assertEquals("left", NaviTurns.type("TURN_LEFT"))
        assertEquals("left", NaviTurns.type("TURN_SHARP_L"))
        assertEquals("right", NaviTurns.type("TURN_RIGHT"))
        assertEquals("right", NaviTurns.type("TURN_SHARP_R"))
        assertEquals("uturn", NaviTurns.type("TURN_UTURN"))
        for (n in listOf("TURN_KEEP_L", "TURN_ENTER_IC_L", "TURN_EXIT_IC_L")) assertEquals("keepLeft", NaviTurns.type(n))
        for (n in listOf("TURN_KEEP_R", "TURN_ENTER_IC_R", "TURN_EXIT_IC_R")) assertEquals("keepRight", NaviTurns.type(n))
    }

    @Test fun `other guidance types are dropped`() {
        for (n in listOf(
            "TURN_UNKNOWN", "TURN_STRAIGHT", "TURN_ENTER_IC_C", "TURN_EXIT_IC_C", "TURN_ENTER_UNDER_R",
            "TURN_AVOID_OVER_L", "TURN_ENTER_ROUNDABOUT_02", "TURN_EXIT_ROUNDABOUT", "TURN_WAY", "TURN_ARRIVE",
            "TURN_TUNNEL", "TURN_DEVIDE_MERGE", "TURN_TOLL", "TURN_ENTER_SERVICEAREA", "TURN_RESTAREA", "", null,
        )) assertNull(NaviTurns.type(n), "$n")
    }

    @Test fun `distance is rounded to a non-negative integer`() {
        assertEquals(230, NaviTurns.inM(229.5))
        assertEquals(229, NaviTurns.inM(229.49))
        assertEquals(0, NaviTurns.inM(-3.0))
        assertEquals(0, NaviTurns.inM(0.4))
        assertNull(NaviTurns.inM(Double.NaN))
        assertNull(NaviTurns.inM(Double.POSITIVE_INFINITY))
    }

    @Test fun `keeps nearest three supported turns in ascending order`() {
        val raw = listOf(
            "TURN_UTURN" to 910.2,
            "TURN_STRAIGHT" to 50.0,
            "TURN_RIGHT" to 229.6,
            "TURN_TUNNEL" to 10.0,
            "TURN_KEEP_L" to 1500.0,
            "TURN_EXIT_IC_R" to 2400.0,
        )
        assertEquals(
            listOf(Turn("right", 230), Turn("uturn", 910), Turn("keepLeft", 1500)),
            NaviTurns.turns(guiding = true, raw = raw),
        )
    }

    @Test fun `not guiding gives empty list`() {
        assertEquals(emptyList(), NaviTurns.turns(guiding = false, raw = listOf("TURN_LEFT" to 100.0)))
        assertEquals(emptyList(), NaviTurns.turns(guiding = true, raw = emptyList()))
    }

    private fun snapshot(turns: List<Turn>) = VehicleSnapshot(
        ts = 1L, gear = "D", speedKph = 30.0, distanceM = 10.0, harshBrake = 0, harshSteer = 0,
        wiperLevel = 0, headlightOn = false, seatRow2 = true, etaSec = null, envTags = emptyList(),
        turns = turns, capabilities = listOf("eta", "turns"),
    )

    @Test fun `snapshot serializes turns as type and inM only`() {
        val json = FirebaseRest("").json
        val obj = Json.parseToJsonElement(json.encodeToString(snapshot(listOf(Turn("right", 230), Turn("uturn", 910))))).jsonObject
        val turns = obj.getValue("turns").jsonArray
        assertEquals(2, turns.size)
        assertEquals(setOf("type", "inM"), turns[0].jsonObject.keys)
        assertEquals("""{"type":"right","inM":230}""", turns[0].toString())
        assertFalse("description" in turns[0].jsonObject)
    }

    @Test fun `snapshot sends empty turns when not guiding`() {
        val json = FirebaseRest("").json
        val obj = Json.parseToJsonElement(json.encodeToString(snapshot(emptyList()))).jsonObject
        assertTrue(obj.getValue("turns").jsonArray.isEmpty())
    }
}
