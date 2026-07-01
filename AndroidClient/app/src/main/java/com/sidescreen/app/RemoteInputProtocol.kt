package com.sidescreen.app

import android.view.KeyEvent
import java.nio.ByteBuffer
import java.nio.ByteOrder

object RemoteInputProtocol {
    const val MAX_PAYLOAD_BYTES = 4096
    const val MAX_TEXT_COMMIT_BYTES = MAX_PAYLOAD_BYTES - 2

    const val CAP_KEYBOARD_ACTIVITY = 1 shl 0
    const val CAP_POINTER_CAPTURE = 1 shl 1
    const val CAP_GENERIC_MOTION = 1 shl 2
    const val CAP_ACCESSIBILITY_ASSIST = 1 shl 4
    const val CAP_TEXT_COMMIT = 1 shl 6
    const val CAP_HID_USAGE_MAPPING = 1 shl 7

    const val FLAG_FROM_ACTIVITY = 1
    const val FLAG_FROM_ACCESSIBILITY = 1 shl 1

    const val EVENT_KEYBOARD_KEY = 0x01
    const val EVENT_TEXT_COMMIT = 0x02
    const val EVENT_POINTER_RELATIVE = 0x10
    const val EVENT_POINTER_BUTTON = 0x11
    const val EVENT_POINTER_WHEEL = 0x12
    const val EVENT_ALL_INPUTS_UP = 0x20
    const val EVENT_INPUT_PING = 0x30
    const val EVENT_INPUT_PONG = 0x31
    const val ENVELOPE_HEADER_LENGTH = 19

    const val ALL_INPUTS_UP_EXPLICIT_USER_ACTION = 0
    const val ALL_INPUTS_UP_ANDROID_LIFECYCLE_PAUSE = 1
    const val ALL_INPUTS_UP_POINTER_CAPTURE_LOST = 2
    const val ALL_INPUTS_UP_INPUT_BACKEND_SWITCH = 3
    const val ALL_INPUTS_UP_NETWORK_DISCONNECT = 4
    const val ALL_INPUTS_UP_PROTOCOL_ERROR = 5
    const val ALL_INPUTS_UP_WATCHDOG_TIMEOUT = 6

    data class EnvelopeHeader(
        val eventType: Int,
        val sequence: Long,
        val timestampNanos: Long,
        val payloadLength: Int,
    )

    data class InputPong(
        val clientTimestampNanos: Long,
        val serverTimestampNanos: Long,
    )

    fun hello(
        token: ByteArray,
        deviceId: String,
        sessionId: ByteArray? = null,
        capabilities: Int,
    ): ByteArray {
        require(token.size == 32) { "token must be 32 bytes" }
        require(sessionId == null || sessionId.size == AuthHandshake.SESSION_ID_LENGTH) {
            "sessionId must be 16 bytes"
        }
        val deviceBytes = deviceId.toByteArray(Charsets.UTF_8).let {
            if (it.size <= 64) it else it.copyOf(64)
        }
        val flags = if (sessionId != null) 1 else 0
        val buffer = ByteBuffer.allocate(4 + 1 + 1 + 32 + 1 + deviceBytes.size + 4 + (sessionId?.size ?: 0))
            .order(ByteOrder.LITTLE_ENDIAN)
            .put(byteArrayOf(0x52, 0x4D, 0x49, 0x50)) // RMIP
            .put(1.toByte())
            .put(flags.toByte())
            .put(token)
            .put(deviceBytes.size.toByte())
            .put(deviceBytes)
            .putInt(capabilities)
        if (sessionId != null) {
            buffer.put(sessionId)
        }
        return buffer.array()
    }

    fun envelope(
        eventType: Int,
        sequence: Long,
        payload: ByteArray,
    ): ByteArray =
        ByteBuffer.allocate(ENVELOPE_HEADER_LENGTH + payload.size)
            .order(ByteOrder.LITTLE_ENDIAN)
            .put(eventType.toByte())
            .putLong(sequence)
            .putLong(System.nanoTime())
            .putShort(payload.size.toShort())
            .put(payload)
            .array()

