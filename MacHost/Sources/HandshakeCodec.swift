import CryptoKit
import Foundation

enum HandshakeError: Error, Equatable {
    case invalidMagic
    case invalidName
    case invalidDeviceId
    case truncated
}

enum HandshakeStatus: UInt8 {
    case ok = 0x00
    case invalidToken = 0x01
    case invalidMagic = 0x02
    case invalidName = 0x03
    case deviceRevoked = 0x04
}

struct ParsedHandshake {
    let token: Data
    let deviceName: String
    let deviceId: String
    let deviceSecret: Data?
    let clientNonce: Data?
    let authTag: Data?
    let isLegacyIdentity: Bool
}

enum HandshakeCodec {
    static let requestMagic: [UInt8] = [0x53, 0x53, 0x57, 0x41]   // "SSWA" legacy
    static let requestMagicV2: [UInt8] = [0x53, 0x53, 0x57, 0x42] // "SSWB"
    static let requestMagicV3: [UInt8] = [0x53, 0x53, 0x57, 0x43] // "SSWC"
    static let responseMagic: [UInt8] = [0x53, 0x53, 0x57, 0x52]  // "SSWR"
    static let fixedPrefixLen = 4 + 32 + 1                         // magic + token + name_len
    static let deviceSecretLength = 32
    static let authNonceLength = 16
    static let authTagLength = 32

    enum RequestFormat {
        case legacy
        case deviceId
        case deviceSecret
    }

    static func requestFormat(fromPrefix data: Data) throws -> RequestFormat {
        guard data.count >= fixedPrefixLen else { throw HandshakeError.truncated }
        let magic = Array(Array(data)[0..<4])
        if magic == requestMagicV3 { return .deviceSecret }
        if magic == requestMagicV2 { return .deviceId }
        if magic == requestMagic { return .legacy }
        throw HandshakeError.invalidMagic
    }

    static func isV2Prefix(_ data: Data) throws -> Bool {
        try requestFormat(fromPrefix: data) != .legacy
    }

    static func nameLength(fromPrefix data: Data) throws -> Int {
        guard data.count >= fixedPrefixLen else { throw HandshakeError.truncated }
        let bytes = Array(data)
        let magic = Array(bytes[0..<4])
        guard magic == requestMagic || magic == requestMagicV2 || magic == requestMagicV3 else {
            throw HandshakeError.invalidMagic
        }
        let nameLen = Int(bytes[36])
        guard nameLen >= 1 && nameLen <= 64 else { throw HandshakeError.invalidName }
        return nameLen
    }

