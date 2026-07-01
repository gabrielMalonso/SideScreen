import XCTest
@testable import SideScreen

final class HandshakeCodecTests: XCTestCase {
    func testParseValidRequest() throws {
        let deviceName = "Pixel 9"
        var bytes: [UInt8] = [0x53, 0x53, 0x57, 0x41]
        bytes.append(contentsOf: (0..<32).map { UInt8($0) })
        appendStringField(deviceName, to: &bytes)
        let result = try HandshakeCodec.parseRequest(Data(bytes))
        XCTAssertEqual(result.token.count, 32)
        XCTAssertEqual(result.token.first, 0x00)
        XCTAssertEqual(result.token.last, 0x1F)
        XCTAssertEqual(result.deviceName, deviceName)
        XCTAssertEqual(result.deviceId, "legacy:\(deviceName)")
        XCTAssertNil(result.deviceSecret)
        XCTAssertTrue(result.isLegacyIdentity)
    }

    func testParseValidV2RequestWithDeviceId() throws {
        let deviceName = "Pixel 9"
        let deviceId = "device-1"
        var bytes: [UInt8] = [0x53, 0x53, 0x57, 0x42]
        bytes.append(contentsOf: (0..<32).map { UInt8($0) })
        appendStringField(deviceName, to: &bytes)
        appendStringField(deviceId, to: &bytes)

        let result = try HandshakeCodec.parseRequest(Data(bytes))
        XCTAssertEqual(result.deviceName, deviceName)
        XCTAssertEqual(result.deviceId, deviceId)
        XCTAssertNil(result.deviceSecret)
        XCTAssertFalse(result.isLegacyIdentity)
    }

    func testParseValidV3RequestWithDeviceSecret() throws {
        let deviceName = "Pixel 9"
        let deviceId = "device-1"
        let secret = Data((80..<112).map { UInt8($0) })
        let nonce = Data((112..<128).map { UInt8($0) })
        let tag = try HandshakeCodec.authenticationTag(
            deviceSecret: secret,
            deviceId: deviceId,
            deviceName: deviceName,
            clientNonce: nonce
        )
        var bytes: [UInt8] = [0x53, 0x53, 0x57, 0x43]
        bytes.append(contentsOf: (0..<32).map { UInt8($0) })
        appendStringField(deviceName, to: &bytes)
        appendStringField(deviceId, to: &bytes)
        bytes.append(contentsOf: secret)
        bytes.append(contentsOf: nonce)
        bytes.append(contentsOf: tag)

        let result = try HandshakeCodec.parseRequest(Data(bytes))
        XCTAssertEqual(result.deviceName, deviceName)
        XCTAssertEqual(result.deviceId, deviceId)
        XCTAssertEqual(result.deviceSecret, secret)
        XCTAssertEqual(result.clientNonce, nonce)
        XCTAssertEqual(result.authTag, tag)
        XCTAssertFalse(result.isLegacyIdentity)
    }

    func testAuthenticationTagMatchesKnownVector() throws {
        let secret = Data((64..<96).map { UInt8($0) })
        let nonce = Data((112..<128).map { UInt8($0) })
        let tag = try HandshakeCodec.authenticationTag(
            deviceSecret: secret,
            deviceId: "device-1",
            deviceName: "Pixel 9",
            clientNonce: nonce
        )
        XCTAssertEqual(
            Array(tag),
            [180, 46, 183, 187, 131, 246, 175, 68, 32, 113, 61, 165, 66, 121, 42, 33,
             75, 124, 70, 165, 219, 25, 187, 149, 238, 172, 245, 146, 190, 148, 44, 177]
        )
        XCTAssertTrue(HandshakeCodec.validateAuthenticationTag(tag, deviceSecret: secret, deviceId: "device-1", deviceName: "Pixel 9", clientNonce: nonce))
        XCTAssertFalse(HandshakeCodec.validateAuthenticationTag(Data(repeating: 0, count: 32), deviceSecret: secret, deviceId: "device-1", deviceName: "Pixel 9", clientNonce: nonce))
    }

