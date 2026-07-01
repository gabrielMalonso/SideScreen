package com.sidescreen.app

import android.view.KeyEvent
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class RemoteInputProtocolTest {
    @Test
    fun helloUsesRmipMagicAndToken() {
        val token = ByteArray(32) { it.toByte() }
        val bytes = RemoteInputProtocol.hello(token, "Tablet", capabilities = 5)
        assertArrayEquals(byteArrayOf(0x52, 0x4D, 0x49, 0x50), bytes.copyOfRange(0, 4))
        assertEquals(1, bytes[4].toInt())
        assertEquals(0, bytes[5].toInt())
        assertArrayEquals(token, bytes.copyOfRange(6, 38))
    }

    @Test
    fun helloCanCarrySessionId() {
        val token = ByteArray(32) { it.toByte() }
        val sessionId = ByteArray(16) { (it + 64).toByte() }
        val bytes = RemoteInputProtocol.hello(token, "Tablet", sessionId, capabilities = 5)
        assertEquals(1, bytes[5].toInt())
        assertArrayEquals(sessionId, bytes.copyOfRange(bytes.size - 16, bytes.size))
    }

    @Test
    fun mapsCommonAndroidKeyCodesToHidUsage() {
        assertEquals(0x04, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_A))
        assertEquals(0x27, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_0))
        assertEquals(0x28, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_ENTER))
        assertEquals(0x52, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_DPAD_UP))
    }

    @Test
    fun mapsMetaKeyUsingSelectedModifierMapping() {
        assertEquals(0xE3, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_META_LEFT))
        assertEquals(0xE7, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_META_RIGHT))
        assertEquals(0xE2, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_META_LEFT, MetaKeyMapping.OPTION))
        assertEquals(0xE6, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_META_RIGHT, MetaKeyMapping.OPTION))
        assertEquals(0xE0, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_META_LEFT, MetaKeyMapping.CONTROL))
        assertEquals(0xE4, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_META_RIGHT, MetaKeyMapping.CONTROL))
        assertNull(AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_META_LEFT, MetaKeyMapping.OFF))
    }

    @Test
    fun mapsCopyPasteShortcutKeys() {
        assertEquals(0xE3, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_META_LEFT, MetaKeyMapping.COMMAND))
        assertEquals(0x06, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_C))
        assertEquals(0x19, AndroidKeyToHid.usageIdForKeyCode(KeyEvent.KEYCODE_V))
    }

    @Test
    fun envelopeCarriesLittleEndianSequenceAndLength() {
        val bytes = RemoteInputProtocol.envelope(0x20, 42, byteArrayOf(1, 2, 3))
        val header = RemoteInputProtocol.parseEnvelopeHeader(bytes.copyOfRange(0, RemoteInputProtocol.ENVELOPE_HEADER_LENGTH))
        assertEquals(0x20, header.eventType)
        assertEquals(42, header.sequence)
        assertEquals(3, header.payloadLength)
    }

    @Test
    fun inputPingPayloadUsesLittleEndianTimestamp() {
        val bytes = RemoteInputProtocol.inputPingPayload(0x0102_0304_0506_0708L)
        assertArrayEquals(
            byteArrayOf(0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01),
            bytes,
        )
    }

    @Test
    fun textCommitPayloadPrefixesUtf8Length() {
        val text = "ação çãõ é 🧪"
        val bytes = RemoteInputProtocol.textCommitPayload(text)

        assertEquals(text.toByteArray(Charsets.UTF_8).size, bytes[0].toInt() and 0xff)
        assertEquals(0, bytes[1].toInt())
        assertEquals(text, bytes.copyOfRange(2, bytes.size).toString(Charsets.UTF_8))
    }

    @Test
    fun textCommitPayloadRejectsHostTooLargePaste() {
        val oversized = "a".repeat(RemoteInputProtocol.MAX_TEXT_COMMIT_BYTES + 1)

        try {
            RemoteInputProtocol.textCommitPayload(oversized)
            throw AssertionError("Expected oversized text commit to be rejected")
        } catch (expected: IllegalArgumentException) {
            assertEquals(
                "text commit payload too large: ${RemoteInputProtocol.MAX_TEXT_COMMIT_BYTES + 1} bytes, max ${RemoteInputProtocol.MAX_TEXT_COMMIT_BYTES}",
                expected.message,
            )
        }
    }

    @Test
    fun inputClientChunksLargeTextCommitInsteadOfThrowing() {
        val client =
            InputClient(
                host = "127.0.0.1",
                port = 9,
                token = ByteArray(32) { it.toByte() },
                deviceId = "tablet",
                sessionId = null,
                context = null,
                endpointMode = EndpointMode.MANUAL,
                metaKeyMapping = MetaKeyMapping.COMMAND,
            )

        try {
            assertTrue(client.sendTextCommit("🧪".repeat(2000)))
        } finally {
            client.shutdown()
        }
    }

    @Test
    fun allInputsUpPayloadCarriesReason() {
        val bytes = RemoteInputProtocol.allInputsUpPayload(RemoteInputProtocol.ALL_INPUTS_UP_POINTER_CAPTURE_LOST)

        assertArrayEquals(byteArrayOf(2), bytes)
    }

    @Test
    fun allInputsUpPayloadCarriesWatchdogTimeoutReason() {
        val bytes = RemoteInputProtocol.allInputsUpPayload(RemoteInputProtocol.ALL_INPUTS_UP_WATCHDOG_TIMEOUT)

        assertArrayEquals(byteArrayOf(6), bytes)
    }

    @Test
    fun exposesAccessibilityAssistCapabilityAndKeyboardFlag() {
        assertEquals(1 shl 4, RemoteInputProtocol.CAP_ACCESSIBILITY_ASSIST)
        assertEquals(1 shl 6, RemoteInputProtocol.CAP_TEXT_COMMIT)
        assertEquals(2, RemoteInputProtocol.FLAG_FROM_ACCESSIBILITY)
    }

    @Test
    fun parsesInputPongPayload() {
        val payload =
            ByteBuffer.allocate(16)
                .order(ByteOrder.LITTLE_ENDIAN)
                .putLong(0x0102_0304_0506_0708L)
                .putLong(0x1112_1314_1516_1718L)
                .array()

        val pong = RemoteInputProtocol.parseInputPongPayload(payload)
        assertEquals(0x0102_0304_0506_0708L, pong.clientTimestampNanos)
        assertEquals(0x1112_1314_1516_1718L, pong.serverTimestampNanos)
    }
}
