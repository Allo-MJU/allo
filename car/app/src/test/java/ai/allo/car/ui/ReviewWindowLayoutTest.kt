package ai.allo.car.ui

import org.junit.Assert.*
import org.junit.Test

class ReviewWindowLayoutTest {
    @Test fun splitWindowStacksAndLeavesRoomForInformation() {
        val layout = ReviewWindowLayout.forContent(420f, 720f)
        assertTrue(layout.stacked)
        assertTrue(layout.artSizeDp <= 720f * .32f)
    }
    @Test fun wideShortWindowKeepsArtworkInsideItsPane() {
        val layout = ReviewWindowLayout.forContent(1000f, 260f)
        assertFalse(layout.stacked)
        assertTrue(layout.artSizeDp <= 228f)
    }
    @Test fun resizeTransientZeroBoundsNeverProducesNegativeSize() {
        assertEquals(0f, ReviewWindowLayout.forContent(0f, 0f).artSizeDp, 0f)
    }
}