    func testReadsV2PrefixAndNameLength() throws {
        let deviceName = "Pixel 9"
        var bytes: [UInt8] = [0x53, 0x53, 0x57, 0x42]
        bytes.append(contentsOf: (0..<32).map { UInt8($0) })
        bytes.append(UInt8(deviceName.utf8.count))

        XCTAssertEqual(try HandshakeCodec.requestFormat(fromPrefix: Data(bytes)), .deviceId)
        XCTAssertTrue(try HandshakeCodec.isV2Prefix(Data(bytes)))
        XCTAssertEqual(try HandshakeCodec.nameLength(fromPrefix: Data(bytes)), deviceName.utf8.count)
    }

    func testRejectsBadMagic() {
        var bytes: [UInt8] = [0x58, 0x58, 0x58, 0x58]
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 32))
        bytes.append(1)
        bytes.append(0x41)
        XCTAssertThrowsError(try HandshakeCodec.parseRequest(Data(bytes))) { e in
            XCTAssertEqual(e as? HandshakeError, .invalidMagic)
        }
    }

    func testRejectsZeroNameLength() {
        var bytes: [UInt8] = [0x53, 0x53, 0x57, 0x41]
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 32))
        bytes.append(0)
        XCTAssertThrowsError(try HandshakeCodec.parseRequest(Data(bytes))) { e in
            XCTAssertEqual(e as? HandshakeError, .invalidName)
        }
    }

    func testRejectsNameLengthGreaterThan64() {
        var bytes: [UInt8] = [0x53, 0x53, 0x57, 0x41]
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 32))
        bytes.append(65)
        bytes.append(contentsOf: [UInt8](repeating: 0x41, count: 65))
        XCTAssertThrowsError(try HandshakeCodec.parseRequest(Data(bytes))) { e in
            XCTAssertEqual(e as? HandshakeError, .invalidName)
        }
    }

    func testEncodeOKResponse() {
        let bytes = HandshakeCodec.encodeResponse(status: .ok)
        XCTAssertEqual(Array(bytes), [0x53, 0x53, 0x57, 0x52, 0x00])
    }

    func testEncodeV2AcceptResponseIncludesSessionCredentials() throws {
        let credentials = try RemoteSessionCredentials(
            sessionId: Data((0..<16).map { UInt8($0) }),
            inputToken: Data((32..<64).map { UInt8($0) }),
            deviceId: "device-1",
            expiresAt: Date(timeIntervalSince1970: 100)
        )

        let bytes = HandshakeCodec.encodeV2AcceptResponse(credentials: credentials)
        XCTAssertEqual(Array(bytes.prefix(5)), [0x53, 0x53, 0x57, 0x52, 0x00])
        XCTAssertEqual(bytes.count, 5 + 16 + 32)
        XCTAssertEqual(bytes.subdata(in: 5..<21), credentials.sessionId)
        XCTAssertEqual(bytes.subdata(in: 21..<53), credentials.inputToken)
    }

    func testEncodeRejectedResponse() {
        XCTAssertEqual(Array(HandshakeCodec.encodeResponse(status: .invalidToken)), [0x53, 0x53, 0x57, 0x52, 0x01])
        XCTAssertEqual(Array(HandshakeCodec.encodeResponse(status: .invalidMagic)), [0x53, 0x53, 0x57, 0x52, 0x02])
        XCTAssertEqual(Array(HandshakeCodec.encodeResponse(status: .invalidName)), [0x53, 0x53, 0x57, 0x52, 0x03])
        XCTAssertEqual(Array(HandshakeCodec.encodeResponse(status: .deviceRevoked)), [0x53, 0x53, 0x57, 0x52, 0x04])
    }

    private func appendStringField(_ value: String, to bytes: inout [UInt8]) {
        let field = Array(value.utf8)
        bytes.append(UInt8(field.count))
        bytes.append(contentsOf: field)
    }
}
