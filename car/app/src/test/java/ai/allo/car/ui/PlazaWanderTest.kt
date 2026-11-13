package ai.allo.car.ui

import kotlin.math.abs
import org.junit.Assert.*
import org.junit.Test

class PlazaWanderTest {
    @Test fun `all six friends stay on the lawn in both layouts`() {
        for (compact in listOf(false, true)) for (index in 0..5) for (tick in 0..2400) {
            val pose = plazaWanderPose(index, tick * .1f, compact)
            assertTrue(pose.x in .15f.. .85f)
            assertTrue(pose.y in (if (compact) .28f else .38f).. .88f)
        }
    }

    @Test fun `each friend walks rests and changes direction without jumping`() {
        for (compact in listOf(false, true)) for (index in 0..5) {
            val samples = (0..6000).map { plazaWanderPose(index, it * .01f, compact) }
            assertTrue(samples.any { it.moving })
            assertTrue(samples.any { !it.moving })
            assertTrue(samples.any { it.moving && it.facingLeft })
            assertTrue(samples.any { it.moving && !it.facingLeft })
            samples.zipWithNext().forEach { (a, b) ->
                assertTrue("x teleport at friend $index", abs(a.x - b.x) < .001f)
                assertTrue("y teleport at friend $index", abs(a.y - b.y) < .001f)
                if (!a.moving && !b.moving) {
                    assertEquals(a.x, b.x, 0f)
                    assertEquals(a.y, b.y, 0f)
                }
            }
        }
    }

    @Test fun `friends have distinct routes and asynchronous rests`() {
        for (compact in listOf(false, true)) for (tick in 0..1200) {
            val poses = (0..5).map { plazaWanderPose(it, tick * .1f, compact) }
            for (i in poses.indices) for (j in i + 1 until poses.size) {
                val a = poses[i]
                val b = poses[j]
                assertTrue(abs(a.x - b.x) > .14f || abs(a.y - b.y) > .14f)
            }
        }
        val initial = (0..5).map { plazaWanderPose(it, 0f, false).moving }
        assertTrue(initial.contains(true) && initial.contains(false))
    }

    @Test fun `invalid clocks remain finite and repeated calls deterministic`() {
        for (time in listOf(-10f, Float.NaN, Float.POSITIVE_INFINITY, 0f, 17.3f)) {
            val pose = plazaWanderPose(0, time, false)
            assertTrue(pose.x.isFinite() && pose.y.isFinite())
            assertEquals(pose, plazaWanderPose(0, time, false))
        }
    }

    @Test fun `sprite and name rectangles stay inside responsive garden viewport`() {
        for (width in listOf(360f, 420f, 600f, 699f, 700f, 785f, 1440f)) {
            val height = gardenHeight(width)
            for (tick in 0..2400) for (index in 0..5) {
                val rect = residentRect(width, index, tick * .1f)
                assertTrue("left clipped: width=$width friend=$index time=${tick * .1f}", rect.left >= 0f)
                assertTrue("right clipped: width=$width friend=$index time=${tick * .1f}", rect.right <= width)
                assertTrue("header overlap: width=$width friend=$index time=${tick * .1f}", rect.top >= 76f)
                assertTrue("name clipped: width=$width friend=$index time=${tick * .1f}", rect.bottom <= height)
            }
        }
    }

    @Test fun `sprite and name rectangles never overlap at supported responsive widths`() {
        for (width in listOf(360f, 420f, 600f, 699f, 700f, 785f, 1440f)) {
            for (tick in 0..2400) {
                val rectangles = (0..5).map { residentRect(width, it, tick * .1f) }
                for (i in rectangles.indices) for (j in i + 1 until rectangles.size) {
                    val a = rectangles[i]
                    val b = rectangles[j]
                    val horizontalOverlap = minOf(a.right, b.right) - maxOf(a.left, b.left)
                    val verticalOverlap = minOf(a.bottom, b.bottom) - maxOf(a.top, b.top)
                    assertTrue(
                        "Overlapping sprite/name targets: width=$width friends=$i/$j time=${tick * .1f} " +
                            "overlap=$horizontalOverlap x $verticalOverlap",
                        horizontalOverlap <= 0f || verticalOverlap <= 0f,
                    )
                }
            }
        }
    }

    private data class ResidentRect(val left: Float, val top: Float, val right: Float, val bottom: Float)

    // Geometry contract of PlazaScene. Includes the complete touch target and 32dp name label,
    // so routes cannot pass through another friend's label even when their feet remain apart.
    private fun lawnHeight(width: Float): Float = if (width < 700f)
        (width * 1.4f).coerceIn(660f, 850f) else (width * .53f).coerceIn(440f, 650f)

    private fun gardenHeight(width: Float): Float = lawnHeight(width) + 100f

    private fun residentRect(width: Float, index: Int, seconds: Float): ResidentRect {
        val compact = width < 700f
        val position = plazaWanderPose(index, seconds, compact)
        val baseSize = if (compact) (width * .25f).coerceIn(84f, 150f)
            else (width * .145f).coerceIn(120f, 196f)
        val petSize = baseSize * (.85f + position.y * .20f)
        val left = (width * position.x - petSize / 2f).coerceIn(0f, width - petSize)
        val top = 100f + (lawnHeight(width) * position.y - petSize * .86f).coerceAtLeast(76f)
        return ResidentRect(left, top, left + petSize, top + petSize + 32f)
    }

}