    /// Parses:
    /// - v1 `[SSWA][token 32][name_len 1][name N]`
    /// - v2 `[SSWB][token 32][name_len 1][name N][device_id_len 1][device_id N]`
    /// - v3 `[SSWC][token 32][name_len 1][name N][device_id_len 1][device_id N][device_secret 32][nonce 16][hmac 32]`
    static func parseRequest(_ data: Data) throws -> ParsedHandshake {
        guard data.count >= fixedPrefixLen else { throw HandshakeError.truncated }
        let bytes = Array(data)
        let magic = Array(bytes[0..<4])
        let format: RequestFormat
        if magic == requestMagicV2 {
            format = .deviceId
        } else if magic == requestMagicV3 {
            format = .deviceSecret
        } else if magic == requestMagic {
            format = .legacy
        } else {
            throw HandshakeError.invalidMagic
        }
        let token = Data(bytes[4..<36])
        let nameLen = Int(bytes[36])
        guard nameLen >= 1 && nameLen <= 64 else { throw HandshakeError.invalidName }
        let nameEnd = fixedPrefixLen + nameLen
        guard data.count >= nameEnd else { throw HandshakeError.truncated }
        let nameBytes = Array(bytes[37..<(37 + nameLen)])
        guard let name = String(bytes: nameBytes, encoding: .utf8), !name.isEmpty else {
            throw HandshakeError.invalidName
        }
        if format == .legacy {
            return ParsedHandshake(
                token: token,
                deviceName: name,
                deviceId: "legacy:\(name)",
                deviceSecret: nil,
                clientNonce: nil,
                authTag: nil,
                isLegacyIdentity: true
            )
        }

        guard data.count >= nameEnd + 1 else { throw HandshakeError.truncated }
        let deviceIdLen = Int(bytes[nameEnd])
        guard deviceIdLen >= 1 && deviceIdLen <= 64 else { throw HandshakeError.invalidDeviceId }
        guard data.count >= nameEnd + 1 + deviceIdLen else { throw HandshakeError.truncated }
        let deviceIdBytes = Array(bytes[(nameEnd + 1)..<(nameEnd + 1 + deviceIdLen)])
        guard let deviceId = String(bytes: deviceIdBytes, encoding: .utf8), !deviceId.isEmpty else {
            throw HandshakeError.invalidDeviceId
        }
        let secretStart = nameEnd + 1 + deviceIdLen
        let deviceSecret: Data?
        let clientNonce: Data?
        let authTag: Data?
        if format == .deviceSecret {
            guard data.count >= secretStart + deviceSecretLength else { throw HandshakeError.truncated }
            deviceSecret = Data(bytes[secretStart..<(secretStart + deviceSecretLength)])
            let nonceStart = secretStart + deviceSecretLength
            guard data.count >= nonceStart + authNonceLength + authTagLength else { throw HandshakeError.truncated }
            clientNonce = Data(bytes[nonceStart..<(nonceStart + authNonceLength)])
            let tagStart = nonceStart + authNonceLength
            authTag = Data(bytes[tagStart..<(tagStart + authTagLength)])
        } else {
            deviceSecret = nil
            clientNonce = nil
            authTag = nil
        }
        return ParsedHandshake(
            token: token,
            deviceName: name,
            deviceId: deviceId,
            deviceSecret: deviceSecret,
            clientNonce: clientNonce,
            authTag: authTag,
            isLegacyIdentity: false
        )
    }

    static func encodeResponse(status: HandshakeStatus) -> Data {
        Data(responseMagic + [status.rawValue])
    }

    static func encodeV2AcceptResponse(credentials: RemoteSessionCredentials) -> Data {
        Data(responseMagic + [HandshakeStatus.ok.rawValue]) + credentials.sessionId + credentials.inputToken
    }

    static func authMessage(deviceId: String, deviceName: String, clientNonce: Data) throws -> Data {
        let deviceIdBytes = Array(deviceId.utf8)
        let nameBytes = Array(deviceName.utf8)
        guard (1...64).contains(deviceIdBytes.count) else { throw HandshakeError.invalidDeviceId }
        guard (1...64).contains(nameBytes.count) else { throw HandshakeError.invalidName }
        guard clientNonce.count == authNonceLength else { throw HandshakeError.truncated }

        var data = Data(requestMagicV3)
        data.append(UInt8(deviceIdBytes.count))
        data.append(contentsOf: deviceIdBytes)
        data.append(UInt8(nameBytes.count))
        data.append(contentsOf: nameBytes)
        data.append(clientNonce)
        return data
    }

    static func authenticationTag(deviceSecret: Data, deviceId: String, deviceName: String, clientNonce: Data) throws -> Data {
        guard deviceSecret.count == deviceSecretLength else { throw HandshakeError.truncated }
        let key = SymmetricKey(data: deviceSecret)
        let message = try authMessage(deviceId: deviceId, deviceName: deviceName, clientNonce: clientNonce)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }

    static func validateAuthenticationTag(
        _ tag: Data?,
        deviceSecret: Data?,
        deviceId: String,
        deviceName: String,
        clientNonce: Data?
    ) -> Bool {
        guard let tag, let deviceSecret, let clientNonce, tag.count == authTagLength else {
            return false
        }
        guard let expected = try? authenticationTag(
            deviceSecret: deviceSecret,
            deviceId: deviceId,
            deviceName: deviceName,
            clientNonce: clientNonce
        ) else {
            return false
        }
        return constantTimeEquals(tag, expected)
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(lhs, rhs) {
            diff |= a ^ b
        }
        return diff == 0
    }
}