    fun keyboardPayload(
        event: KeyEvent,
        usageId: Int,
        down: Boolean,
        sourceFlag: Int = FLAG_FROM_ACTIVITY,
    ): ByteArray =
        ByteBuffer.allocate(24)
            .order(ByteOrder.LITTLE_ENDIAN)
            .put(if (down) 0 else 1)
            .putShort(0x07.toShort())
            .putShort(usageId.toShort())
            .putInt(event.scanCode)
            .putInt(event.keyCode)
            .put(keyLocation(event).toByte())
            .putShort(event.repeatCount.toShort())
            .putInt(event.metaState)
            .putInt(sourceFlag)
            .array()

    fun textCommitPayload(text: String): ByteArray {
        val bytes = text.toByteArray(Charsets.UTF_8)
        require(bytes.isNotEmpty()) { "text commit must not be empty" }
        require(bytes.size <= MAX_TEXT_COMMIT_BYTES) {
            "text commit payload too large: ${bytes.size} bytes, max $MAX_TEXT_COMMIT_BYTES"
        }
        return ByteBuffer.allocate(2 + bytes.size)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putShort(bytes.size.toShort())
            .put(bytes)
            .array()
    }

    fun pointerRelativePayload(
        dx: Float,
        dy: Float,
        fromPointerCapture: Boolean,
    ): ByteArray =
        ByteBuffer.allocate(13)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putFloat(dx)
            .putFloat(dy)
            .put(0.toByte()) // pixel-like
            .putInt(if (fromPointerCapture) 1 else 2)
            .array()

    fun pointerButtonPayload(
        button: Int,
        down: Boolean,
    ): ByteArray =
        ByteBuffer.allocate(6)
            .order(ByteOrder.LITTLE_ENDIAN)
            .put(if (down) 0 else 1)
            .put(button.toByte())
            .putInt(0)
            .array()

    fun pointerWheelPayload(
        deltaX: Float,
        deltaY: Float,
    ): ByteArray =
        ByteBuffer.allocate(13)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putFloat(deltaX)
            .putFloat(deltaY)
            .put(1.toByte()) // pixel
            .putInt(0)
            .array()

    fun inputPingPayload(value: Long = System.nanoTime()): ByteArray =
        ByteBuffer.allocate(8)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putLong(value)
            .array()

    fun allInputsUpPayload(reason: Int): ByteArray =
        byteArrayOf(reason.coerceIn(0, 255).toByte())

    fun parseEnvelopeHeader(bytes: ByteArray): EnvelopeHeader {
        require(bytes.size == ENVELOPE_HEADER_LENGTH) { "input envelope header must be $ENVELOPE_HEADER_LENGTH bytes" }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        return EnvelopeHeader(
            eventType = buffer.get().toInt() and 0xff,
            sequence = buffer.long,
            timestampNanos = buffer.long,
            payloadLength = buffer.short.toInt() and 0xffff,
        )
    }

    fun parseInputPongPayload(bytes: ByteArray): InputPong {
        require(bytes.size == 16) { "input pong payload must be 16 bytes" }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        return InputPong(
            clientTimestampNanos = buffer.long,
            serverTimestampNanos = buffer.long,
        )
    }

    private fun keyLocation(event: KeyEvent): Int =
        when (event.keyCode) {
            KeyEvent.KEYCODE_SHIFT_LEFT,
            KeyEvent.KEYCODE_CTRL_LEFT,
            KeyEvent.KEYCODE_ALT_LEFT,
            KeyEvent.KEYCODE_META_LEFT,
            -> 1
            KeyEvent.KEYCODE_SHIFT_RIGHT,
            KeyEvent.KEYCODE_CTRL_RIGHT,
            KeyEvent.KEYCODE_ALT_RIGHT,
            KeyEvent.KEYCODE_META_RIGHT,
            -> 2
            in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_EQUALS -> 3
            else -> 0
        }
}

object AndroidKeyToHid {
    fun usageId(
        event: KeyEvent,
        metaKeyMapping: MetaKeyMapping = MetaKeyMapping.COMMAND,
    ): Int? =
        usageIdForKeyCode(event.keyCode, metaKeyMapping)

    fun usageIdForKeyCode(
        keyCode: Int,
        metaKeyMapping: MetaKeyMapping = MetaKeyMapping.COMMAND,
    ): Int? =
        if (keyCode == KeyEvent.KEYCODE_META_LEFT || keyCode == KeyEvent.KEYCODE_META_RIGHT) {
            metaKeyMapping.usageIdForKeyCode(keyCode)
        } else {
            baseUsageIdForKeyCode(keyCode)
        }

