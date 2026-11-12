package ai.allo.car.model
import kotlin.test.*
class DrivingMotionTest {
    private fun DrivingMotionTracker.speed(speed: Double, time: Long, gear: String = "D") = accept(speed, time, time, gear)
    @Test fun `stopped and increasing speed select bounded running rates`() {
        val t = DrivingMotionTracker()
        assertEquals(0f, t.speed(0.0, 0).playbackRate)
        val slow = t.speed(10.0, 200); val medium = t.speed(50.0, 400); val fast = t.speed(120.0, 600)
        assertTrue(slow.fresh); assertTrue(slow.playbackRate > 0f)
        assertTrue(medium.playbackRate > slow.playbackRate); assertTrue(fast.playbackRate > medium.playbackRate)
        assertTrue(t.speed(250.0, 800).playbackRate <= 2f)
    }
    @Test fun `sharp deceleration emits once and uses receive time for animation`() {
        val t = DrivingMotionTracker()
        for (time in 0L..400L step 200L) t.speed(60.0,time)
        assertEquals(0L, t.accept(45.0,600,650,"D").brakeSerial) // first candidate awaits confirmation
        val event = t.accept(30.0, 800, 850, "D")
        assertEquals(1L, event.brakeSerial); assertEquals(850L, event.brakeAtMs)
        assertEquals(1L, t.speed(20.0, 1000).brakeSerial); assertEquals(1L, t.speed(0.0, 1200).brakeSerial)
    }
    @Test fun `gentle deceleration and small jitter never trigger falling`() {
        val t = DrivingMotionTracker(); t.speed(60.0, 0); t.speed(59.0, 10); t.speed(60.0, 100); t.speed(58.0, 200); t.speed(55.0, 1000)
        assertEquals(0L, t.state(1000, "D").brakeSerial)
    }
    @Test fun `high rate samples accumulate sufficient window for abrupt stop`() {
        val t = DrivingMotionTracker()
        for (time in 0L..100L step 25L) t.speed(30.0 - time * .04,time)
        assertEquals(0L,t.state(100,"D").brakeSerial) // no decision from a tiny window
        for (time in 125L..500L step 25L) t.speed(30.0 - time * .04,time)
        assertEquals(1L,t.state(500,"D").brakeSerial)
    }
    @Test fun `long continuous braking never retriggers after cooldown`() {
        val t = DrivingMotionTracker(); t.speed(100.0, 0)
        for (i in 1..6) t.speed(100.0-i*15, i*500L)
        assertEquals(1L, t.state(3000,"D").brakeSerial)
    }
    @Test fun `steady recovery then another braking event emits again`() {
        val t = DrivingMotionTracker()
        for (time in 0L..400L step 200L) t.speed(60.0,time)
        t.speed(40.0,600); t.speed(20.0,800)
        assertEquals(1L,t.state(800,"D").brakeSerial)
        for (time in 1000L..3000L step 200L) t.speed(20.0,time)
        t.speed(10.0,3200)
        assertEquals(2L,t.speed(0.0,3400).brakeSerial)
    }
    @Test fun `stale signal stops motion and clears event then rebaselines`() {
        val t = DrivingMotionTracker()
        for (time in 0L..400L step 200L) t.speed(60.0,time)
        t.speed(40.0,600); t.speed(20.0,800)
        val stale = t.state(2300, "D")
        assertFalse(stale.fresh); assertEquals(0f, stale.playbackRate); assertNull(stale.brakeAtMs)
        assertNull(t.speed(0.0, 2400).brakeAtMs); assertEquals(1L, t.state(2400,"D").brakeSerial)
    }
    @Test fun `invalid readings stop motion without manufacturing deceleration`() {
        for (bad in listOf(Double.NaN, Double.POSITIVE_INFINITY, -1.0, 401.0)) {
            val t = DrivingMotionTracker(); t.speed(60.0,0)
            assertFalse(t.speed(bad,100).fresh); assertEquals(0L, t.speed(0.0,200).brakeSerial)
        }
    }
    @Test fun `out of order and duplicate samples preserve newest valid reading`() {
        val t = DrivingMotionTracker(); t.speed(60.0,100); t.speed(55.0,1000)
        assertEquals(55.0, t.accept(0.0,500,1100,"D").speedKph)
        assertEquals(55.0, t.accept(0.0,1000,1200,"D").speedKph)
        assertEquals(0L, t.state(1200,"D").brakeSerial); assertFalse(t.state(2500,"D").fresh)
    }
    @Test fun `park reverse and unknown gear reset braking baseline`() {
        for (gear in listOf("P","R","N","?")) {
            val t = DrivingMotionTracker(); t.speed(60.0,0)
            assertFalse(t.speed(40.0,100,gear).fresh); assertEquals(0L, t.speed(0.0,200).brakeSerial)
        }
    }
    @Test fun `gear switch without speed callback invalidates state`() {
        val t = DrivingMotionTracker(); t.speed(60.0,0)
        assertFalse(t.state(50,"P").fresh); assertFalse(t.state(60,"D").fresh)
        assertEquals(0L, t.speed(0.0,100).brakeSerial)
    }
    @Test fun `stale or future sensor timestamps cannot animate`() {
        val t = DrivingMotionTracker()
        assertFalse(t.accept(60.0,0,2000,"D").fresh); assertFalse(t.accept(60.0,3000,2000,"D").fresh)
        assertEquals(0L, t.speed(0.0,2200).brakeSerial)
    }
    @Test fun `explicit invalidation preserves event identity but cancels animation`() {
        val t=DrivingMotionTracker()
        for (time in 0L..400L step 200L) t.speed(60.0,time)
        t.speed(40.0,600); t.speed(20.0,800); t.invalidate()
        assertFalse(t.state(900,"D").fresh); assertNull(t.state(900,"D").brakeAtMs); assertEquals(1L,t.state(900,"D").brakeSerial)
    }
    @Test fun `harsh brake result is invariant across continuous sensor sampling rates`() {
        for (decel in listOf(12.0, 14.0, 20.0)) for (interval in listOf(100L, 200L, 500L)) {
            val t = DrivingMotionTracker()
            t.speed(100.0, 0)
            for (time in interval..2_000L step interval) t.speed(100.0 - decel * time / 1000.0, time)
            assertEquals(1L, t.state(2_000, "D").brakeSerial, "$decel kph/s sampled every $interval ms")
        }
    }
    @Test fun `deceleration just below threshold never triggers at any supported sample rate`() {
        for (interval in listOf(100L, 200L, 500L)) {
            val t = DrivingMotionTracker()
            t.speed(100.0, 0)
            for (time in interval..2_000L step interval) t.speed(100.0 - 11.9 * time / 1000.0, time)
            assertEquals(0L, t.state(2_000, "D").brakeSerial, "sample interval=$interval")
        }
    }
    @Test fun `oscillating noise and gentle drift cannot accumulate into a false brake`() {
        for (interval in listOf(100L, 200L, 500L)) {
            val t = DrivingMotionTracker()
            t.speed(60.0, 0)
            for (i in 1..20) t.speed(60.0 - i * interval / 1000.0 + if (i % 2 == 0) .5 else -.5, i * interval)
            assertEquals(0L, t.state(20 * interval, "D").brakeSerial)
        }
    }

