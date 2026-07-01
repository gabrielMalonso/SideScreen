package com.sidescreen.app

import android.view.KeyEvent

class RemoteKeyboardCapture(
    private val inputClient: () -> InputClient?,
    private val recordInputEvent: () -> Unit,
    private val updateDiagnostics: () -> Unit,
) {
    fun dispatch(event: KeyEvent): Boolean {
        if (RemoteInputBridge.wasRecentlyForwardedByAccessibility(event)) {
            RemoteInputDiagnostics.recordDuplicate(event)
            updateDiagnostics()
            recordInputEvent()
            return true
        }

        val handled = inputClient()?.sendKey(event) == true
        RemoteInputDiagnostics.recordKey(RemoteInputDiagnosticsState.Source.ACTIVITY, handled, event)
        updateDiagnostics()
        if (handled) recordInputEvent()
        return handled
    }
}
