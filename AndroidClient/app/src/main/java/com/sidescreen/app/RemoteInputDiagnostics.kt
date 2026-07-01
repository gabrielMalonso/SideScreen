package com.sidescreen.app

import android.view.KeyEvent

class RemoteInputDiagnosticsState {
    enum class Source { ACTIVITY, ACCESSIBILITY }

    data class Snapshot(
        val capturedKeys: Long = 0,
        val unsupportedKeys: Long = 0,
        val accessibilityKeys: Long = 0,
        val duplicateKeys: Long = 0,
        val lastKey: String = "none",
    ) {
        fun keySummary(): String =
            "Keys: captured $capturedKeys / unsupported $unsupportedKeys · assist $accessibilityKeys · dup $duplicateKeys · last $lastKey"
    }

    private var capturedKeys = 0L
    private var unsupportedKeys = 0L
    private var accessibilityKeys = 0L
    private var duplicateKeys = 0L
    private var lastKey = "none"

    @Synchronized
    fun recordKey(
        source: Source,
        handled: Boolean,
        action: String,
        keyCode: String,
        scanCode: Int,
        repeatCount: Int,
    ) {
        if (handled) {
            capturedKeys += 1
            if (source == Source.ACCESSIBILITY) accessibilityKeys += 1
        } else {
            unsupportedKeys += 1
        }
        lastKey = "${source.name.lowercase()} $action $keyCode scan=$scanCode repeat=$repeatCount ${if (handled) "sent" else "unsupported"}"
    }

    @Synchronized
    fun recordDuplicate(eventDescription: String) {
        duplicateKeys += 1
        lastKey = "duplicate $eventDescription"
    }

    @Synchronized
    fun recordTextCommit(byteCount: Int) {
        capturedKeys += 1
        lastKey = "activity textCommit bytes=$byteCount sent"
    }

    @Synchronized
    fun reset() {
        capturedKeys = 0
        unsupportedKeys = 0
        accessibilityKeys = 0
        duplicateKeys = 0
        lastKey = "none"
    }

    @Synchronized
    fun snapshot(): Snapshot =
        Snapshot(
            capturedKeys = capturedKeys,
            unsupportedKeys = unsupportedKeys,
            accessibilityKeys = accessibilityKeys,
            duplicateKeys = duplicateKeys,
            lastKey = lastKey,
        )
}

object RemoteInputDiagnostics {
    private val state = RemoteInputDiagnosticsState()

    fun recordKey(
        source: RemoteInputDiagnosticsState.Source,
        handled: Boolean,
        event: KeyEvent,
    ) {
        state.recordKey(
            source = source,
            handled = handled,
            action = actionName(event.action),
            keyCode = KeyEvent.keyCodeToString(event.keyCode),
            scanCode = event.scanCode,
            repeatCount = event.repeatCount,
        )
    }

    fun recordDuplicate(event: KeyEvent) {
        state.recordDuplicate("${actionName(event.action)} ${KeyEvent.keyCodeToString(event.keyCode)} scan=${event.scanCode}")
    }

    fun recordTextCommit(text: String) {
        state.recordTextCommit(text.toByteArray(Charsets.UTF_8).size)
    }

    fun reset() {
        state.reset()
    }

    fun snapshot(): RemoteInputDiagnosticsState.Snapshot = state.snapshot()

    private fun actionName(action: Int): String =
        when (action) {
            KeyEvent.ACTION_DOWN -> "down"
            KeyEvent.ACTION_UP -> "up"
            else -> "action=$action"
        }
}
