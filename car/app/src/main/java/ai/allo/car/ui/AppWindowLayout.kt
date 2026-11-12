package ai.allo.car.ui

/** Dimensions are the actual inset-free app content area, not the vehicle display. */
internal data class DrivingWindowLayout(
    val horizontal: Boolean,
    val artSizeDp: Float,
    val showFootnote: Boolean,
) {
    companion object {
        fun forContent(widthDp: Float, heightDp: Float, fontScale: Float): DrivingWindowLayout {
            val width = widthDp.coerceAtLeast(0f)
            val height = heightDp.coerceAtLeast(0f)
            val scale = fontScale.coerceAtLeast(1f)
            val horizontal = (width >= 960f * scale && width >= height * 1.1f) ||
                (height < 340f * scale && width >= 360f)
            val footnote = height >= (if (horizontal) 240f else 440f) * scale
            // Include card padding and pane gap, then give the remaining space to the character.
            val textHeight = 124f * scale + if (footnote) 72f * scale else 0f
            val artLimit = if (horizontal) minOf(width * .55f - 32f, height * .78f)
                else minOf(width - 48f, (height - textHeight - 72f) * .82f)
            return DrivingWindowLayout(horizontal, artLimit.coerceIn(0f, 720f), footnote)
        }
    }
}

/** Review screens reflow within the current window, never the whole display. */
internal data class ReviewWindowLayout(val stacked: Boolean, val artSizeDp: Float) {
    companion object {
        fun forContent(widthDp: Float, heightDp: Float): ReviewWindowLayout {
            val width = widthDp.coerceAtLeast(0f)
            val height = heightDp.coerceAtLeast(0f)
            val stacked = width < 760f
            val limit = if (stacked) minOf(width - 40f, height * .32f) else minOf(width * .36f - 32f, height - 32f)
            return ReviewWindowLayout(stacked, limit.coerceIn(0f, 340f))
        }
    }
}
