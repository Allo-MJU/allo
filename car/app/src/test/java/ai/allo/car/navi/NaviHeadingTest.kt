package ai.allo.car.navi

import ai.allo.car.model.VehicleSnapshot
import ai.allo.car.sync.FirebaseRest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

/** schema.md 3.3 headingDeg: 0 이상 360 미만, 소수 첫째 자리 반올림, NaN·무한대·미수신이면 null */
class NaviHeadingTest {
    @Test fun `normal values pass through`() {
        assertEquals(0.0, NaviHeading.deg(0.0))
        assertEquals(87.5, NaviHeading.deg(87.5))
        assertEquals(359.9, NaviHeading.deg(359.9))
    }

    @Test fun `negative values wrap by adding 360`() {
        assertEquals(270.0, NaviHeading.deg(-90.0))
        assertEquals(359.5, NaviHeading.deg(-0.5))
        assertEquals(10.0, NaviHeading.deg(-710.0))
        assertEquals(0.0, NaviHeading.deg(-360.0))
    }

    @Test fun `values of 360 or more wrap`() {
        assertEquals(0.0, NaviHeading.deg(360.0))
        assertEquals(30.0, NaviHeading.deg(390.0))
        assertEquals(1.5, NaviHeading.deg(721.5))
    }

    @Test fun `rounds to one decimal place`() {
        assertEquals(87.5, NaviHeading.deg(87.46))
        assertEquals(87.4, NaviHeading.deg(87.44))
        assertEquals(12.3, NaviHeading.deg(12.345678))
        assertEquals(0.0, NaviHeading.deg(359.96))   // 반올림하면 360.0 → 범위 밖이라 0.0
        assertEquals(0.0, NaviHeading.deg(-0.01))
    }

    @Test fun `NaN infinity and missing give null`() {
        assertNull(NaviHeading.deg(Double.NaN))
        assertNull(NaviHeading.deg(Double.POSITIVE_INFINITY))
        assertNull(NaviHeading.deg(Double.NEGATIVE_INFINITY))
        assertNull(NaviHeading.deg(null))
    }

    private fun snapshot(headingDeg: Double?) = VehicleSnapshot(
        ts = 1L, gear = "D", speedKph = 30.0, distanceM = 10.0, harshBrake = 0, harshSteer = 0,
        wiperLevel = 0, headlightOn = false, seatRow2 = true, etaSec = null, envTags = emptyList(),
        headingDeg = headingDeg, capabilities = listOf("eta"),
    )

    @Test fun `snapshot serializes headingDeg as a number`() {
        val json = FirebaseRest("").json
        val obj = Json.parseToJsonElement(json.encodeToString(snapshot(87.5))).jsonObject
        assertEquals(87.5, obj.getValue("headingDeg").jsonPrimitive.double)
        for (k in listOf("lat", "lng", "latitude", "longitude", "address")) assertFalse(k in obj, k)
    }

    @Test fun `snapshot sends null headingDeg when unknown`() {
        val json = FirebaseRest("").json
        val text = json.encodeToString(snapshot(null))
        val obj = Json.parseToJsonElement(text).jsonObject
        assertEquals(JsonNull, obj.getValue("headingDeg"))
        assert(""""headingDeg":null""" in text)
    }
}
