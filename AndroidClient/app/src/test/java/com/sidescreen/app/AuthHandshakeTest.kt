package com.sidescreen.app

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AuthHandshakeTest {
    @Test
    fun encodesGoldenBytes() {
        val deviceName = "Pixel 9"
        val deviceNameBytes = deviceName.toByteArray()
        val deviceId = "device-1"
        val deviceIdBytes = deviceId.toByteArray()
        val token = ByteArray(32) { it.toByte() }
        val secret = ByteArray(32) { (it + 64).toByte() }
        val nonce = ByteArray(16) { (it + 112).toByte() }
        val tag = AuthHandshake.authenticationTag(secret, deviceId, deviceName, nonce)
        val bytes = AuthHandshake.encodeRequest(token, deviceName, deviceId, secret, nonce)
        val expected =
            byteArrayOf(0x53, 0x53, 0x57, 0x43) +
                ByteArray(32) { it.toByte() } +
                byteArrayOf(deviceNameBytes.size.toByte()) +
                deviceNameBytes +
                byteArrayOf(deviceIdBytes.size.toByte()) +
                deviceIdBytes +
                secret +
                nonce +
                tag
        assertArrayEquals(expected, bytes)
    }

    @Test
    fun authenticationTagMatchesKnownVector() {
        val secret = ByteArray(32) { (it + 64).toByte() }
        val nonce = ByteArray(16) { (it + 112).toByte() }
        val tag = AuthHandshake.authenticationTag(secret, "device-1", "Pixel 9", nonce)
        assertArrayEquals(
            byteArrayOf(
                180.toByte(), 46, 183.toByte(), 187.toByte(), 131.toByte(), 246.toByte(), 175.toByte(), 68,
                32, 113, 61, 165.toByte(), 66, 121, 42, 33,
                75, 124, 70, 165.toByte(), 219.toByte(), 25, 187.toByte(), 149.toByte(),
                238.toByte(), 172.toByte(), 245.toByte(), 146.toByte(), 190.toByte(), 148.toByte(), 44, 177.toByte(),
            ),
            tag,
        )
        assertEquals(true, AuthHandshake.validateAuthenticationTag(tag, secret, "device-1", "Pixel 9", nonce))
        assertEquals(false, AuthHandshake.validateAuthenticationTag(ByteArray(32), secret, "device-1", "Pixel 9", nonce))
    }

    @Test
    fun rejectsNameLongerThan64() {
        val longName = "x".repeat(65)
        try {
            AuthHandshake.encodeRequest(ByteArray(32), longName, "device-1", ByteArray(32))
            error("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // OK
        }
    }

    @Test
    fun rejectsDeviceIdLongerThan64() {
        val longId = "x".repeat(65)
        try {
            AuthHandshake.encodeRequest(ByteArray(32), "x", longId, ByteArray(32))
            error("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // OK
        }
    }

    @Test
    fun rejectsTokenWrongSize() {
        try {
            AuthHandshake.encodeRequest(ByteArray(31), "x", "device-1", ByteArray(32))
            error("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // OK
        }
    }

    @Test
    fun rejectsDeviceSecretWrongSize() {
        try {
            AuthHandshake.encodeRequest(ByteArray(32), "x", "device-1", ByteArray(31))
            error("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // OK
        }
    }

    @Test
    fun rejectsNonceWrongSize() {
        try {
            AuthHandshake.encodeRequest(ByteArray(32), "x", "device-1", ByteArray(32), ByteArray(15))
            error("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // OK
        }
    }

    @Test
    fun parseOKResponse() {
        val r = AuthHandshake.parseResponse(byteArrayOf(0x53, 0x53, 0x57, 0x52, 0x00))
        assertEquals(AuthHandshake.ResponseStatus.OK, r)
    }

    @Test
    fun parseInvalidTokenResponse() {
        val r = AuthHandshake.parseResponse(byteArrayOf(0x53, 0x53, 0x57, 0x52, 0x01))
        assertEquals(AuthHandshake.ResponseStatus.INVALID_TOKEN, r)
    }

    @Test
    fun parseDeviceRevokedResponse() {
        val r = AuthHandshake.parseResponse(byteArrayOf(0x53, 0x53, 0x57, 0x52, 0x04))
        assertEquals(AuthHandshake.ResponseStatus.DEVICE_REVOKED, r)
    }

    @Test
    fun parsesSessionCredentials() {
        val bytes = ByteArray(48) { it.toByte() }
        val credentials = AuthHandshake.parseSessionCredentials(bytes)!!
        assertArrayEquals(ByteArray(16) { it.toByte() }, credentials.sessionId)
        assertArrayEquals(ByteArray(32) { (it + 16).toByte() }, credentials.inputToken)
    }

    @Test
    fun rejectsMalformedSessionCredentials() {
        assertNull(AuthHandshake.parseSessionCredentials(ByteArray(47)))
    }

    @Test
    fun parseInvalidMagicResponseReturnsNull() {
        val r = AuthHandshake.parseResponse(byteArrayOf(0x58, 0x58, 0x58, 0x58, 0x00))
        assertNull(r)
    }
}
