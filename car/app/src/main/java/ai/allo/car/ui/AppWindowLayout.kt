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
            val horizontal = height < 340f * scale && width >= 360f
            val footnote = height >= (if (horizontal) 200f else 340f) * scale
            // Reserve the actual title + two status lines before assigning space to artwork.
            val textHeight = 118f * scale + if (footnote) 64f * scale else 0f
            val artLimit = if (horizontal) minOf(width * .32f, height) else minOf(width, (height - textHeight).coerceAtLeast(0f))
            val preferred = if (width < 560f) 160f else 220f
            return DrivingWindowLayout(horizontal, minOf(preferred, artLimit), footnote)
        }
    }
}
