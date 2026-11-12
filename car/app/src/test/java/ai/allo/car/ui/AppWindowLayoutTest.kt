package ai.allo.car.ui

import kotlin.test.*

class AppWindowLayoutTest {
    @Test fun `short app window places artwork beside text instead of clipping a vertical stack`() {
        val layout = DrivingWindowLayout.forContent(600f, 220f, 1f)
        assertTrue(layout.horizontal)
        assertTrue(layout.artSizeDp <= 220f)
        assertTrue(600f - layout.artSizeDp - 24f >= 300f)
    }
    @Test fun `portrait window keeps stacked composition and reserves readable text space`() {
        val layout = DrivingWindowLayout.forContent(320f, 260f, 1f)
        assertFalse(layout.horizontal)
        assertTrue(layout.artSizeDp + 118f <= 260f)
        assertFalse(layout.showFootnote)
    }
    @Test fun `larger fonts yield artwork space rather than hiding status below the window`() {
        val normal = DrivingWindowLayout.forContent(320f, 300f, 1f)
        val enlarged = DrivingWindowLayout.forContent(320f, 300f, 1.5f)
        assertTrue(enlarged.artSizeDp < normal.artSizeDp)
        assertTrue(enlarged.artSizeDp + 118f * 1.5f <= 300f)
    }
    @Test fun `temporary zero bounds during resize never yield a negative image size`() {
        for (width in listOf(0f, 200f, 320f, 600f, 1200f)) for (height in listOf(0f, 80f, 220f, 500f, 900f)) {
            val layout = DrivingWindowLayout.forContent(width, height, 1f)
            assertTrue(layout.artSizeDp >= 0f)
            assertTrue(layout.artSizeDp <= minOf(width, height))
        }
    }
}
