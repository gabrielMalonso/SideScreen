package com.sidescreen.app

import org.junit.Assert.assertEquals
import org.junit.Test

class PointerTuningTest {
    @Test
    fun clampsSensitivityValues() {
        val tuning =
            PointerTuning.normalized(
                mouseSensitivity = 10f,
                scrollSensitivity = -1f,
                naturalScroll = false,
            )

        assertEquals(3.0f, tuning.mouseSensitivity)
        assertEquals(0.25f, tuning.scrollSensitivity)
    }

    @Test
    fun scalesRelativePointerMovement() {
        val tuning = PointerTuning.normalized(1.5f, 1f, false)

        val (dx, dy) = tuning.relative(4f, -2f)

        assertEquals(6f, dx)
        assertEquals(-3f, dy)
    }

    @Test
    fun appliesScrollSensitivityAndNaturalDirection() {
        val normal = PointerTuning.normalized(1f, 2f, false)
        val natural = PointerTuning.normalized(1f, 2f, true)

        assertEquals(96f, normal.wheel(1f, 1f).first)
        assertEquals(96f, normal.wheel(1f, 1f).second)
        assertEquals(-96f, natural.wheel(1f, 1f).first)
        assertEquals(-96f, natural.wheel(1f, 1f).second)
    }
}
