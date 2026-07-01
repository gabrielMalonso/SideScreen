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
    let helperBinaryInstalled: Bool
    let helperLaunchDaemonInstalled: Bool
    let helperSocketAvailable: Bool

    var installed: Bool {
        managerInstalled && daemonInstalled
    }

    var canUseFromCurrentProcess: Bool {
        installed && daemonRunning && socketAvailable && getuid() == 0
    }

    var canUseThroughHelper: Bool {
        installed && daemonRunning && socketAvailable && helperSocketAvailable
    }

    var title: String {
        if canUseFromCurrentProcess { return "Ready" }
        if canUseThroughHelper { return "Ready via helper" }
        if !installed { return "Not installed" }
        if !daemonRunning { return "Daemon not running" }
        if !socketAvailable { return "Socket unavailable" }
        if helperBinaryInstalled && helperLaunchDaemonInstalled { return "Helper stopped" }
        return "Requires privileged helper"
    }

    var detail: String {
        if canUseFromCurrentProcess {
            return "Karabiner VirtualHID is reachable from this process."
        }
        if canUseThroughHelper {
            return "SideScreen privileged helper is running and can reach Karabiner VirtualHID."
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
        if helperBinaryInstalled && helperLaunchDaemonInstalled {
            return "SideScreen helper is installed but its socket is not available. Try reinstalling or restarting the helper."
        }
        return "Karabiner VirtualHID is installed, but the service socket is root-only. SideScreen is using CGEvent until a privileged Mac helper is installed."
    }
}

enum KarabinerVirtualHIDDetector {
    static let managerPath = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
    static let daemonPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app"
    static let socketPath = "/Library/Application Support/org.pqrs/tmp/rootonly/karabiner_virtual_hid_device_service.sock"

    static func status() -> KarabinerVirtualHIDStatus {
        let helperStatus = VirtualHIDHelperInstaller.status()
        return KarabinerVirtualHIDStatus(
            managerInstalled: FileManager.default.fileExists(atPath: managerPath),
            daemonInstalled: FileManager.default.fileExists(atPath: daemonPath),
            daemonRunning: processIsRunning(named: "Karabiner-VirtualHIDDevice-Daemon"),
            socketAvailable: hasSocket(),
            helperBinaryInstalled: helperStatus.helperBinaryInstalled,
            helperLaunchDaemonInstalled: helperStatus.launchDaemonInstalled,
            helperSocketAvailable: helperStatus.helperSocketAvailable
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
    static func make(
        mode: InputBackendMode,
        onDiagnosticsChanged: ((InputIngressDiagnostics) -> Void)? = nil
    ) -> InputBackendSelection {
        let status = KarabinerVirtualHIDDetector.status()
        func cgeventIngress() -> InputBackend {
            InputIngress(downstream: CGEventInputBackend(), onDiagnosticsChanged: onDiagnosticsChanged)
        }
        func virtualHIDIngress(client: VirtualHIDReportClient) -> InputBackend {
            InputIngress(downstream: KarabinerVirtualHIDBackend(client: client), onDiagnosticsChanged: onDiagnosticsChanged)
        }

        switch mode {
        case .automatic:
            if status.canUseFromCurrentProcess {
                debugLog("VirtualHID is ready — using Karabiner VirtualHID backend")
                return InputBackendSelection(
                    backend: virtualHIDIngress(client: KarabinerVirtualHIDServiceClient()),
                    activeBackend: .virtualHID,
                    status: status
                )
            }
            if status.canUseThroughHelper {
                debugLog("VirtualHID helper is ready — using SideScreen VirtualHID helper")
                return InputBackendSelection(
                    backend: virtualHIDIngress(client: SideScreenVirtualHIDHelperClient()),
                    activeBackend: .virtualHID,
                    status: status
                )
            }
            debugLog("VirtualHID unavailable — using CGEvent fallback: \(status.detail)")
            return InputBackendSelection(
                backend: cgeventIngress(),
                activeBackend: .cgevent,
                status: status
            )
        case .cgevent:
            return InputBackendSelection(
                backend: cgeventIngress(),
                activeBackend: .cgevent,
                status: status
            )
        case .virtualHID:
            if status.canUseFromCurrentProcess {
                debugLog("VirtualHID requested — using Karabiner VirtualHID backend")
                return InputBackendSelection(
                    backend: virtualHIDIngress(client: KarabinerVirtualHIDServiceClient()),
                    activeBackend: .virtualHID,
                    status: status
                )
            }
            if status.canUseThroughHelper {
                debugLog("VirtualHID requested — using SideScreen VirtualHID helper")
                return InputBackendSelection(
                    backend: virtualHIDIngress(client: SideScreenVirtualHIDHelperClient()),
                    activeBackend: .virtualHID,
                    status: status
                )
            }
            debugLog("VirtualHID requested but unavailable: \(status.detail)")
            return InputBackendSelection(
                backend: cgeventIngress(),
                activeBackend: .cgevent,
                status: status
            )
        }
    }
}