    private fun baseUsageIdForKeyCode(keyCode: Int): Int? =
        when {
            keyCode in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z -> 0x04 + (keyCode - KeyEvent.KEYCODE_A)
            keyCode in KeyEvent.KEYCODE_1..KeyEvent.KEYCODE_9 -> 0x1E + (keyCode - KeyEvent.KEYCODE_1)
            keyCode == KeyEvent.KEYCODE_0 -> 0x27
            keyCode in KeyEvent.KEYCODE_F1..KeyEvent.KEYCODE_F12 -> 0x3A + (keyCode - KeyEvent.KEYCODE_F1)
            keyCode in KeyEvent.KEYCODE_NUMPAD_1..KeyEvent.KEYCODE_NUMPAD_9 -> 0x59 + (keyCode - KeyEvent.KEYCODE_NUMPAD_1)
            keyCode == KeyEvent.KEYCODE_NUMPAD_0 -> 0x62
            else -> directMap[keyCode]
        }

    private val directMap =
        mapOf(
            KeyEvent.KEYCODE_ENTER to 0x28,
            KeyEvent.KEYCODE_ESCAPE to 0x29,
            KeyEvent.KEYCODE_DEL to 0x2A,
            KeyEvent.KEYCODE_TAB to 0x2B,
            KeyEvent.KEYCODE_SPACE to 0x2C,
            KeyEvent.KEYCODE_MINUS to 0x2D,
            KeyEvent.KEYCODE_EQUALS to 0x2E,
            KeyEvent.KEYCODE_LEFT_BRACKET to 0x2F,
            KeyEvent.KEYCODE_RIGHT_BRACKET to 0x30,
            KeyEvent.KEYCODE_BACKSLASH to 0x31,
            KeyEvent.KEYCODE_SEMICOLON to 0x33,
            KeyEvent.KEYCODE_APOSTROPHE to 0x34,
            KeyEvent.KEYCODE_GRAVE to 0x35,
            KeyEvent.KEYCODE_COMMA to 0x36,
            KeyEvent.KEYCODE_PERIOD to 0x37,
            KeyEvent.KEYCODE_SLASH to 0x38,
            KeyEvent.KEYCODE_CAPS_LOCK to 0x39,
            KeyEvent.KEYCODE_INSERT to 0x49,
            KeyEvent.KEYCODE_FORWARD_DEL to 0x4C,
            KeyEvent.KEYCODE_MOVE_HOME to 0x4A,
            KeyEvent.KEYCODE_MOVE_END to 0x4D,
            KeyEvent.KEYCODE_PAGE_UP to 0x4B,
            KeyEvent.KEYCODE_PAGE_DOWN to 0x4E,
            KeyEvent.KEYCODE_DPAD_RIGHT to 0x4F,
            KeyEvent.KEYCODE_DPAD_LEFT to 0x50,
            KeyEvent.KEYCODE_DPAD_DOWN to 0x51,
            KeyEvent.KEYCODE_DPAD_UP to 0x52,
            KeyEvent.KEYCODE_NUMPAD_DIVIDE to 0x54,
            KeyEvent.KEYCODE_NUMPAD_MULTIPLY to 0x55,
            KeyEvent.KEYCODE_NUMPAD_SUBTRACT to 0x56,
            KeyEvent.KEYCODE_NUMPAD_ADD to 0x57,
            KeyEvent.KEYCODE_NUMPAD_ENTER to 0x58,
            KeyEvent.KEYCODE_NUMPAD_DOT to 0x63,
            KeyEvent.KEYCODE_SHIFT_LEFT to 0xE1,
            KeyEvent.KEYCODE_SHIFT_RIGHT to 0xE5,
            KeyEvent.KEYCODE_CTRL_LEFT to 0xE0,
            KeyEvent.KEYCODE_CTRL_RIGHT to 0xE4,
            KeyEvent.KEYCODE_ALT_LEFT to 0xE2,
            KeyEvent.KEYCODE_ALT_RIGHT to 0xE6,
            KeyEvent.KEYCODE_META_LEFT to 0xE3,
            KeyEvent.KEYCODE_META_RIGHT to 0xE7,
        )
}
