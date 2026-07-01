package com.sidescreen.app

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

class SideScreenAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        DiagLog.log("AS", "Accessibility assist connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Key filtering is handled in onKeyEvent. Window content is intentionally ignored.
    }

    override fun onInterrupt() {
        DiagLog.log("AS", "Accessibility assist interrupted")
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (!RemoteInputBridge.isInputConnected()) return false
        if (event.action != KeyEvent.ACTION_DOWN && event.action != KeyEvent.ACTION_UP) return false

        val handled = RemoteInputBridge.sendAccessibilityKey(event)
        RemoteInputDiagnostics.recordKey(RemoteInputDiagnosticsState.Source.ACCESSIBILITY, handled, event)
        if (handled) {
            DiagLog.log("AS", "forwarded key action=${event.action} code=${event.keyCode}")
        }
        return handled
    }

    companion object {
        fun isEnabled(context: Context): Boolean {
            val expected = ComponentName(context, SideScreenAccessibilityService::class.java).flattenToString()
            val enabled =
                Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                ) ?: return false
            return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
        }
    }
}