    @Test fun `quantized gentle braking with bunched samples does not trigger`() {
        val t = DrivingMotionTracker()
        val samples = listOf(0L to 40.0, 200L to 39.0, 400L to 37.0, 600L to 36.0,
            800L to 35.0, 1000L to 33.0, 1200L to 32.0, 1400L to 31.0,
            1600L to 29.0, 1800L to 28.0, 2000L to 27.0, 2200L to 26.0,
            2300L to 25.0, 2400L to 23.0, 2600L to 22.0, 3000L to 21.0,
            3200L to 19.0, 3400L to 18.0, 3600L to 16.0, 3800L to 15.0,
            4000L to 14.0, 4200L to 12.0, 4400L to 11.0, 4600L to 9.0,
            4800L to 8.0, 5000L to 7.0, 5200L to 5.0, 5400L to 4.0,
            5600L to 2.0, 5800L to 1.0, 6000L to 0.0)
        for ((time, speed) in samples) t.speed(speed,time)
        assertEquals(0L,t.state(6000,"D").brakeSerial)
    }
    @Test fun `one low sensor spike followed by recovery never plays a fall`() {
        val t=DrivingMotionTracker()
        for (time in 0L..1000L step 200L) t.speed(60.0,time)
        t.speed(10.0,1200); t.speed(60.0,1400); t.speed(60.0,1600)
        assertEquals(0L,t.state(1600,"D").brakeSerial)
    }
    @Test fun `real abrupt stop gets a single event within its six tenths of a second`() {
        val t=DrivingMotionTracker()
        for (time in 0L..1000L step 200L) t.speed(85.0,time)
        t.speed(55.0,1200); t.speed(26.0,1400); t.speed(0.0,1600)
        assertEquals(1L,t.state(1600,"D").brakeSerial)
        assertTrue(t.state(1600,"D").brakeAtMs!! <= 1600L)
        for (time in 1800L..4000L step 200L) t.speed(0.0,time)
        assertEquals(1L,t.state(4000,"D").brakeSerial)
    }

    @Test fun `recorded Pleos callbacks produce one hard brake and no gentle brake in both runs`() {
        val lines = javaClass.getResourceAsStream("/driving-motion-pleos-samples.csv")!!.bufferedReader().use { it.readLines() }
        val runs = lines.filterNot { it.startsWith("#") || it.isBlank() }.map { it.split(',') }.groupBy { it[0] }
        assertEquals(setOf("1", "2"),runs.keys)
        for ((run, rows) in runs) {
            val tracker=DrivingMotionTracker()
            var previousSerial=0L
            val eventTimes=mutableListOf<Long>()
            for (row in rows) {
                val sampleAt=row[1].toLong()
                val result=tracker.accept(row[3].toDouble(), sampleAt, row[2].toLong(), row[4])
                if (result.brakeSerial > previousSerial) eventTimes.add(sampleAt)
                previousSerial=result.brakeSerial
            }
            val peak=rows.indexOfFirst { it[3].toDouble() > 84.0 }
            val zeroAfterPeak=rows.drop(peak).first { it[3].toDouble() < .8 }[1].toLong()
            assertEquals(1,eventTimes.size,"run $run must not add an event during gentle stop")
            assertTrue(eventTimes.single() in rows[peak][1].toLong()..zeroAfterPeak,"run $run event must be during hard stop")
            assertEquals("P",rows.last()[4])
            assertEquals(0.0,rows.last()[3].toDouble())
        }
    }

}
