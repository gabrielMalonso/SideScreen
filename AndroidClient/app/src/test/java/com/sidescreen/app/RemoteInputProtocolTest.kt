package com.sidescreen.app

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
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
        assertEquals(0x04, AndroidKeyToHid.usageIdForKeyCode(29))
        assertEquals(0x27, AndroidKeyToHid.usageIdForKeyCode(7))
        assertEquals(0x28, AndroidKeyToHid.usageIdForKeyCode(66))
        assertEquals(0x52, AndroidKeyToHid.usageIdForKeyCode(19))
    }

    @Test
    fun envelopeCarriesLittleEndianSequenceAndLength() {
        val bytes = RemoteInputProtocol.envelope(0x20, 42, byteArrayOf(1, 2, 3))
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(0x20, buffer.get().toInt())
        assertEquals(42, buffer.long)
        buffer.long
        assertEquals(3, buffer.short.toInt())
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
    fun exposesAccessibilityAssistCapabilityAndKeyboardFlag() {
        assertEquals(1 shl 4, RemoteInputProtocol.CAP_ACCESSIBILITY_ASSIST)
        assertEquals(2, RemoteInputProtocol.FLAG_FROM_ACCESSIBILITY)
    }
}
