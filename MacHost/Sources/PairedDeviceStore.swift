import Foundation

struct PairedDevice: Codable, Equatable {
    let id: String
    let name: String
    let deviceSecret: Data?
    let lastConnected: Date
    let revoked: Bool
}

final class PairedDeviceStore {
    static let userDefaultsKey = "wireless.pairedDevices"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func all() -> [PairedDevice] {
        guard let data = defaults.data(forKey: Self.userDefaultsKey),
              let decoded = decodeDevices(from: data) else {
            return []
        }
        return decoded.sorted { $0.lastConnected > $1.lastConnected }
    }

    func upsert(id: String, name: String, deviceSecret: Data? = nil, lastConnected: Date) {
        var current = all()
        let existing = current.first { $0.id == id }
        let wasRevoked = existing?.revoked ?? false
        let secret = deviceSecret ?? existing?.deviceSecret
        current.removeAll { $0.id == id }
        current.append(PairedDevice(id: id, name: name, deviceSecret: secret, lastConnected: lastConnected, revoked: wasRevoked))
        save(current)
    }

    func revoke(id: String) {
        var current = all()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        let device = current[index]
        current[index] = PairedDevice(id: device.id, name: device.name, deviceSecret: device.deviceSecret, lastConnected: device.lastConnected, revoked: true)
        save(current)
    }

    func restore(id: String) {
        var current = all()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        let device = current[index]
        current[index] = PairedDevice(id: device.id, name: device.name, deviceSecret: device.deviceSecret, lastConnected: device.lastConnected, revoked: false)
        save(current)
    }

    func clear() {
        defaults.removeObject(forKey: Self.userDefaultsKey)
    }

    func isRevoked(id: String) -> Bool {
        all().first { $0.id == id }?.revoked == true
    }

    func deviceSecret(id: String) -> Data? {
        all().first { $0.id == id }?.deviceSecret
    }

    private func save(_ devices: [PairedDevice]) {
        let encoded = (try? JSONEncoder().encode(devices)) ?? Data()
        defaults.set(encoded, forKey: Self.userDefaultsKey)
    }

    private func decodeDevices(from data: Data) -> [PairedDevice]? {
        if let devices = try? JSONDecoder().decode([PairedDevice].self, from: data) {
            return devices
        }
        guard let legacy = try? JSONDecoder().decode([LegacyPairedDevice].self, from: data) else {
            return nil
        }
        let migrated = legacy.map {
            PairedDevice(id: "legacy:\($0.name)", name: $0.name, deviceSecret: nil, lastConnected: $0.lastConnected, revoked: false)
        }
        save(migrated)
        return migrated
    }
}

private struct LegacyPairedDevice: Codable {
    let name: String
    let lastConnected: Date
}
