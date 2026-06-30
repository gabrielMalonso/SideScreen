package com.sidescreen.app

import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object AuthHandshake {
    private val REQ_MAGIC = byteArrayOf(0x53, 0x53, 0x57, 0x43) // "SSWC"
    private val RES_MAGIC = byteArrayOf(0x53, 0x53, 0x57, 0x52) // "SSWR"
    const val DEVICE_SECRET_LENGTH = 32
    const val AUTH_NONCE_LENGTH = 16
    const val AUTH_TAG_LENGTH = 32
    const val SESSION_ID_LENGTH = 16
    const val INPUT_TOKEN_LENGTH = 32

    enum class ResponseStatus(val code: Byte) {
        OK(0x00),
        INVALID_TOKEN(0x01),
        INVALID_MAGIC(0x02),
        INVALID_NAME(0x03),
        DEVICE_REVOKED(0x04),
        ;

        companion object {
            fun forCode(code: Byte): ResponseStatus? = values().firstOrNull { it.code == code }
        }
    }

    data class SessionCredentials(
        val sessionId: ByteArray,
        val inputToken: ByteArray,
    ) {
        init {
            require(sessionId.size == SESSION_ID_LENGTH) { "sessionId must be 16 bytes" }
            require(inputToken.size == INPUT_TOKEN_LENGTH) { "inputToken must be 32 bytes" }
        }

        override fun equals(other: Any?): Boolean =
            other is SessionCredentials &&
                sessionId.contentEquals(other.sessionId) &&
                inputToken.contentEquals(other.inputToken)

        override fun hashCode(): Int = 31 * sessionId.contentHashCode() + inputToken.contentHashCode()
    }

    /**
     * Build the wire format request:
     *   [magic 4][token 32][name_len 1][name N][device_id_len 1][device_id N][device_secret 32][nonce 16][hmac 32]
     */
    fun encodeRequest(
        token: ByteArray,
        deviceName: String,
        deviceId: String,
        deviceSecret: ByteArray,
        clientNonce: ByteArray = newClientNonce(),
    ): ByteArray {
        require(token.size == 32) { "token must be 32 bytes, got ${token.size}" }
        require(deviceSecret.size == DEVICE_SECRET_LENGTH) { "deviceSecret must be 32 bytes, got ${deviceSecret.size}" }
        require(clientNonce.size == AUTH_NONCE_LENGTH) { "clientNonce must be 16 bytes, got ${clientNonce.size}" }
        val nameBytes = deviceName.toByteArray(Charsets.UTF_8)
        val deviceIdBytes = deviceId.toByteArray(Charsets.UTF_8)
        require(nameBytes.size in 1..64) { "deviceName UTF-8 length must be 1..64, got ${nameBytes.size}" }
        require(deviceIdBytes.size in 1..64) { "deviceId UTF-8 length must be 1..64, got ${deviceIdBytes.size}" }
        val authTag = authenticationTag(deviceSecret, deviceId, deviceName, clientNonce)
        return REQ_MAGIC + token + byteArrayOf(nameBytes.size.toByte()) + nameBytes +
            byteArrayOf(deviceIdBytes.size.toByte()) + deviceIdBytes + deviceSecret + clientNonce + authTag
    }

    fun newClientNonce(): ByteArray =
        ByteArray(AUTH_NONCE_LENGTH).also { SecureRandom().nextBytes(it) }

    fun authenticationTag(
        deviceSecret: ByteArray,
        deviceId: String,
        deviceName: String,
        clientNonce: ByteArray,
    ): ByteArray {
        require(deviceSecret.size == DEVICE_SECRET_LENGTH) { "deviceSecret must be 32 bytes, got ${deviceSecret.size}" }
        require(clientNonce.size == AUTH_NONCE_LENGTH) { "clientNonce must be 16 bytes, got ${clientNonce.size}" }
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(deviceSecret, "HmacSHA256"))
        return mac.doFinal(authMessage(deviceId, deviceName, clientNonce))
    }

    fun validateAuthenticationTag(
        tag: ByteArray,
        deviceSecret: ByteArray,
        deviceId: String,
        deviceName: String,
        clientNonce: ByteArray,
    ): Boolean =
        MessageDigest.isEqual(tag, authenticationTag(deviceSecret, deviceId, deviceName, clientNonce))

    private fun authMessage(
        deviceId: String,
        deviceName: String,
        clientNonce: ByteArray,
    ): ByteArray {
        val nameBytes = deviceName.toByteArray(Charsets.UTF_8)
        val deviceIdBytes = deviceId.toByteArray(Charsets.UTF_8)
        require(nameBytes.size in 1..64) { "deviceName UTF-8 length must be 1..64, got ${nameBytes.size}" }
        require(deviceIdBytes.size in 1..64) { "deviceId UTF-8 length must be 1..64, got ${deviceIdBytes.size}" }
        return REQ_MAGIC + byteArrayOf(deviceIdBytes.size.toByte()) + deviceIdBytes +
            byteArrayOf(nameBytes.size.toByte()) + nameBytes + clientNonce
    }

    /**
     * Parse the 5-byte response. Returns null if magic is wrong or buffer is malformed.
     */
    fun parseResponse(bytes: ByteArray): ResponseStatus? {
        if (bytes.size < 5) return null
        for (i in 0..3) if (bytes[i] != RES_MAGIC[i]) return null
        return ResponseStatus.forCode(bytes[4])
    }

    fun parseSessionCredentials(bytes: ByteArray): SessionCredentials? {
        if (bytes.size != SESSION_ID_LENGTH + INPUT_TOKEN_LENGTH) return null
        return SessionCredentials(
            sessionId = bytes.copyOfRange(0, SESSION_ID_LENGTH),
            inputToken = bytes.copyOfRange(SESSION_ID_LENGTH, SESSION_ID_LENGTH + INPUT_TOKEN_LENGTH),
        )
    }
}
