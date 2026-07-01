import Cocoa
import SwiftUI
import Combine
import ApplicationServices
import os.log
@preconcurrency import ScreenCaptureKit

// Debug file logger - writes to /tmp/sidescreen.log
func debugLog(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(timestamp)] \(message)\n"
    print(message)
    if let data = line.data(using: .utf8) {
        let url = URL(fileURLWithPath: "/tmp/sidescreen.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - Gesture State Machine

enum GestureState {
    case idle
    case pending          // Touch down, waiting to determine gesture
    case scrolling        // 1-finger scroll
    case longPressReady   // Long press detected, waiting for drag or release
    case dragging         // Long press + drag (left mouse drag)
    case twoFingerScroll  // 2-finger scroll
    case pinching         // Pinch zoom
}

struct GestureThresholds {
    static let tapMaxDistance: CGFloat = 15
    static let tapMaxTime: UInt64 = 250_000_000       // 250ms
    static let doubleTapMaxTime: UInt64 = 400_000_000  // 400ms
    static let doubleTapMaxDistance: CGFloat = 20
    static let longPressTime: UInt64 = 500_000_000     // 500ms
    static let scrollSensitivity: CGFloat = 1.2
    static let pinchMinDistance: CGFloat = 20
    static let minTouchInterval: UInt64 = 8_000_000    // ~120Hz
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var streamingServer: StreamingServer?
    var inputServer: InputServer?
    var screenCapture: ScreenCapture?
    var virtualDisplayManager: VirtualDisplayManager?
    private var activeDisplaySource: DisplaySource?
    var settings = DisplaySettings()
    var settingsWindow: SettingsWindowController?
    var statusItem: NSStatusItem?
    let pairedDeviceStore = PairedDeviceStore()
    private let remoteSessionStore = RemoteSessionStore()
    private let displaySourceCatalog = DisplaySourceCatalog()
    /// Identity of the wireless device currently streaming (nil when no wireless client is active).
    /// Used to roll its `lastConnected` timestamp forward every status refresh tick so the UI
    /// shows "just now" while connected and freezes at the disconnect moment afterward.
    private var currentWirelessDevice: PairedDevice?
    private var wirelessConnectionGeneration: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()
    private var permissionCheckTimer: Timer?
    private var statusRefreshTimer: Timer?
    private var pendingPipelineRestart: Task<Void, Never>?
    private var shouldStartFromLaunchArguments = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("✅ App launched")

        // Create menu bar item
        setupMenuBar()

        // Setup settings window
        setupSettingsWindow()

        // Setup settings observers
        setupSettingsObservers()

        // Check permissions
        Task {
            await checkPermissions()
        }

        // Periodic status refresh for the per-mode checklist (ADB / WiFi / Listening IP).
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusIndicators()
            }
        }
        // Initial refresh so the UI isn't blank for 2 seconds.
        Task { @MainActor in
            refreshStatusIndicators()
        }

        // Show settings window
        showSettings()

        Task { @MainActor in
            applyLaunchArguments(ProcessInfo.processInfo.arguments)
            guard shouldStartFromLaunchArguments else { return }
            debugLog("Launch argument requested server start")
            await checkPermissions()
            await startServer()
        }
    }

    @MainActor
    private func applyLaunchArguments(_ arguments: [String]) {
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--start":
                shouldStartFromLaunchArguments = true
            case "--usb":
                settings.connectionMode = .usb
            case "--wireless":
                settings.connectionMode = .wireless
            case "--lan":
                settings.connectionMode = .wireless
                settings.endpointMode = .lan
            case "--tailnet":
                settings.connectionMode = .wireless
                settings.endpointMode = .tailnet
            case "--manual-endpoint":
                settings.connectionMode = .wireless
                settings.endpointMode = .manual
            case "--tailnet-host":
                if index + 1 < arguments.count {
                    index += 1
                    settings.connectionMode = .wireless
                    settings.endpointMode = .tailnet
                    settings.tailnetHost = arguments[index]
                } else {
                    debugLog("Ignoring --tailnet-host without value")
                }
            default:
                break
            }
            index += 1
        }
    }

    @MainActor
    private func refreshStatusIndicators() {
        settings.adbInstalled = StatusDetector.adbInstalled()
        settings.wifiConnected = StatusDetector.wifiReachable()
        settings.listeningAddress = LANAddressResolver.primaryIPv4()
        refreshVirtualHIDStatus()

        // While a wireless client is actively streaming, keep its lastConnected
        // rolling forward so the UI shows "just now". On disconnect, the
        // onClientDisconnected handler clears currentWirelessDevice — from that
        // point lastConnected stays frozen at the disconnect moment, so the
        // "X minutes ago" label counts up correctly.
        if let device = currentWirelessDevice {
            pairedDeviceStore.upsert(id: device.id, name: device.name, deviceSecret: device.deviceSecret, lastConnected: Date())
        }

        let port = Int(settings.port)
        Task.detached { [weak self] in
            let devices = StatusDetector.usbDevices()
            let reverseOK = StatusDetector.adbReverseConfigured(port: port)
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.settings.usbDeviceConnected = !devices.isEmpty
                self.settings.adbReverseConfigured = reverseOK
            }
        }
    }

    @MainActor
    private func refreshVirtualHIDStatus() {
        let status = KarabinerVirtualHIDDetector.status()
        settings.virtualHIDStatus = status.title
        settings.virtualHIDStatusDetail = status.detail
        settings.virtualHIDHelperInstalled = status.helperBinaryInstalled && status.helperLaunchDaemonInstalled
        if !settings.isRunning {
            settings.activeInputBackend = "Not running"
        }
    }

    @MainActor
    private func installVirtualHIDHelper() async {
        guard !settings.isRunning else { return }
        settings.virtualHIDHelperActionInProgress = true
        settings.virtualHIDHelperMessage = "Installing helper..."
        do {
            try await Task.detached(priority: .userInitiated) {
                try VirtualHIDHelperInstaller.installForCurrentUser()
            }.value
            settings.virtualHIDHelperMessage = "Helper installed for uid \(getuid())."
        } catch {
            settings.virtualHIDHelperMessage = "Helper install failed: \(error.localizedDescription)"
        }
        settings.virtualHIDHelperActionInProgress = false
        refreshVirtualHIDStatus()
    }

    @MainActor
    private func uninstallVirtualHIDHelper() async {
        guard !settings.isRunning else { return }
        settings.virtualHIDHelperActionInProgress = true
        settings.virtualHIDHelperMessage = "Removing helper..."
        do {
            try await Task.detached(priority: .userInitiated) {
                try VirtualHIDHelperInstaller.uninstallForCurrentUser()
            }.value
            settings.virtualHIDHelperMessage = "Helper removed."
        } catch {
            settings.virtualHIDHelperMessage = "Helper removal failed: \(error.localizedDescription)"
        }
        settings.virtualHIDHelperActionInProgress = false
        refreshVirtualHIDStatus()
    }

    @MainActor
    private func handleConnectionModeChange(to mode: ConnectionMode) async {
        debugLog("Connection mode changed to: \(mode.rawValue)")
        // Disconnect any active client immediately (per spec §6 / fix #2).
        let wasRunning = settings.isRunning
        if wasRunning {
            stopServer()
        }
        if mode == .wireless {
            // Generate token if missing; the QR will reflect it.
            _ = WirelessAuth.loadOrCreate()
        }
        if wasRunning {
            await startServer()
        }
    }

    /// Check permissions on demand (called when settings window opens or manually)
    func refreshPermissions() {
        Task {
            await checkPermissions()
        }
    }

    func setupSettingsObservers() {
        // Observer cho gaming boost changes. It changes effective bitrate,
        // quality, and FPS, so rebuild the display/capture pipeline when live.
        settings.$gamingBoost
            .dropFirst() // Skip initial value
            .sink { [weak self] gamingBoost in
                guard let self = self, self.settings.isRunning else { return }
                print("🎮 Gaming Boost \(gamingBoost ? "ENABLED" : "DISABLED")")
                self.schedulePipelineRestart(reason: "Gaming Boost changed")
            }
            .store(in: &cancellables)

        // Observer cho bitrate/quality changes (chỉ khi không gaming boost)
        Publishers.CombineLatest(settings.$bitrate, settings.$quality)
            .dropFirst()
            .sink { [weak self] bitrate, quality in
                guard let self = self, self.settings.isRunning, !self.settings.gamingBoost else { return }
                print("⚙️ Settings updated: \(bitrate)Mbps, \(quality)")
                self.screenCapture?.updateEncoderSettings(
                    bitrateMbps: bitrate,
                    quality: quality,
                    gamingBoost: false
                )
            }
            .store(in: &cancellables)

        // Observer cho rotation changes - send to connected client immediately
        settings.$rotation
            .dropFirst()
            .sink { [weak self] rotation in
                guard let self = self, self.settings.isRunning else { return }
                guard self.activeDisplaySource?.isVirtual == true else { return }
                print("🔄 Rotation changed to \(rotation)°")
                self.streamingServer?.updateRotation(rotation)
            }
            .store(in: &cancellables)

        // Observer cho touch enable/disable - propagate to streaming server so
        // incoming touch frames from the client are dropped early when off.
        settings.$touchEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.streamingServer?.touchEnabled = enabled
            }
            .store(in: &cancellables)

        // Observer cho connection mode changes — restart server with new auth/ADB policy.
        settings.$connectionMode
            .dropFirst()
            .sink { [weak self] mode in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.handleConnectionModeChange(to: mode)
                }
            }
            .store(in: &cancellables)

        settings.$displaySourceMode
            .dropFirst()
            .sink { [weak self] mode in
                guard let self = self else { return }
                Task { @MainActor in
                    guard self.settings.isRunning else { return }
                    debugLog("Display source mode changed to \(mode.rawValue) — restarting server")
                    self.stopServer()
                    await self.startServer()
                }
            }
            .store(in: &cancellables)

        settings.$inputBackendMode
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    guard self.settings.isRunning else {
                        self.refreshVirtualHIDStatus()
                        return
                    }
                    debugLog("Input backend changed — restarting server to rebuild input pipeline")
                    self.stopServer()
                    await self.startServer()
                }
            }
            .store(in: &cancellables)

        // Resolution/HiDPI rebuild only applies to Extended Display, where the
        // virtual display is created at server start.
        settings.$resolution
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] resolution in
                guard let self = self else { return }
                guard self.settings.isRunning else { return }
                guard self.activeDisplaySource?.isVirtual == true else { return }
                self.schedulePipelineRestart(reason: "Resolution changed to \(resolution)")
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(settings.$refreshRate, settings.$hiDPI)
            .dropFirst()
            .sink { [weak self] refreshRate, hiDPI in
                guard let self = self, self.settings.isRunning else { return }
                guard self.activeDisplaySource?.isVirtual == true else { return }
                self.schedulePipelineRestart(reason: "Display timing changed to \(refreshRate)Hz, HiDPI=\(hiDPI)")
            }
            .store(in: &cancellables)
    }

    private func schedulePipelineRestart(reason: String) {
        pendingPipelineRestart?.cancel()
        pendingPipelineRestart = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled, self.settings.isRunning else { return }
            debugLog("\(reason) — restarting server to rebuild display pipeline")
            self.stopServer()
            await self.startServer()
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "Side Screen")
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    func setupSettingsWindow() {
        settingsWindow = SettingsWindowController(settings: settings)

        settings.onToggleServer = { [weak self] in
            guard let self else { return }
            if self.settings.isRunning {
                self.stopServer()
            } else {
                Task { [weak self] in
                    await self?.startServer()
                }
            }
        }
        settings.onInstallVirtualHIDHelper = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.installVirtualHIDHelper()
            }
        }
        settings.onUninstallVirtualHIDHelper = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.uninstallVirtualHIDHelper()
            }
        }
        settings.onRefreshVirtualHIDStatus = { [weak self] in
            Task { @MainActor in
                self?.refreshVirtualHIDStatus()
            }
        }
        settings.onRefreshPermissions = { [weak self] in
            self?.refreshPermissions()
        }
        settings.onCopyDiagnostics = { [weak self] in
            Task { @MainActor in
                self?.copyDiagnosticsToClipboard()
            }
        }
        settings.onPromptAccessibility = { [weak self] in
            Task { @MainActor in
                self?.promptAccessibilityPermission()
            }
        }
        settings.onSetPairedDeviceRevoked = { [weak self] deviceId, revoked in
            Task { @MainActor in
                self?.setPairedDeviceRevoked(id: deviceId, revoked: revoked)
            }
        }
        settings.onResetWirelessPairing = { [weak self] in
            Task { @MainActor in
                self?.resetWirelessPairing()
            }
        }
    }

    @MainActor
    private func setPairedDeviceRevoked(id deviceId: String, revoked: Bool) {
        if revoked {
            pairedDeviceStore.revoke(id: deviceId)
            remoteSessionStore.revoke(deviceId: deviceId)
            if currentWirelessDevice?.id == deviceId {
                dropActiveWirelessConnection(reason: "device revoked", recordLastConnected: true)
            }
        } else {
            pairedDeviceStore.restore(id: deviceId)
        }
    }

    @MainActor
    private func resetWirelessPairing() {
        let freshToken = WirelessAuth.reset()
        pairedDeviceStore.clear()
        remoteSessionStore.clear()
        streamingServer?.expectedAuthToken = settings.connectionMode == .wireless ? freshToken : nil
        dropActiveWirelessConnection(reason: "wireless token reset", recordLastConnected: false)
    }

    @MainActor
    private func dropActiveWirelessConnection(reason: String, recordLastConnected: Bool) {
        wirelessConnectionGeneration += 1
        releaseLegacyTouchState(reason: reason)
        if let device = currentWirelessDevice {
            if recordLastConnected {
                pairedDeviceStore.upsert(id: device.id, name: device.name, deviceSecret: device.deviceSecret, lastConnected: Date())
            }
            remoteSessionStore.revoke(deviceId: device.id)
        }
        inputServer?.dropActiveConnection(reason: reason)
        streamingServer?.dropActiveConnection(reason: reason)
        currentWirelessDevice = nil
        settings.currentWirelessDeviceId = nil
        settings.currentWirelessDevice = nil
        settings.clientConnected = false
        settings.currentFPS = 0
        settings.currentBitrate = 0
    }

    @MainActor
    private func copyDiagnosticsToClipboard() {
        let text = buildDiagnosticsText()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        settings.diagnosticsMessage = "Diagnostics copied."
    }

    private func buildDiagnosticsText() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let logTail = (try? String(contentsOfFile: "/tmp/sidescreen.log", encoding: .utf8))
            .map { $0.split(separator: "\n").suffix(80).joined(separator: "\n") } ?? "No log found at /tmp/sidescreen.log"

        return """
        Side Screen Mac diagnostics
        Version: \(version)
        macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        Mode: \(settings.connectionMode.rawValue)
        Endpoint: \(settings.endpointMode.rawValue)
        Display source mode: \(settings.displaySourceMode.rawValue)
        Active display source: \(settings.activeDisplaySourceKind) / \(settings.activeDisplaySourceName)
        Port: \(settings.port)
        Running: \(settings.isRunning)
        Client connected: \(settings.clientConnected)
        Screen Recording: \(settings.hasScreenRecordingPermission)
        Accessibility: \(settings.hasAccessibilityPermission)
        Touch enabled: \(settings.touchEnabled)
        ADB installed: \(settings.adbInstalled)
        ADB reverse: \(settings.adbReverseConfigured)
        USB device: \(settings.usbDeviceConnected)
        Listening address: \(settings.listeningAddress ?? "none")
        Capture method: \(settings.captureMethod)
        Input backend: \(settings.activeInputBackend)
        Virtual HID: \(settings.virtualHIDStatus) \(settings.virtualHIDStatusDetail)
        Input state: \(settings.inputPressedKeys) keys / \(settings.inputPressedButtons) buttons
        Input release-all: \(settings.inputReleaseAllCount), last: \(settings.inputLastReleaseReason)
        Input sequence: \(settings.inputSequenceGapCount) gaps / \(settings.inputDroppedStaleCount) stale

        Recent log:
        \(logTail)
        """
    }

    @objc func showSettings() {
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func checkPermissions() async {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        debugLog("checkPermissions — macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")

        // Check Screen Recording permission using CoreGraphics API
        let hasScreenCapture = CGPreflightScreenCaptureAccess()
        await MainActor.run {
            settings.hasScreenRecordingPermission = hasScreenCapture
        }
        if hasScreenCapture {
            debugLog("Screen recording permission granted (CGPreflight)")

            // On macOS 26+, also verify ScreenCaptureKit is actually functional
            if version.majorVersion >= 26 {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    debugLog("SCShareableContent verification OK — \(content.displays.count) displays found")
                } catch {
                    debugLog("WARNING: CGPreflight OK but SCShareableContent failed on macOS 26: \(error.localizedDescription)")
                    debugLog("CGDisplayStream fallback will likely activate at capture time")
                }
            }
        } else {
            debugLog("Screen recording permission not granted yet")
            CGRequestScreenCaptureAccess()
        }

        // Check Accessibility permission (required for touch/mouse injection)
        await checkAccessibilityPermission()
    }

    func checkAccessibilityPermission() async {
        let trusted = AXIsProcessTrusted()
        await MainActor.run {
            settings.hasAccessibilityPermission = trusted
        }
        if trusted {
            print("✅ Accessibility permission granted")
        } else {
            print("⚠️  Accessibility permission not granted - touch control will not work")
        }
    }

    @MainActor
    func promptAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        settings.hasAccessibilityPermission = trusted

        if !trusted {
            debugLog("Accessibility prompt shown; user still needs to grant permission in System Settings")
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    /// Setup ADB reverse port forwarding for USB connection
    func setupADBReverse() async {
        let port = settings.port
        let inputPort = UInt16(min(Int(port) + 1, Int(UInt16.max)))
        let ports = [port, inputPort]
        print("🔌 Setting up ADB reverse for ports \(ports.map(String.init).joined(separator: ", "))...")

        await Task.detached(priority: .utility) {
            // Try common adb paths
            let adbPaths = [
                "/usr/local/bin/adb",
                "/opt/homebrew/bin/adb",
                "~/Library/Android/sdk/platform-tools/adb",
                "/Users/\(NSUserName())/Library/Android/sdk/platform-tools/adb"
            ]

            var adbPath: String?
            for path in adbPaths {
                let expandedPath = NSString(string: path).expandingTildeInPath
                if FileManager.default.fileExists(atPath: expandedPath) {
                    adbPath = expandedPath
                    break
                }
            }

            // Also try 'which adb' to find it in PATH
            if adbPath == nil {
                let whichProcess = Process()
                whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                whichProcess.arguments = ["adb"]
                let whichPipe = Pipe()
                whichProcess.standardOutput = whichPipe
                whichProcess.standardError = FileHandle.nullDevice

                do {
                    try whichProcess.run()
                    whichProcess.waitUntilExit()
                    let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                    if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !path.isEmpty {
                        adbPath = path
                    }
                } catch {
                    // Ignore
                }
            }

            guard let finalAdbPath = adbPath else {
                print("⚠️  ADB not found - USB connection may not work")
                print("💡 Install Android SDK or run manually: adb reverse tcp:\(port) tcp:\(port) && adb reverse tcp:\(inputPort) tcp:\(inputPort)")
                return
            }

            print("📱 Found ADB at: \(finalAdbPath)")

            // Retry adb reverse up to 3 times — handles first-install authorization delay
            for reversePort in ports {
                for attempt in 1...3 {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: finalAdbPath)
                    process.arguments = ["reverse", "tcp:\(reversePort)", "tcp:\(reversePort)"]

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    do {
                        try process.run()
                        process.waitUntilExit()

                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? ""

                        if process.terminationStatus == 0 {
                            print("✅ ADB reverse setup successful: tcp:\(reversePort) -> tcp:\(reversePort)")
                            break
                        } else {
                            print("⚠️  ADB reverse port \(reversePort) attempt \(attempt)/3 failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                            if attempt < 3 {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                            }
                        }
                    } catch {
                        print("⚠️  Failed to run ADB for port \(reversePort) (attempt \(attempt)/3): \(error.localizedDescription)")
                        if attempt < 3 {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    }
                    if attempt == 3 {
                        print("💡 Make sure Android device is connected via USB with debugging enabled")
                    }
                }
            }
        }.value
    }

    @MainActor
    func showPermissionAlert() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let isMacOS26 = version.majorVersion >= 26

        let alert = NSAlert()
        if isMacOS26 {
            alert.messageText = "Screen & System Audio Recording Permission Required"
            alert.informativeText = "Please grant Screen & System Audio Recording permission in System Settings > Privacy & Security."
        } else {
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "Please grant Screen Recording permission in System Settings > Privacy & Security."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    private func makeDisplaySourceForCurrentSettings() throws -> DisplaySource {
        switch settings.displaySourceMode {
        case .remoteDesktop:
            virtualDisplayManager = nil
            let source = displaySourceCatalog.source(preferredID: settings.selectedRemoteDisplayID)
            if settings.selectedRemoteDisplayID != source.displayID {
                settings.selectedRemoteDisplayID = source.displayID
            }
            return .existing(source)
        case .extendedDisplay:
            virtualDisplayManager = VirtualDisplayManager()
            let size = settings.resolutionSize
            try virtualDisplayManager?.createDisplay(
                width: size.width,
                height: size.height,
                refreshRate: settings.effectiveRefreshRate,
                hiDPI: settings.hiDPI,
                name: "SideScreen"
            )
            guard let displayID = virtualDisplayManager?.displayID else {
                throw NSError(
                    domain: "DisplaySource",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Virtual display was not created"]
                )
            }
            return .virtual(VirtualDisplaySource(
                displayID: displayID,
                requestedWidth: size.width,
                requestedHeight: size.height,
                hiDPI: settings.hiDPI,
                refreshRate: settings.effectiveRefreshRate
            ))
        }
    }

    private func displayConfigSize(
        for codec: StreamCodec,
        source: DisplaySource,
        capture: ScreenCapture?
    ) -> (width: Int, height: Int) {
        switch codec {
        case .hevc:
            return source.hevcDisplayConfigSize
        case .h264:
            if let capture {
                return capture.encodeSize(for: .h264)
            }
            let physical = ScreenCapture.physicalSize(for: source.displayID)
            return CodecLimits.clampForAvc(width: physical.width, height: physical.height)
        }
    }

    private func displayConfigRotation(for source: DisplaySource) -> Int {
        source.isVirtual ? settings.rotation : 0
    }

    private func remoteDisplayListEnvelope() -> DisplayControlEnvelope {
        let displays = displaySourceCatalog.displays()
        let selected = activeDisplaySource.flatMap { source -> CGDirectDisplayID? in
            if case .existing(let existing) = source { return existing.displayID }
            return nil
        } ?? displaySourceCatalog.source(preferredID: settings.selectedRemoteDisplayID).displayID
        return .displayList(selectedDisplayId: selected, displays: displays)
    }

    @MainActor
    private func sendRemoteDisplayList() {
        streamingServer?.sendDisplayControl(remoteDisplayListEnvelope())
    }

    @MainActor
    private func handleDisplayControl(_ envelope: DisplayControlEnvelope) async {
        switch envelope.type {
        case .requestDisplayList:
            sendRemoteDisplayList()
        case .selectDisplay:
            guard let displayID = envelope.displayId else {
                return
            }
            await switchRemoteDisplay(displayID: displayID)
        case .displayList, .selectDisplayResult:
            break
        }
    }

    @MainActor
    private func switchRemoteDisplay(displayID: CGDirectDisplayID) async {
        guard displaySourceCatalog.contains(displayID: displayID) else {
            streamingServer?.sendDisplayControl(.selectDisplayResult(
                displayId: displayID,
                status: "error",
                message: "Display unavailable"
            ))
            sendRemoteDisplayList()
            return
        }

        let existing = displaySourceCatalog.source(preferredID: displayID)
        settings.selectedRemoteDisplayID = displayID

        guard settings.displaySourceMode == .remoteDesktop else {
            streamingServer?.sendDisplayControl(.selectDisplayResult(
                displayId: displayID,
                status: "ok",
                message: "Display will be used when Remote Desktop mode is active"
            ))
            sendRemoteDisplayList()
            return
        }

        let source = DisplaySource.existing(existing)
        guard settings.isRunning, let capture = screenCapture else {
            activeDisplaySource = source
            settings.activeDisplaySourceName = source.title
            settings.activeDisplaySourceKind = source.diagnosticKind
            streamingServer?.sendDisplayControl(.selectDisplayResult(displayId: displayID, status: "ok"))
            sendRemoteDisplayList()
            return
        }

        inputServer?.releaseAll(reason: "display changed")
        releaseLegacyTouchState(reason: "display changed")

        do {
            try await capture.switchDisplay(to: source, refreshRate: settings.effectiveRefreshRate)
            activeDisplaySource = source
            settings.displayCreated = false
            settings.activeDisplaySourceName = source.title
            settings.activeDisplaySourceKind = source.diagnosticKind

            let configSize = displayConfigSize(for: capture.codec, source: source, capture: capture)
            streamingServer?.setDisplaySize(
                width: configSize.width,
                height: configSize.height,
                rotation: displayConfigRotation(for: source)
            )
            streamingServer?.sendDisplaySize()
            capture.requestKeyframeOrReplayCachedFrame(force: true)
            streamingServer?.sendDisplayControl(.selectDisplayResult(displayId: displayID, status: "ok"))
            sendRemoteDisplayList()
            debugLog("Remote display switched to \(source.title) (ID: \(displayID))")
        } catch {
            debugLog("Remote display switch failed: \(error)")
            streamingServer?.sendDisplayControl(.selectDisplayResult(
                displayId: displayID,
                status: "error",
                message: error.localizedDescription
            ))
            sendRemoteDisplayList()
        }
    }

    func startServer() async {
        guard settings.hasScreenRecordingPermission else {
            await showPermissionAlert()
            return
        }

        do {
            let displaySource = try makeDisplaySourceForCurrentSettings()
            activeDisplaySource = displaySource
            await MainActor.run {
                settings.displayCreated = displaySource.isVirtual
                settings.activeDisplaySourceName = displaySource.title
                settings.activeDisplaySourceKind = displaySource.diagnosticKind
            }
            debugLog("Display source selected: \(displaySource.diagnosticKind) \(displaySource.title) (ID: \(displaySource.displayID))")

            if displaySource.isVirtual {
                // Disable mirror mode (may fail if already in extend mode)
                do {
                    try virtualDisplayManager?.disableMirrorMode()
                } catch {
                    // Not critical - continue anyway
                }
            }

            // Run ADB setup (USB only) and display init wait in parallel.
            // For wireless mode, skip ADB entirely — the auth handshake gates LAN connections instead.
            await withTaskGroup(of: Void.self) { group in
                if settings.connectionMode == .usb {
                    group.addTask { await self.setupADBReverse() }
                } else {
                    debugLog("Wireless mode: skipping ADB setup")
                }
                if displaySource.isVirtual {
                    group.addTask { try? await Task.sleep(nanoseconds: 500_000_000) }
                }
            }

            if displaySource.isVirtual {
                virtualDisplayManager?.restoreDisplayPosition()

                // Verify display is registered in the system
                if let vdm = virtualDisplayManager {
                    let registered = vdm.verifyDisplayRegistered()
                    if !registered {
                        debugLog("WARNING: Virtual display not found in online display list — capture may fail")
                    }
                }
            }

            // Setup capture
            screenCapture = try await ScreenCapture()
            screenCapture?.onCaptureMethodChanged = { [weak self] method in
                guard let self = self else { return }
                debugLog("Capture method: \(method)")
                Task { @MainActor in
                    self.settings.captureMethod = method
                }
            }
            try await screenCapture?.setup(for: displaySource, refreshRate: settings.effectiveRefreshRate)

            // Setup server
            streamingServer = StreamingServer(port: settings.port)
            let inputSelection = InputBackendFactory.make(mode: settings.inputBackendMode) { [weak self] diagnostics in
                Task { @MainActor [weak self] in
                    self?.settings.inputPressedKeys = diagnostics.pressedKeyCount
                    self?.settings.inputPressedButtons = diagnostics.pressedButtonCount
                    self?.settings.inputReleaseAllCount = diagnostics.releaseAllCount
                    self?.settings.inputDroppedStaleCount = diagnostics.droppedStaleCount
                    self?.settings.inputSequenceGapCount = diagnostics.sequenceGapCount
                    self?.settings.inputCoalescedPointerMoves = diagnostics.coalescedPointerMoves
                    self?.settings.inputLastReleaseReason = diagnostics.lastReleaseReason
                }
            }
            let inputPort = UInt16(min(Int(settings.port) + 1, Int(UInt16.max)))
            settings.activeInputBackend = inputSelection.activeBackend.title
            settings.virtualHIDStatus = inputSelection.status.title
            settings.virtualHIDStatusDetail = inputSelection.status.detail
            inputServer = InputServer(
                port: inputPort,
                validateAuthToken: settings.connectionMode == .wireless ? { [weak self] token, deviceId, sessionId in
                    let accepted = self?.remoteSessionStore.validateInputToken(token, deviceId: deviceId, sessionId: sessionId) == true
                    debugLog(
                        "Input auth \(accepted ? "OK" : "rejected") — device=...\(deviceId.suffix(4)), " +
                        "session=\(sessionId == nil ? "missing" : "present")"
                    )
                    return accepted
                } : nil,
                backend: inputSelection.backend,
                activeBackend: inputSelection.activeBackend,
                isDeviceRevoked: { [weak self] deviceId in
                    self?.pairedDeviceStore.isRevoked(id: deviceId) == true
                }
            )
            streamingServer?.touchEnabled = settings.touchEnabled
            streamingServer?.onDisplayControlReady = { [weak self] in
                Task { @MainActor in
                    self?.sendRemoteDisplayList()
                }
            }
            streamingServer?.onDisplayControlMessage = { [weak self] envelope in
                Task { @MainActor in
                    await self?.handleDisplayControl(envelope)
                }
            }
            if settings.connectionMode == .wireless {
                streamingServer?.expectedAuthToken = WirelessAuth.loadOrCreate()
                streamingServer?.isWirelessDeviceRevoked = { [weak self] deviceId in
                    self?.pairedDeviceStore.isRevoked(id: deviceId) == true
                }
                streamingServer?.wirelessDeviceSecret = { [weak self] deviceId in
                    self?.pairedDeviceStore.deviceSecret(id: deviceId)
                }
                streamingServer?.makeWirelessSessionCredentials = { [weak self] deviceId in
                    try self?.remoteSessionStore.create(deviceId: deviceId)
                }
                streamingServer?.onWirelessClientPaired = { [weak self] deviceId, deviceName, deviceSecret in
                    guard let self = self else { return }
                    Task { @MainActor in
                        self.wirelessConnectionGeneration += 1
                        let device = PairedDevice(id: deviceId, name: deviceName, deviceSecret: deviceSecret, lastConnected: Date(), revoked: false)
                        self.currentWirelessDevice = device
                        self.settings.currentWirelessDeviceId = deviceId
                        self.settings.currentWirelessDevice = deviceName
                        self.pairedDeviceStore.upsert(id: deviceId, name: deviceName, deviceSecret: deviceSecret, lastConnected: Date())
                    }
                }
            }
            let initialConfigSize = displayConfigSize(for: .hevc, source: displaySource, capture: screenCapture)
            streamingServer?.setDisplaySize(
                width: initialConfigSize.width,
                height: initialConfigSize.height,
                rotation: displayConfigRotation(for: displaySource)
            )
            streamingServer?.onClientConnected = { [weak self] in
                guard let self = self else { return }
                self.screenCapture?.requestKeyframeOrReplayCachedFrame(force: true)
                Task { @MainActor in
                    self.settings.clientConnected = true
                }
            }
            // Runs synchronously on the server's network queue BEFORE the
            // display config is sent, so the config below carries the right
            // dimensions for the negotiated codec.
            streamingServer?.onCodecNegotiated = { [weak self] codec in
                guard let self = self, let capture = self.screenCapture else { return }
                capture.setCodec(codec)
                let source = self.activeDisplaySource ?? displaySource
                let configSize = self.displayConfigSize(for: codec, source: source, capture: capture)
                self.streamingServer?.setDisplaySize(
                    width: configSize.width,
                    height: configSize.height,
                    rotation: self.displayConfigRotation(for: source)
                )
            }
            streamingServer?.onKeyframeRequested = { [weak self] force in
                self?.screenCapture?.requestKeyframeOrReplayCachedFrame(force: force)
            }

            streamingServer?.onClientDisconnected = { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    let disconnectedGeneration = self.wirelessConnectionGeneration
                    let disconnectedDevice = self.currentWirelessDevice
                    self.inputServer?.dropActiveConnection(reason: "stream disconnected")
                    if let device = disconnectedDevice {
                        self.remoteSessionStore.revoke(deviceId: device.id)
                    }
                    self.releaseLegacyTouchState(reason: "stream disconnected")
                    guard self.wirelessConnectionGeneration == disconnectedGeneration else {
                        debugLog("Ignoring stale stream disconnect callback")
                        return
                    }
                    self.settings.clientConnected = false
                    // Final lastConnected snapshot at the disconnect moment, then
                    // freeze (currentWirelessDevice = nil stops the rolling update
                    // in refreshStatusIndicators).
                    if let device = disconnectedDevice {
                        self.pairedDeviceStore.upsert(id: device.id, name: device.name, deviceSecret: device.deviceSecret, lastConnected: Date())
                        self.currentWirelessDevice = nil
                        self.settings.currentWirelessDeviceId = nil
                        self.settings.currentWirelessDevice = nil
                    }
                }
            }

            streamingServer?.onTouchEvent = { [weak self] x, y, action, pointerCount, x2, y2 in
                self?.handleTouch(x: x, y: y, action: action, pointerCount: pointerCount, x2: x2, y2: y2)
            }

            streamingServer?.onStats = { [weak self] fps, mbps in
                let captured = self
                Task { @MainActor in
                    captured?.settings.currentFPS = fps
                    captured?.settings.currentBitrate = mbps
                }
            }

            streamingServer?.start()
            inputServer?.start()
            screenCapture?.startStreaming(
                to: streamingServer,
                bitrateMbps: settings.effectiveBitrate,
                quality: settings.effectiveQuality,
                gamingBoost: settings.gamingBoost,
                frameRate: settings.effectiveRefreshRate
            )

            await MainActor.run {
                settings.isRunning = true
            }

            print("✅ Server started on port \(settings.port), input port \(inputPort)")
        } catch {
            print("❌ Failed to start: \(error)")
            if activeDisplaySource?.isVirtual == true {
                virtualDisplayManager?.destroyDisplay()
            }
            activeDisplaySource = nil
            virtualDisplayManager = nil
            await MainActor.run {
                settings.isRunning = false
                settings.displayCreated = false
                settings.activeDisplaySourceName = "None"
                settings.activeDisplaySourceKind = "none"

                let alert = NSAlert()
                alert.messageText = "Failed to Start Server"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }

    func stopServer() {
        // Save display position before destroying
        if activeDisplaySource?.isVirtual == true {
            virtualDisplayManager?.saveDisplayPosition()
        }

        releaseLegacyTouchState(reason: "server stopped")
        screenCapture?.stopStreaming()
        inputServer?.stop()
        streamingServer?.stop()
        remoteSessionStore.clear()
        if activeDisplaySource?.isVirtual == true {
            virtualDisplayManager?.destroyDisplay()
        }
        activeDisplaySource = nil
        virtualDisplayManager = nil
        inputServer = nil

        settings.isRunning = false
        settings.displayCreated = false
        settings.activeDisplaySourceName = "None"
        settings.activeDisplaySourceKind = "none"
        settings.clientConnected = false
        settings.currentFPS = 0
        settings.currentBitrate = 0

        print("⏹️ Server stopped")
    }

    // MARK: - Gesture Properties

    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private var accessibilityWarningShown = false
    private var gestureState: GestureState = .idle
    private var lastTouchTime: UInt64 = 0

    // Touch tracking
    private var touchStartPosition: CGPoint = .zero
    private var touchLastPosition: CGPoint = .zero
    private var touchStartTime: UInt64 = 0
    private var touchLastMoveTime: UInt64 = 0
    private var lastScrollDeltaX: CGFloat = 0
    private var lastScrollDeltaY: CGFloat = 0

    // Double tap tracking
    private var lastTapTime: UInt64 = 0
    private var lastTapPosition: CGPoint = .zero

    // Long press timer
    private var longPressTimer: DispatchWorkItem?

    // 2-finger tracking
    private var initialPinchDistance: CGFloat = 0
    private var lastPinchDistance: CGFloat = 0

    // Momentum scrolling
    private var momentumTimer: Timer?
    private var momentumVelocityX: CGFloat = 0
    private var momentumVelocityY: CGFloat = 0
    private var lastMomentumPosition: CGPoint = .zero

    // MARK: - Touch Entry Point

    func handleTouch(x: Float, y: Float, action: Int, pointerCount: Int = 1, x2: Float = 0, y2: Float = 0) {
        guard settings.touchEnabled else { return }

        if !AXIsProcessTrusted() {
            if !accessibilityWarningShown {
                accessibilityWarningShown = true
                print("⚠️  Accessibility not granted - touch ignored")
                Task { @MainActor in
                    settings.hasAccessibilityPermission = false
                }
            }
            return
        }

        guard let displayID = activeDisplaySource?.displayID else { return }
        let bounds = CGDisplayBounds(displayID)

        let p1 = CGPoint(
            x: bounds.origin.x + CGFloat(x) * bounds.width,
            y: bounds.origin.y + CGFloat(y) * bounds.height
        )
        let p2 = CGPoint(
            x: bounds.origin.x + CGFloat(x2) * bounds.width,
            y: bounds.origin.y + CGFloat(y2) * bounds.height
        )

        if pointerCount >= 2 {
            handleTwoFingerTouch(p1: p1, p2: p2, action: action)
        } else {
            handleOneFingerTouch(at: p1, action: action)
        }
    }

    // MARK: - 1-Finger Gesture State Machine

    private func handleOneFingerTouch(at point: CGPoint, action: Int) {
        switch action {
        case 0: oneFingerDown(at: point)
        case 1: oneFingerMove(to: point)
        case 2: oneFingerUp(at: point)
        default: break
        }
    }

    private func oneFingerDown(at point: CGPoint) {
        stopMomentumScroll()
        cancelLongPressTimer()

        touchStartPosition = point
        touchLastPosition = point
        touchStartTime = DispatchTime.now().uptimeNanoseconds
        touchLastMoveTime = touchStartTime
        gestureState = .pending

        // Move cursor to touch position (absolute)
        moveCursor(to: point)

        // Start long press timer
        let timer = DispatchWorkItem { [weak self] in
            guard let self, self.gestureState == .pending else { return }
            self.gestureState = .longPressReady
        }
        longPressTimer = timer
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .nanoseconds(Int(GestureThresholds.longPressTime)),
            execute: timer
        )
    }

    private func oneFingerMove(to point: CGPoint) {
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastTouchTime < GestureThresholds.minTouchInterval { return }
        lastTouchTime = now

        let deltaX = point.x - touchLastPosition.x
        let deltaY = point.y - touchLastPosition.y
        let totalDistance = hypot(point.x - touchStartPosition.x, point.y - touchStartPosition.y)

        switch gestureState {
        case .pending:
            if totalDistance > GestureThresholds.tapMaxDistance {
                cancelLongPressTimer()
                gestureState = .scrolling
                let sx = deltaX * GestureThresholds.scrollSensitivity
                let sy = deltaY * GestureThresholds.scrollSensitivity
                injectScrollEvent(deltaX: sx, deltaY: sy, at: point)
                lastScrollDeltaX = sx
                lastScrollDeltaY = sy
            }

        case .longPressReady:
            if totalDistance > GestureThresholds.tapMaxDistance {
                // Long press + drag → left mouse drag
                gestureState = .dragging
                injectMouseDown(at: touchStartPosition)
                injectMouseDragged(to: point)
            }

        case .scrolling:
            let sx = deltaX * GestureThresholds.scrollSensitivity
            let sy = deltaY * GestureThresholds.scrollSensitivity
            injectScrollEvent(deltaX: sx, deltaY: sy, at: point)
            let timeDelta = now - touchLastMoveTime
            if timeDelta > 0 && timeDelta < 100_000_000 {
                lastScrollDeltaX = sx
                lastScrollDeltaY = sy
            }

        case .dragging:
            injectMouseDragged(to: point)

        default:
            break
        }

        touchLastPosition = point
        touchLastMoveTime = now
    }

    private func oneFingerUp(at point: CGPoint) {
        cancelLongPressTimer()
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now - touchStartTime
        let distance = hypot(point.x - touchStartPosition.x, point.y - touchStartPosition.y)

        switch gestureState {
        case .pending:
            // Quick release, no movement → tap or double tap
            if distance < GestureThresholds.tapMaxDistance && elapsed < GestureThresholds.tapMaxTime {
                // Check double tap
                let timeSinceLastTap = now - lastTapTime
                let distFromLastTap = hypot(point.x - lastTapPosition.x, point.y - lastTapPosition.y)

                if timeSinceLastTap < GestureThresholds.doubleTapMaxTime
                    && distFromLastTap < GestureThresholds.doubleTapMaxDistance {
                    performDoubleClick(at: point)
                    lastTapTime = 0  // Reset so triple tap doesn't trigger
                } else {
                    performClick(at: point)
                    lastTapTime = now
                    lastTapPosition = point
                }
            }

        case .longPressReady:
            // Held long but didn't drag → right click
            performRightClick(at: point)

        case .scrolling:
            // Check momentum
            let timeSinceLastMove = now - touchLastMoveTime
            if timeSinceLastMove < 50_000_000 {
                let threshold: CGFloat = 2.0
                if abs(lastScrollDeltaX) > threshold || abs(lastScrollDeltaY) > threshold {
                    startMomentumScroll(
                        velocityX: lastScrollDeltaX * 6.0,
                        velocityY: lastScrollDeltaY * 6.0,
                        at: point
                    )
                }
            }

        case .dragging:
            injectMouseUp(at: point)

        default:
            break
        }

        gestureState = .idle
    }

    // MARK: - 2-Finger Gestures

    private func handleTwoFingerTouch(p1: CGPoint, p2: CGPoint, action: Int) {
        let distance = hypot(p2.x - p1.x, p2.y - p1.y)
        let midpoint = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)

        switch action {
        case 0: // Down
            cancelLongPressTimer()
            stopMomentumScroll()
            gestureState = .idle  // Reset so 2-finger detection starts fresh
            initialPinchDistance = distance
            lastPinchDistance = distance
            touchLastPosition = midpoint

        case 1: // Move
            let distanceChange = abs(distance - initialPinchDistance)
            let midDelta = hypot(midpoint.x - touchLastPosition.x, midpoint.y - touchLastPosition.y)

            // Determine mode if not yet decided
            if gestureState != .twoFingerScroll && gestureState != .pinching {
                if distanceChange > GestureThresholds.pinchMinDistance {
                    gestureState = .pinching
                } else if midDelta > GestureThresholds.tapMaxDistance {
                    gestureState = .twoFingerScroll
                }
            }

            switch gestureState {
            case .twoFingerScroll:
                let dx = (midpoint.x - touchLastPosition.x) * GestureThresholds.scrollSensitivity
                let dy = (midpoint.y - touchLastPosition.y) * GestureThresholds.scrollSensitivity
                injectScrollEvent(deltaX: dx, deltaY: dy, at: midpoint)

            case .pinching:
                let scaleDelta = distance - lastPinchDistance
                // Cmd + scroll = zoom in most Mac apps
                let zoomAmount = Int32(scaleDelta * 0.5)
                if zoomAmount != 0 {
                    injectZoomEvent(delta: zoomAmount, at: midpoint)
                }
                lastPinchDistance = distance

            default:
                break
            }

            touchLastPosition = midpoint

        case 2: // Up
            gestureState = .idle
            // Reset 1-finger tracking so leftover moves don't trigger scroll
            touchStartPosition = .zero
            touchLastPosition = .zero

        default:
            break
        }
    }

    // MARK: - Event Injection

    private func moveCursor(to point: CGPoint) {
        if let event = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func performClick(at point: CGPoint) {
        if let down = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            up.post(tap: .cghidEventTap)
        }
    }

    private func performDoubleClick(at point: CGPoint) {
        if let down = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            down.setIntegerValueField(.mouseEventClickState, value: 2)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            up.setIntegerValueField(.mouseEventClickState, value: 2)
            up.post(tap: .cghidEventTap)
        }
    }

    private func performRightClick(at point: CGPoint) {
        if let down = CGEvent(mouseEventSource: eventSource, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(mouseEventSource: eventSource, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) {
            up.post(tap: .cghidEventTap)
        }
    }

    private func injectMouseDown(at point: CGPoint) {
        if let event = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cghidEventTap)
        }
    }

    private func injectMouseDragged(to point: CGPoint) {
        if let event = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func injectMouseUp(at point: CGPoint) {
        if let event = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func injectScrollEvent(deltaX: CGFloat, deltaY: CGFloat, at position: CGPoint) {
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY),
            wheel2: Int32(deltaX),
            wheel3: 0
        ) else { return }
        scrollEvent.location = position
        scrollEvent.post(tap: .cghidEventTap)
    }

    private func injectZoomEvent(delta: Int32, at position: CGPoint) {
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) else { return }
        scrollEvent.location = position
        // Set Cmd flag for zoom
        scrollEvent.flags = .maskCommand
        scrollEvent.post(tap: .cghidEventTap)
    }

    // MARK: - Long Press Timer

    private func cancelLongPressTimer() {
        longPressTimer?.cancel()
        longPressTimer = nil
    }

    // MARK: - Momentum Scrolling

    private func startMomentumScroll(velocityX: CGFloat, velocityY: CGFloat, at position: CGPoint) {
        stopMomentumScroll()
        momentumVelocityX = velocityX
        momentumVelocityY = velocityY
        lastMomentumPosition = position
        momentumTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.momentumTick()
        }
    }

    private func momentumTick() {
        let decay: CGFloat = 0.92
        let minVelocity: CGFloat = 0.5

        if abs(momentumVelocityX) < minVelocity && abs(momentumVelocityY) < minVelocity {
            stopMomentumScroll()
            return
        }

        injectScrollEvent(deltaX: momentumVelocityX, deltaY: momentumVelocityY, at: lastMomentumPosition)
        momentumVelocityX *= decay
        momentumVelocityY *= decay
    }

    private func stopMomentumScroll() {
        momentumTimer?.invalidate()
        momentumTimer = nil
        momentumVelocityX = 0
        momentumVelocityY = 0
    }

    private func releaseLegacyTouchState(reason: String) {
        cancelLongPressTimer()
        stopMomentumScroll()
        if gestureState == .dragging {
            injectMouseUp(at: touchLastPosition == .zero ? touchStartPosition : touchLastPosition)
            debugLog("Released legacy touch drag: \(reason)")
        }
        gestureState = .idle
        touchStartPosition = .zero
        touchLastPosition = .zero
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop momentum scrolling
        stopMomentumScroll()

        // Stop server and cleanup
        stopServer()

        // Cancel all combine subscriptions
        cancellables.removeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
