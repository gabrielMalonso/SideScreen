import XCTest
@testable import SideScreen

final class PairedDeviceStoreTests: XCTestCase {
    private func freshStore() -> PairedDeviceStore {
        let suite = "PairedDeviceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PairedDeviceStore(defaults: defaults)
    }

    func testStartsEmpty() {
        XCTAssertEqual(freshStore().all().count, 0)
    }

    func testUpsertAdds() {
        let store = freshStore()
        let secret = Data(repeating: 7, count: 32)
        store.upsert(id: "device-1", name: "iPad Air", deviceSecret: secret, lastConnected: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.id, "device-1")
        XCTAssertEqual(store.all().first?.name, "iPad Air")
        XCTAssertEqual(store.deviceSecret(id: "device-1"), secret)
    }

    func testUpsertUpdatesExisting() {
        let store = freshStore()
        store.upsert(id: "device-1", name: "iPad Air", lastConnected: Date(timeIntervalSince1970: 1000))
        store.upsert(id: "device-1", name: "Gabriel Tablet", lastConnected: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.name, "Gabriel Tablet")
        XCTAssertEqual(store.all().first?.lastConnected.timeIntervalSince1970, 2000)
    }

    func testRevokePreventsDeviceUse() {
        let store = freshStore()
        store.upsert(id: "device-1", name: "iPad Air", lastConnected: Date())
        store.upsert(id: "device-2", name: "Pixel Tablet", lastConnected: Date())
        store.revoke(id: "device-1")
        XCTAssertTrue(store.isRevoked(id: "device-1"))
        XCTAssertFalse(store.isRevoked(id: "device-2"))
        XCTAssertEqual(store.all().count, 2)
    }

    func testRestoreAllowsRevokedDeviceAgain() {
        let store = freshStore()
        store.upsert(id: "device-1", name: "iPad Air", lastConnected: Date())
        store.revoke(id: "device-1")
        store.restore(id: "device-1")
        XCTAssertFalse(store.isRevoked(id: "device-1"))
    }

    func testClearRemovesAll() {
        let store = freshStore()
        store.upsert(id: "device-1", name: "iPad Air", lastConnected: Date())
        store.upsert(id: "device-2", name: "Pixel Tablet", lastConnected: Date())
        store.clear()
        XCTAssertEqual(store.all().count, 0)
    }

    func testSortedByLastConnectedDescending() {
        let store = freshStore()
        store.upsert(id: "old", name: "Old", lastConnected: Date(timeIntervalSince1970: 1000))
        store.upsert(id: "new", name: "New", lastConnected: Date(timeIntervalSince1970: 9000))
        store.upsert(id: "mid", name: "Mid", lastConnected: Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(store.all().map { $0.name }, ["New", "Mid", "Old"])
    }

    func testRoundTripJSON() {
        let suite = "PairedDeviceStoreTests-RT-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let storeA = PairedDeviceStore(defaults: defaults)
        storeA.upsert(id: "device-1", name: "iPad Air", lastConnected: Date(timeIntervalSince1970: 1000))
        let storeB = PairedDeviceStore(defaults: defaults)
        XCTAssertEqual(storeB.all().first?.id, "device-1")
        XCTAssertEqual(storeB.all().first?.name, "iPad Air")
    }

    func testMigratesLegacyNameOnlyRecords() throws {
        struct LegacyDevice: Codable {
            let name: String
            let lastConnected: Date
        }

        let suite = "PairedDeviceStoreTests-Legacy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let data = try JSONEncoder().encode([LegacyDevice(name: "Old Tablet", lastConnected: Date(timeIntervalSince1970: 1000))])
        defaults.set(data, forKey: PairedDeviceStore.userDefaultsKey)

        let store = PairedDeviceStore(defaults: defaults)
        XCTAssertEqual(store.all(), [
            PairedDevice(id: "legacy:Old Tablet", name: "Old Tablet", deviceSecret: nil, lastConnected: Date(timeIntervalSince1970: 1000), revoked: false)
        ])
    }
}
