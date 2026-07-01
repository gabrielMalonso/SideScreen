package com.sidescreen.app

data class PointerTuning(
    val mouseSensitivity: Float,
    val scrollSensitivity: Float,
    val naturalScroll: Boolean,
) {
    fun relative(
        dx: Float,
        dy: Float,
    ): Pair<Float, Float> = dx * mouseSensitivity to dy * mouseSensitivity

    fun wheel(
        rawHorizontal: Float,
        rawVertical: Float,
    ): Pair<Float, Float> {
        val direction = if (naturalScroll) -1f else 1f
        return rawHorizontal * WHEEL_UNIT * scrollSensitivity * direction to
            rawVertical * WHEEL_UNIT * scrollSensitivity * direction
    }

    companion object {
        const val MIN_SENSITIVITY = 0.25f
        const val MAX_SENSITIVITY = 3.0f
        const val DEFAULT_MOUSE_SENSITIVITY = 1.0f
        const val DEFAULT_SCROLL_SENSITIVITY = 1.0f
        private const val WHEEL_UNIT = 48f

        fun normalized(
            mouseSensitivity: Float,
            scrollSensitivity: Float,
            naturalScroll: Boolean,
        ): PointerTuning =
            PointerTuning(
                mouseSensitivity = mouseSensitivity.coerceIn(MIN_SENSITIVITY, MAX_SENSITIVITY),
                scrollSensitivity = scrollSensitivity.coerceIn(MIN_SENSITIVITY, MAX_SENSITIVITY),
                naturalScroll = naturalScroll,
            )
    }
}
