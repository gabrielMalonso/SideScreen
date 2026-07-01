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
    let directProbeSucceeded: Bool
    let helperStatus: SideScreenVirtualHIDHelperStatus?
    let probeFailure: String?

    var installed: Bool {
        managerInstalled && daemonInstalled
    }

    var canUseFromCurrentProcess: Bool {
        installed && daemonRunning && socketAvailable && getuid() == 0 && directProbeSucceeded
    }

    var canUseThroughHelper: Bool {
        installed && daemonRunning && helperSocketAvailable && helperStatus?.upstreamAvailable == true
    }

    var fallbackReason: String {
        if canUseFromCurrentProcess || canUseThroughHelper { return "" }
        return detail
    }

    var title: String {
        if canUseFromCurrentProcess { return "Ready" }
        if canUseThroughHelper { return "Ready via helper" }
        if !installed { return "Not installed" }
        if !daemonRunning { return "Daemon not running" }
        if helperSocketAvailable && helperStatus == nil { return "Helper legacy or not responding" }
        if helperBinaryInstalled && helperLaunchDaemonInstalled { return "Helper stopped" }
        if !socketAvailable { return "Socket unavailable" }
        return "Requires privileged helper"
    }

    var detail: String {
        if canUseFromCurrentProcess {
            return "Karabiner VirtualHID is reachable from this process."
        }
        if canUseThroughHelper {
            let version = helperStatus.map { " Helper v\($0.helperBuildVersion)." } ?? ""
            return "SideScreen privileged helper responded and can reach Karabiner VirtualHID.\(version)"
        }
        if !installed {
            return "Install Karabiner-DriverKit-VirtualHIDDevice to use hardware-like keyboard and mouse input."
        }
        if !daemonRunning {
            return "Start Karabiner-VirtualHIDDevice-Daemon. The driver accepts input only through its daemon."
        }
        if helperSocketAvailable && helperStatus == nil {
            return probeFailure ?? "SideScreen helper did not answer the status probe. Reinstall the helper so the app and helper speak the same protocol."
        }
        if helperSocketAvailable && helperStatus?.upstreamAvailable == false {
            return "SideScreen helper is running, but Karabiner VirtualHID did not answer the helper probe."
        }
        if helperBinaryInstalled && helperLaunchDaemonInstalled {
            return "SideScreen helper is installed but its socket is not available. Try reinstalling or restarting the helper."
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
        let helperStatus = VirtualHIDHelperInstaller.status()
        let directProbeSucceeded: Bool
        var probeFailure: String?
        if getuid() == 0 && hasSocket() {
            do {
                try KarabinerVirtualHIDServiceClient().probe()
                directProbeSucceeded = true
            } catch {
                directProbeSucceeded = false
                probeFailure = "Karabiner VirtualHID direct probe failed: \(error)."
            }
        } else {
            directProbeSucceeded = false
        }

        let liveHelperStatus: SideScreenVirtualHIDHelperStatus?
        if helperStatus.helperSocketAvailable {
            do {
                liveHelperStatus = try SideScreenVirtualHIDHelperClient().status()
            } catch {
                liveHelperStatus = nil
                probeFailure = "SideScreen helper status probe failed: \(error)."
            }
        } else {
            liveHelperStatus = nil
        }

        return KarabinerVirtualHIDStatus(
            managerInstalled: FileManager.default.fileExists(atPath: managerPath),
            daemonInstalled: FileManager.default.fileExists(atPath: daemonPath),
            daemonRunning: processIsRunning(named: "Karabiner-VirtualHIDDevice-Daemon"),
            socketAvailable: hasSocket(),
            helperBinaryInstalled: helperStatus.helperBinaryInstalled,
            helperLaunchDaemonInstalled: helperStatus.launchDaemonInstalled,
            helperSocketAvailable: helperStatus.helperSocketAvailable,
            directProbeSucceeded: directProbeSucceeded,
            helperStatus: liveHelperStatus,
            probeFailure: probeFailure
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
    let requestedBackend: InputBackendMode
    let activeBackend: ActiveInputBackend
    let fallbackReason: String?
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
            InputIngress(
                downstream: KarabinerVirtualHIDBackend(client: client) { failure in
                    debugLog("VirtualHID active backend degraded: \(failure)")
                },
                onDiagnosticsChanged: onDiagnosticsChanged
            )
        }

        switch mode {
        case .automatic:
            if status.canUseFromCurrentProcess {
                debugLog("VirtualHID is ready — using Karabiner VirtualHID backend")
                return InputBackendSelection(
                    backend: virtualHIDIngress(client: KarabinerVirtualHIDServiceClient()),
                    requestedBackend: mode,
                    activeBackend: .virtualHID,
                    fallbackReason: nil,
                    status: status
                )
            }
            if status.canUseThroughHelper {
                debugLog("VirtualHID helper is ready — using SideScreen VirtualHID helper")
                return InputBackendSelection(
                    backend: virtualHIDIngress(client: SideScreenVirtualHIDHelperClient()),
                    requestedBackend: mode,
                    activeBackend: .virtualHID,
                    fallbackReason: nil,
                    status: status
                )
            }
            debugLog("VirtualHID unavailable — using CGEvent fallback: \(status.detail)")
            return InputBackendSelection(
                backend: cgeventIngress(),
                requestedBackend: mode,
                activeBackend: .cgevent,
                fallbackReason: status.fallbackReason,
                status: status
            )
        case .cgevent:
            return InputBackendSelection(
                backend: cgeventIngress(),
                requestedBackend: mode,
                activeBackend: .cgevent,
                fallbackReason: nil,
                status: status
            )
        case .virtualHID:
            if status.canUseFromCurrentProcess {
                debugLog("VirtualHID requested — using Karabiner VirtualHID backend")
                return InputBackendSelection(
                    backend: virtualHIDIngress(client: KarabinerVirtualHIDServiceClient()),
                    requestedBackend: mode,
                    activeBackend: .virtualHID,
                    fallbackReason: nil,
                    status: status
                )
            }
            if status.canUseThroughHelper {
                debugLog("VirtualHID requested — using SideScreen VirtualHID helper")
                return InputBackendSelection(
                    backend: virtualHIDIngress(client: SideScreenVirtualHIDHelperClient()),
                    requestedBackend: mode,
                    activeBackend: .virtualHID,
                    fallbackReason: nil,
                    status: status
                )
            }
            debugLog("VirtualHID requested but unavailable: \(status.detail)")
            return InputBackendSelection(
                backend: cgeventIngress(),
                requestedBackend: mode,
                activeBackend: .cgevent,
                fallbackReason: "Virtual HID requested but unavailable: \(status.detail)",
                status: status
            )
        }
    }
}
