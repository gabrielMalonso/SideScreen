package com.sidescreen.app

import android.view.KeyEvent

object RemoteInputBridge {
    private const val DUPLICATE_WINDOW_MS = 150L

    @Volatile
    private var inputClient: InputClient? = null

    @Volatile
    private var lastAccessibilitySignature: KeySignature? = null

    fun attach(client: InputClient) {
        inputClient = client
        lastAccessibilitySignature = null
    }

    fun detach(client: InputClient?) {
        if (client == null || inputClient === client) {
            inputClient = null
            lastAccessibilitySignature = null
        }
    }

    fun isInputConnected(): Boolean = inputClient?.isConnected == true

    fun sendAccessibilityKey(event: KeyEvent): Boolean {
        val handled =
            inputClient?.sendKey(
                event = event,
                sourceFlag = RemoteInputProtocol.FLAG_FROM_ACCESSIBILITY,
            ) == true
        if (handled) {
            lastAccessibilitySignature = KeySignature.from(event, System.currentTimeMillis())
        }
        return handled
    }

    fun wasRecentlyForwardedByAccessibility(event: KeyEvent): Boolean {
        val signature = lastAccessibilitySignature ?: return false
        return signature.matches(event, System.currentTimeMillis(), DUPLICATE_WINDOW_MS)
    }

    private data class KeySignature(
        val keyCode: Int,
        val scanCode: Int,
        val action: Int,
        val downTime: Long,
        val eventTime: Long,
        val recordedAtMs: Long,
    ) {
        fun matches(
            event: KeyEvent,
            nowMs: Long,
            windowMs: Long,
        ): Boolean =
            nowMs - recordedAtMs <= windowMs &&
                keyCode == event.keyCode &&
                scanCode == event.scanCode &&
                action == event.action &&
                downTime == event.downTime &&
                eventTime == event.eventTime

        companion object {
            fun from(
                event: KeyEvent,
                recordedAtMs: Long,
            ): KeySignature =
                KeySignature(
                    keyCode = event.keyCode,
                    scanCode = event.scanCode,
                    action = event.action,
                    downTime = event.downTime,
                    eventTime = event.eventTime,
                    recordedAtMs = recordedAtMs,
                )
        }
    }
}
