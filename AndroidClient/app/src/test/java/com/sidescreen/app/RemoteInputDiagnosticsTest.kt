package com.sidescreen.app

import org.junit.Assert.assertEquals
import org.junit.Test

class RemoteInputDiagnosticsTest {
    @Test
    fun recordsCapturedUnsupportedAssistAndDuplicateKeys() {
        val state = RemoteInputDiagnosticsState()

        state.recordKey(
            source = RemoteInputDiagnosticsState.Source.ACTIVITY,
            handled = true,
            action = "down",
            keyCode = "KEYCODE_A",
            scanCode = 30,
            repeatCount = 0,
        )
        state.recordKey(
            source = RemoteInputDiagnosticsState.Source.ACTIVITY,
            handled = false,
            action = "down",
            keyCode = "KEYCODE_UNKNOWN",
            scanCode = 0,
            repeatCount = 0,
        )
        state.recordKey(
            source = RemoteInputDiagnosticsState.Source.ACCESSIBILITY,
            handled = true,
            action = "up",
            keyCode = "KEYCODE_TAB",
            scanCode = 15,
            repeatCount = 0,
        )
        state.recordDuplicate("up KEYCODE_TAB scan=15")

        val snapshot = state.snapshot()
        assertEquals(2, snapshot.capturedKeys)
        assertEquals(1, snapshot.unsupportedKeys)
        assertEquals(1, snapshot.accessibilityKeys)
        assertEquals(1, snapshot.duplicateKeys)
        assertEquals("duplicate up KEYCODE_TAB scan=15", snapshot.lastKey)
    }

    @Test
    fun summaryIsCompactAndStable() {
        val state = RemoteInputDiagnosticsState()

        state.recordKey(
            source = RemoteInputDiagnosticsState.Source.ACTIVITY,
            handled = false,
            action = "down",
            keyCode = "KEYCODE_META_LEFT",
            scanCode = 0,
            repeatCount = 1,
        )

        assertEquals(
            "Keys: captured 0 / unsupported 1 · assist 0 · dup 0 · last activity down KEYCODE_META_LEFT scan=0 repeat=1 unsupported",
            state.snapshot().keySummary(),
        )
    }

    @Test
    fun textCommitRecordsLengthWithoutTextContent() {
        val state = RemoteInputDiagnosticsState()

        state.recordTextCommit(byteCount = 6)

        val snapshot = state.snapshot()
        assertEquals(1, snapshot.capturedKeys)
        assertEquals("activity textCommit bytes=6 sent", snapshot.lastKey)
    }
}
