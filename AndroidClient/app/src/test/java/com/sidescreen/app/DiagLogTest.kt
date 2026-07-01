package com.sidescreen.app

import org.junit.Assert.assertEquals
import org.junit.Test

class DiagLogTest {
    @Test
    fun summarizesRecentErrorsInOriginalOrder() {
        val summary =
            DiagLog.summarizeRecentErrors(
                listOf(
                    "[1] IC: Input channel connected",
                    "[2] SC: TCP connect failed to 100.1.2.3",
                    "[3] AS: Accessibility assist connected",
                    "[4] HS: token rejected",
                    "[5] SC: TCP connect timeout",
                ),
                maxLines = 2,
            )

        assertEquals("Recent errors: token rejected · TCP connect timeout", summary)
    }

    @Test
    fun summarizesNoErrors() {
        val summary =
            DiagLog.summarizeRecentErrors(
                listOf(
                    "[1] IC: Input channel connected",
                    "[2] AS: Accessibility assist connected",
                ),
            )

        assertEquals("Recent errors: none", summary)
    }
}
