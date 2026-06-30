import XCTest
@testable import SideScreen

final class HandshakeCodecTests: XCTestCase {
    func testParseValidRequest() throws {
        var bytes: [UInt8] = [0x53, 0x53, 0x57, 0x41]
        bytes.append(contentsOf: (0..<32).map { UInt8($0) })
        bytes.append(8)
        bytes.append(contentsOf: Array("iPad Air".utf8))
        let result = try HandshakeCodec.parseRequest(Data(bytes))
        XCTAssertEqual(result.token.count, 32)
        XCTAssertEqual(result.token.first, 0x00)
        XCTAssertEqual(result.token.last, 0x1F)
        XCTAssertEqual(result.deviceName, "iPad Air")
        XCTAssertEqual(result.deviceId, "legacy:iPad Air")
        XCTAssertNil(result.deviceSecret)
        XCTAssertTrue(result.isLegacyIdentity)
    }

    func testParseValidV2RequestWithDeviceId() throws {
        var bytes: [UInt8] = [0x53, 0x53, 0x57, 0x42]
        bytes.append(contentsOf: (0..<32).map { UInt8($0) })
        bytes.append(8)
        bytes.append(contentsOf: Array("iPad Air".utf8))
        bytes.append(8)
        bytes.append(contentsOf: Array("device-1".utf8))

        let result = try HandshakeCodec.parseRequest(Data(bytes))
        XCTAssertEqual(result.deviceName, "iPad Air")
        XCTAssertEqual(result.deviceId, "device-1")
        XCTAssertNil(result.deviceSecret)
        XCTAssertFalse(result.isLegacyIdentity)
    }

    func testParseValidV3RequestWithDeviceSecret() throws {
        let secret = Data((80..<112).map { UInt8($0) })
        let nonce = Data((112..<128).map { UInt8($0) })
        let tag = try HandshakeCodec.authenticationTag(
            deviceSecret: secret,
            deviceId: "device-1",
            deviceName: "iPad Air",
            clientNonce: nonce
        )
        var bytes: [UInt8] = [0x53, 0x53, 0x57, 0x43]
        bytes.append(contentsOf: (0..<32).map { UInt8($0) })
        bytes.append(8)
        bytes.append(contentsOf: Array("iPad Air".utf8))
        bytes.append(8)
        bytes.append(contentsOf: Array("device-1".utf8))
        bytes.append(contentsOf: secret)
        bytes.append(contentsOf: nonce)
        bytes.append(contentsOf: tag)

        let result = try HandshakeCodec.parseRequest(Data(bytes))
        XCTAssertEqual(result.deviceName, "iPad Air")
        XCTAssertEqual(result.deviceId, "device-1")
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
            deviceName: "iPad Air",
            clientNonce: nonce
        )
        XCTAssertEqual(
            Array(tag),
            [223, 220, 62, 5, 37, 190, 249, 175, 214, 53, 114, 248, 124, 48, 127, 24,
             118, 131, 59, 86, 102, 33, 141, 224, 108, 120, 103, 16, 0, 225, 115, 91]
        )
        XCTAssertTrue(HandshakeCodec.validateAuthenticationTag(tag, deviceSecret: secret, deviceId: "device-1", deviceName: "iPad Air", clientNonce: nonce))
        XCTAssertFalse(HandshakeCodec.validateAuthenticationTag(Data(repeating: 0, count: 32), deviceSecret: secret, deviceId: "device-1", deviceName: "iPad Air", clientNonce: nonce))
    }

    func testReadsV2PrefixAndNameLength() throws {
        var bytes: [UInt8] = [0x53, 0x53, 0x57, 0x42]
        bytes.append(contentsOf: (0..<32).map { UInt8($0) })
        bytes.append(8)

        XCTAssertEqual(try HandshakeCodec.requestFormat(fromPrefix: Data(bytes)), .deviceId)
        XCTAssertTrue(try HandshakeCodec.isV2Prefix(Data(bytes)))
        XCTAssertEqual(try HandshakeCodec.nameLength(fromPrefix: Data(bytes)), 8)
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
}
