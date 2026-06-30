import Foundation
import Security

struct RemoteSessionCredentials: Equatable {
    static let sessionIdLength = 16
    static let inputTokenLength = 32

    let sessionId: Data
    let inputToken: Data
    let deviceId: String
    let expiresAt: Date

    init(sessionId: Data, inputToken: Data, deviceId: String, expiresAt: Date) throws {
        guard sessionId.count == Self.sessionIdLength,
              inputToken.count == Self.inputTokenLength,
              !deviceId.isEmpty else {
            throw RemoteSessionStoreError.invalidCredentials
        }
        self.sessionId = sessionId
        self.inputToken = inputToken
        self.deviceId = deviceId
        self.expiresAt = expiresAt
    }
}

enum RemoteSessionStoreError: Error, Equatable {
    case randomGenerationFailed
    case invalidCredentials
}

final class RemoteSessionStore {
    private let lock = NSLock()
    private var sessionsByDeviceId: [String: RemoteSessionCredentials] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 8 * 60 * 60) {
        self.ttl = ttl
    }

    func create(deviceId: String, now: Date = Date()) throws -> RemoteSessionCredentials {
        let credentials = try RemoteSessionCredentials(
            sessionId: Self.randomData(count: RemoteSessionCredentials.sessionIdLength),
            inputToken: Self.randomData(count: RemoteSessionCredentials.inputTokenLength),
            deviceId: deviceId,
            expiresAt: now.addingTimeInterval(ttl)
        )
        lock.lock()
        sessionsByDeviceId[deviceId] = credentials
        lock.unlock()
        return credentials
    }

    func validateInputToken(_ token: Data, deviceId: String, sessionId: Data?, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let credentials = sessionsByDeviceId[deviceId] else {
            return false
        }
        if credentials.expiresAt <= now {
            sessionsByDeviceId.removeValue(forKey: deviceId)
            return false
        }
        guard sessionId == credentials.sessionId else {
            return false
        }
        return WirelessAuth.validate(token, expected: credentials.inputToken)
    }

    func revoke(deviceId: String) {
        lock.lock()
        sessionsByDeviceId.removeValue(forKey: deviceId)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        sessionsByDeviceId.removeAll()
        lock.unlock()
    }

    private static func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw RemoteSessionStoreError.randomGenerationFailed
        }
        return Data(bytes)
    }
}
