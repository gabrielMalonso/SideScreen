import Foundation

enum InputBackendMode: String, Codable, CaseIterable {
    case automatic
    case cgevent
    case virtualHID

    var title: String {
        switch self {
        case .automatic: return "Auto"
        case .cgevent: return "CGEvent"
        case .virtualHID: return "Virtual HID"
        }
    }
}

enum ActiveInputBackend: UInt8 {
    case none = 0
    case cgevent = 1
    case virtualHID = 2

    var title: String {
        switch self {
        case .none: return "None"
        case .cgevent: return "CGEvent"
        case .virtualHID: return "Virtual HID"
        }
    }
}

struct KarabinerVirtualHIDStatus {
    let managerInstalled: Bool
    let daemonInstalled: Bool
    let daemonRunning: Bool
    let socketAvailable: Bool

    var installed: Bool {
        managerInstalled && daemonInstalled
    }

    var canUseFromCurrentProcess: Bool {
        installed && daemonRunning && socketAvailable && getuid() == 0
    }

    var title: String {
        if canUseFromCurrentProcess { return "Ready" }
        if !installed { return "Not installed" }
        if !daemonRunning { return "Daemon not running" }
        if !socketAvailable { return "Socket unavailable" }
        return "Requires privileged helper"
    }

    var detail: String {
        if canUseFromCurrentProcess {
            return "Karabiner VirtualHID is reachable from this process."
        }
        if !installed {
            return "Install Karabiner-DriverKit-VirtualHIDDevice to use hardware-like keyboard and mouse input."
        }
        if !daemonRunning {
            return "Start Karabiner-VirtualHIDDevice-Daemon. The driver accepts input only through its daemon."
        }
        if !socketAvailable {
            return "The daemon socket was not found at /Library/Application Support/org.pqrs/tmp/rootonly/karabiner_virtual_hid_device_service.sock."
        }
        return "Karabiner VirtualHID is installed, but the service socket is root-only. SideScreen is using CGEvent until a privileged Mac helper is installed."
    }
}

enum KarabinerVirtualHIDDetector {
    static let managerPath = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
    static let daemonPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app"
    static let socketPath = "/Library/Application Support/org.pqrs/tmp/rootonly/karabiner_virtual_hid_device_service.sock"

    static func status() -> KarabinerVirtualHIDStatus {
        KarabinerVirtualHIDStatus(
            managerInstalled: FileManager.default.fileExists(atPath: managerPath),
            daemonInstalled: FileManager.default.fileExists(atPath: daemonPath),
            daemonRunning: processIsRunning(named: "Karabiner-VirtualHIDDevice-Daemon"),
            socketAvailable: hasSocket()
        )
    }

    private static func hasSocket() -> Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    private static func processIsRunning(named processName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", processName]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

struct InputBackendSelection {
    let backend: InputBackend
    let activeBackend: ActiveInputBackend
    let status: KarabinerVirtualHIDStatus
}

enum InputBackendFactory {
    static func make(mode: InputBackendMode) -> InputBackendSelection {
        let status = KarabinerVirtualHIDDetector.status()

        switch mode {
        case .automatic:
            if status.canUseFromCurrentProcess {
                debugLog("VirtualHID is ready, but SideScreen VirtualHID client is not linked yet — using CGEvent fallback")
            }
            return InputBackendSelection(
                backend: InputIngress(downstream: CGEventInputBackend()),
                activeBackend: .cgevent,
                status: status
            )
        case .cgevent:
            return InputBackendSelection(
                backend: InputIngress(downstream: CGEventInputBackend()),
                activeBackend: .cgevent,
                status: status
            )
        case .virtualHID:
            if !status.canUseFromCurrentProcess {
                debugLog("VirtualHID requested but unavailable: \(status.detail)")
            } else {
                debugLog("VirtualHID requested but SideScreen VirtualHID client is not linked yet — using CGEvent fallback")
            }
            return InputBackendSelection(
                backend: InputIngress(downstream: CGEventInputBackend()),
                activeBackend: .cgevent,
                status: status
            )
        }
    }
}
