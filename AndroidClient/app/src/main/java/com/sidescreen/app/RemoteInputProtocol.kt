package com.sidescreen.app

import android.view.KeyEvent
import java.nio.ByteBuffer
import java.nio.ByteOrder

object RemoteInputProtocol {
    const val CAP_KEYBOARD_ACTIVITY = 1 shl 0
    const val CAP_POINTER_CAPTURE = 1 shl 1
    const val CAP_GENERIC_MOTION = 1 shl 2
    const val CAP_HID_USAGE_MAPPING = 1 shl 7

    const val EVENT_KEYBOARD_KEY = 0x01
    const val EVENT_POINTER_RELATIVE = 0x10
    const val EVENT_POINTER_BUTTON = 0x11
    const val EVENT_POINTER_WHEEL = 0x12
    const val EVENT_ALL_INPUTS_UP = 0x20

    fun hello(
        token: ByteArray,
        deviceId: String,
        capabilities: Int,
    ): ByteArray {
        require(token.size == 32) { "token must be 32 bytes" }
        val deviceBytes = deviceId.toByteArray(Charsets.UTF_8).let {
            if (it.size <= 64) it else it.copyOf(64)
        }
        return ByteBuffer.allocate(4 + 1 + 1 + 32 + 1 + deviceBytes.size + 4)
            .order(ByteOrder.LITTLE_ENDIAN)
            .put(byteArrayOf(0x52, 0x4D, 0x49, 0x50)) // RMIP
            .put(1.toByte())
            .put(0.toByte())
            .put(token)
            .put(deviceBytes.size.toByte())
            .put(deviceBytes)
            .putInt(capabilities)
            .array()
    }

    fun envelope(
        eventType: Int,
        sequence: Long,
        payload: ByteArray,
    ): ByteArray =
        ByteBuffer.allocate(21 + payload.size)
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
            .putInt(1) // FLAG_FROM_ACTIVITY
            .array()

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
    fun usageId(event: KeyEvent): Int? = usageIdForKeyCode(event.keyCode)

    fun usageIdForKeyCode(keyCode: Int): Int? =
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
