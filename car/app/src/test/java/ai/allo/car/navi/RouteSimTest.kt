package ai.allo.car.navi

import ai.allo.car.model.Turn
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RouteSimTest {
    private fun sim() = RouteSim.parse("right:220,left:560,uturn:900")!!

    @Test fun countsDownFromWhereItWasTurnedOn() {
        val s = sim()
        // 켠 때의 누적 거리가 0 이 아니어도 그때부터 센다
        assertEquals(listOf(Turn("right", 220), Turn("left", 560), Turn("uturn", 900)), s.turns(5_000.0))
        assertEquals(listOf(Turn("right", 20), Turn("left", 360), Turn("uturn", 700)), s.turns(5_200.0))
    }

    @Test fun passedTurnsDropAndNextLapFollows() {
        val s = sim()
        s.turns(0.0)
        // 950m: 세 회전을 다 지났다. 한 바퀴 = 900 + 300 = 1200m → 다음 바퀴 우회전은 1420m
        assertEquals(listOf(Turn("right", 470), Turn("left", 810), Turn("uturn", 1150)), s.turns(950.0))
    }

    @Test fun headingTurnsAtEachTurnPoint() {
        val s = RouteSim.parse("right:200,left:400", startHeading = 90.0)!!
        s.turns(0.0)
        fun near(expected: Double, at: Double) {
            val h = s.headingDeg(at)
            val d = ((h - expected + 540) % 360) - 180
            assertTrue("at $at: $h vs $expected", kotlin.math.abs(d) <= RouteSim.SWAY_DEG + 0.01)
        }
        near(90.0, 100.0)   // 출발
        near(180.0, 300.0)  // 우회전 뒤
        near(90.0, 500.0)   // 좌회전 뒤
    }

    @Test fun headingStaysInRange() {
        val s = RouteSim.parse("left:100")!!
        s.turns(0.0)
        for (m in 0..3000 step 50) {
            val h = s.headingDeg(m.toDouble())
            assertTrue("$m: $h", h >= 0.0 && h < 360.0)
        }
    }

    @Test fun badSpecIsRejected() {
        assertNull(RouteSim.parse(""))
        assertNull(RouteSim.parse("right"))
        assertNull(RouteSim.parse("fly:100"))
        assertNull(RouteSim.parse("right:-5"))
        assertNull(RouteSim.parse("right:abc"))
    }
}
