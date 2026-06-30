import XCTest
@testable import SideScreen

final class RemoteSessionStoreTests: XCTestCase {
    func testCreateProducesFixedSizeCredentials() throws {
        let store = RemoteSessionStore(ttl: 60)
        let credentials = try store.create(deviceId: "device-1", now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(credentials.deviceId, "device-1")
        XCTAssertEqual(credentials.sessionId.count, RemoteSessionCredentials.sessionIdLength)
        XCTAssertEqual(credentials.inputToken.count, RemoteSessionCredentials.inputTokenLength)
        XCTAssertEqual(credentials.expiresAt.timeIntervalSince1970, 160)
    }

    func testValidatesInputTokenBeforeExpiry() throws {
        let store = RemoteSessionStore(ttl: 60)
        let credentials = try store.create(deviceId: "device-1", now: Date(timeIntervalSince1970: 100))

        XCTAssertTrue(store.validateInputToken(credentials.inputToken, deviceId: "device-1", sessionId: credentials.sessionId, now: Date(timeIntervalSince1970: 120)))
        XCTAssertFalse(store.validateInputToken(credentials.inputToken, deviceId: "device-1", sessionId: Data(repeating: 0, count: 16), now: Date(timeIntervalSince1970: 120)))
        XCTAssertFalse(store.validateInputToken(Data(repeating: 0, count: 32), deviceId: "device-1", sessionId: credentials.sessionId, now: Date(timeIntervalSince1970: 120)))
        XCTAssertFalse(store.validateInputToken(credentials.inputToken, deviceId: "device-2", sessionId: credentials.sessionId, now: Date(timeIntervalSince1970: 120)))
    }

    func testRejectsExpiredCredentials() throws {
        let store = RemoteSessionStore(ttl: 60)
        let credentials = try store.create(deviceId: "device-1", now: Date(timeIntervalSince1970: 100))

        XCTAssertFalse(store.validateInputToken(credentials.inputToken, deviceId: "device-1", sessionId: credentials.sessionId, now: Date(timeIntervalSince1970: 161)))
    }

    func testRevokeRemovesSession() throws {
        let store = RemoteSessionStore(ttl: 60)
        let credentials = try store.create(deviceId: "device-1", now: Date(timeIntervalSince1970: 100))

        store.revoke(deviceId: "device-1")
        XCTAssertFalse(store.validateInputToken(credentials.inputToken, deviceId: "device-1", sessionId: credentials.sessionId, now: Date(timeIntervalSince1970: 120)))
    }
}
