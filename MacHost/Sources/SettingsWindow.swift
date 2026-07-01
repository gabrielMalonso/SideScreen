import Cocoa
import SwiftUI

// MARK: - Frosted GroupBox Component

struct FrostedGroupBox<Content: View, Trailing: View>: View {
    let title: String
    var icon: String?
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                trailing
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

extension FrostedGroupBox where Trailing == EmptyView {
    init(title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
        self.trailing = EmptyView()
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Streaming Profiles

enum StreamingProfile: String, Codable, CaseIterable {
    case custom
    case productivity
    case quality
    case lowLatency
    case lowBandwidth

    var title: String {
        switch self {
        case .custom: return "Manual"
        case .productivity: return "Productivity"
        case .quality: return "Quality"
        case .lowLatency: return "Low latency"
        case .lowBandwidth: return "Economy"
        }
    }

    var summary: String {
        switch self {
        case .custom:
            return "Use the controls below without a preset."
        case .productivity:
            return "Readable text and stable frame pacing for terminal, browser, and editor work."
        case .quality:
            return "Sharper image for reading, design review, and slower desktop work."
        case .lowLatency:
            return "Prioritizes fast pointer and keyboard feel; video quality gives way first."
        case .lowBandwidth:
            return "Uses less bandwidth and battery for long sessions or relayed Tailnet."
        }
    }

    var settings: StreamingProfileSettings? {
        switch self {
        case .custom:
            return nil
        case .productivity:
            return StreamingProfileSettings(
                refreshRate: 60,
                bitrate: 500,
                quality: "medium",
                gamingBoost: false
            )
        case .quality:
            return StreamingProfileSettings(
                refreshRate: 60,
                bitrate: 800,
                quality: "high",
                gamingBoost: false
            )
        case .lowLatency:
            return StreamingProfileSettings(
                refreshRate: 120,
                bitrate: 300,
                quality: "ultralow",
                gamingBoost: false
            )
        case .lowBandwidth:
            return StreamingProfileSettings(
                refreshRate: 30,
                bitrate: 60,
                quality: "low",
                gamingBoost: false
            )
        }
    }
}

struct StreamingProfileSettings {
    let refreshRate: Int
    let bitrate: Int
    let quality: String
    let gamingBoost: Bool
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings: DisplaySettings
    @State private var showPermissionAlert = false
    @State private var showResetConfirmation = false
    @State private var headerHovered = false

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with frosted glass
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 48, height: 48)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)

                        Image(systemName: "macbook.and.iphone")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(headerHovered ? 1.05 : 1)
                    .animation(.spring(response: 0.3), value: headerHovered)
                    .onHover { headerHovered = $0 }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Remote Mac")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("Control your Mac from Android")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { showResetConfirmation = true }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background {
                                Circle().fill(.ultraThinMaterial)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Reset settings")
                    .alert("Reset Settings", isPresented: $showResetConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Reset", role: .destructive) {
                            settings.resetToDefaults()
                            if let window = NSApp.windows.first(where: { $0.title == "Remote Mac" }) {
                                window.center()
                            }
                        }
                    } message: {
                        Text("This will reset all settings to default values.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(.ultraThinMaterial)

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)

                // Connection mode picker — pinned, NOT scrollable.
                HStack(spacing: 6) {
                    ForEach(ConnectionMode.allCases, id: \.self) { mode in
                        Button(action: { settings.connectionMode = mode }) {
                            HStack(spacing: 4) {
                                Image(systemName: mode == .usb ? "cable.connector" : "wifi")
                                Text(mode == .usb ? "USB" : "Wireless")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(settings.connectionMode == mode ? Color.accentColor : Color.clear)
                            .foregroundColor(settings.connectionMode == mode ? .white : .primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        FrostedGroupBox(title: "Mac Display", icon: "display") {
                            VStack(alignment: .leading, spacing: 10) {
                                StatusRow(
                                    title: "Source",
                                    status: settings.activeDisplaySourceName,
                                    color: settings.activeDisplaySourceKind == "none" ? .secondary : .green,
                                    hint: "Real Mac display currently captured for the remote desktop session."
                                )
                                StatusRow(
                                    title: "Mode",
                                    status: "Remote Desktop",
                                    color: .green,
                                    hint: "Captures an existing Mac display. It does not create an extra monitor."
                                )
                            }
                        }

                        // Refresh Rate (own block)
                        FrostedGroupBox(title: "Refresh Rate", icon: "speedometer") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Frame Rate")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(settings.refreshRate) Hz")
                                        .font(.system(size: 11, weight: .medium))
                                }

                                HStack(spacing: 6) {
                                    ForEach([30, 60, 90, 120], id: \.self) { rate in
                                        BitrateButton(
                                            label: "\(rate)",
                                            value: rate,
                                            currentValue: settings.refreshRate,
                                            disabled: false
                                        ) {
                                            settings.refreshRate = rate
                                        }
                                    }
                                }

                                if settings.refreshRate >= 90 {
                                    Text("High refresh rate for smooth experience")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                }
                            }
                        }

                        // Touch Control
                        FrostedGroupBox(title: "Touch Control", icon: "hand.tap") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Enable Touch Input")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Control Mac from tablet touch")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $settings.touchEnabled)
                                        .labelsHidden()
                                }

                                if !settings.touchEnabled {
                                    Text("Remote input is disabled; video keeps streaming")
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                }
                            }
                        }

                        FrostedGroupBox(title: "Remote Input", icon: "keyboard") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Backend")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Picker("", selection: $settings.inputBackendMode) {
                                        ForEach(InputBackendMode.allCases, id: \.self) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 230)
                                    .disabled(settings.isRunning)
                                }

                                StatusRow(
                                    title: "Active backend",
                                    status: settings.activeInputBackend,
                                    color: settings.activeInputBackend.contains("CGEvent") ? .orange : .green,
                                    hint: "Which backend is currently applying keyboard and mouse events on macOS. Virtual HID is preferred when a privileged helper is available; CGEvent is the fallback."
                                )
                                StatusRow(
                                    title: "Virtual HID",
                                    status: settings.virtualHIDStatus,
                                    color: settings.virtualHIDStatus.hasPrefix("Ready") ? .green : .orange,
                                    hint: settings.virtualHIDStatusDetail.isEmpty ? "Karabiner VirtualHID status has not been checked yet." : settings.virtualHIDStatusDetail
                                )
                                HStack(spacing: 8) {
                                    Button(settings.virtualHIDHelperInstalled ? "Reinstall Helper" : "Install Helper") {
                                        settings.onInstallVirtualHIDHelper?()
                                    }
                                    .disabled(settings.isRunning || settings.virtualHIDHelperActionInProgress)

                                    Button("Remove Helper") {
                                        settings.onUninstallVirtualHIDHelper?()
                                    }
                                    .disabled(settings.isRunning || settings.virtualHIDHelperActionInProgress || !settings.virtualHIDHelperInstalled)

                                    Button("Refresh") {
                                        settings.onRefreshVirtualHIDStatus?()
                                    }
                                    .disabled(settings.virtualHIDHelperActionInProgress)

                                    if settings.virtualHIDHelperActionInProgress {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                                .font(.system(size: 11))

                                if !settings.virtualHIDHelperMessage.isEmpty {
                                    Text(settings.virtualHIDHelperMessage)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                StatusRow(
                                    title: "Pressed state",
                                    status: "\(settings.inputPressedKeys) keys / \(settings.inputPressedButtons) buttons",
                                    color: settings.inputPressedKeys == 0 && settings.inputPressedButtons == 0 ? .green : .orange,
                                    hint: "Current remote input state tracked by InputIngress. It should return to 0/0 after disconnect, pause, or pointer capture release."
                                )
                                StatusRow(
                                    title: "Release-all",
                                    status: "\(settings.inputReleaseAllCount)",
                                    color: .green,
                                    hint: settings.inputLastReleaseReason
                                )
                                StatusRow(
                                    title: "Sequence",
                                    status: "\(settings.inputSequenceGapCount) gaps / \(settings.inputDroppedStaleCount) stale",
                                    color: settings.inputDroppedStaleCount == 0 ? .green : .orange,
                                    hint: "Gaps suggest packet loss or reconnect churn. Stale events are dropped except all-inputs-up."
                                )
                                StatusRow(
                                    title: "Mouse coalescing",
                                    status: "\(settings.inputCoalescedPointerMoves) moves",
                                    color: .green,
                                    hint: "Consecutive relative mouse moves coalesced before hitting the backend."
                                )

                                if settings.inputBackendMode == .virtualHID && settings.virtualHIDStatus != "Ready" {
                                    Text(settings.virtualHIDStatusDetail)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        // Network Settings (port — applies to both modes; listener binds on it)
                        FrostedGroupBox(title: "Network Settings", icon: "network") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Server Port")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    TextField("Port", value: $settings.port, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                        .disabled(settings.isRunning)
                                }

                                if settings.isRunning {
                                    Text("Stop server to change port")
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                } else if settings.port == DisplaySettings.maxVideoPort {
                                    Text("Port 65535 is reserved for input, so video is capped at 65534.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                } else if settings.connectionMode == .wireless {
                                    Text("Changing the port invalidates existing pairings — re-scan the QR on each tablet.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                } else if settings.port != 54321 {
                                    Text("Custom port set — Android client must use the same port.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Wireless-mode-only: QR + Paired Devices.
                        if settings.connectionMode == .wireless {
                            WirelessSection(settings: settings,
                                            pairedDeviceStore: (NSApp.delegate as? AppDelegate)?.pairedDeviceStore ?? PairedDeviceStore())
                        }

                        // Remote profile presets
                        FrostedGroupBox(title: "Remote Profile", icon: "slider.horizontal.3") {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("", selection: Binding(
                                    get: { settings.streamingProfile },
                                    set: { settings.applyStreamingProfile($0) }
                                )) {
                                    ForEach(StreamingProfile.allCases, id: \.self) { profile in
                                        Text(profile.title).tag(profile)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()

                                Text(settings.streamingProfile.summary)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 8) {
                                    ProfileMetric(label: "FPS", value: "\(settings.effectiveRefreshRate)")
                                    ProfileMetric(label: "Bitrate", value: "\(settings.effectiveBitrate) Mbps")
                                    ProfileMetric(label: "Quality", value: settings.effectiveQuality)
                                }
                            }
                        }

                        // Gaming Boost
                        FrostedGroupBox(title: "Gaming Boost", icon: settings.gamingBoost ? "bolt.fill" : "bolt") {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Enable Gaming Mode")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Optimized for competitive gaming")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $settings.gamingBoost)
                                        .labelsHidden()
                                }

                                if settings.gamingBoost {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 10))
                                            Text("Low encoder delay (50 Mbps cap)")
                                                .font(.system(size: 11))
                                        }
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 10))
                                            Text("120 Hz refresh rate")
                                                .font(.system(size: 11))
                                        }
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 10))
                                            Text("Ultra-low latency encoding")
                                                .font(.system(size: 11))
                                        }
                                    }
                                    .padding(.leading, 4)
                                    .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Streaming Settings
                        FrostedGroupBox(title: "Streaming Settings", icon: "antenna.radiowaves.left.and.right") {
                            VStack(alignment: .leading, spacing: 16) {
                                // Bitrate
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Bitrate")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(settings.effectiveBitrate) Mbps")
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.accentColor)
                                    }

                                    HStack(spacing: 6) {
                                        BitrateButton(label: "100", value: 100, currentValue: settings.bitrate, disabled: settings.gamingBoost) {
                                            settings.bitrate = 100
                                        }
                                        BitrateButton(label: "300", value: 300, currentValue: settings.bitrate, disabled: settings.gamingBoost) {
                                            settings.bitrate = 300
                                        }
                                        BitrateButton(label: "500", value: 500, currentValue: settings.bitrate, disabled: settings.gamingBoost) {
                                            settings.bitrate = 500
                                        }
                                        BitrateButton(label: "1000", value: 1000, currentValue: settings.bitrate, disabled: settings.gamingBoost) {
                                            settings.bitrate = 1000
                                        }
                                        BitrateButton(label: "2000", value: 2000, currentValue: settings.bitrate, disabled: settings.gamingBoost) {
                                            settings.bitrate = 2000
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        Text("20")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        Slider(value: Binding(
                                            get: { Double(settings.bitrate) },
                                            set: { settings.bitrate = Int($0) }
                                        ), in: 20...5000, step: 10)
                                        .disabled(settings.gamingBoost)
                                        Text("5000")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }

                                    if settings.gamingBoost {
                                        HStack(spacing: 4) {
                                            Image(systemName: "bolt.fill")
                                                .font(.system(size: 10))
                                            Text("Locked at 50 Mbps in Gaming Boost")
                                                .font(.system(size: 10))
                                        }
                                        .foregroundColor(.orange)
                                    }
                                }

                                // Quality
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Quality Preset")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)

                                    Picker("", selection: $settings.quality) {
                                        Text("Ultra Low").tag("ultralow")
                                        Text("Low").tag("low")
                                        Text("Medium").tag("medium")
                                        Text("High").tag("high")
                                    }
                                    .pickerStyle(.segmented)
                                    .disabled(settings.gamingBoost)

                                    if settings.gamingBoost {
                                        Text("Quality locked to Ultra Low in Gaming Boost mode")
                                            .font(.system(size: 10))
                                            .foregroundColor(.orange)
                                    } else if settings.quality == "ultralow" {
                                        Text("Fastest encoding, lowest latency")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }

                        // Status
                        FrostedGroupBox(title: "Status", icon: "checkmark.circle") {
                            VStack(alignment: .leading, spacing: 12) {
                                StatusRow(title: "Display Source",
                                          status: settings.activeDisplaySourceName,
                                          color: settings.activeDisplaySourceKind == "none" ? .secondary : .green,
                                          hint: "Active real Mac display captured for the remote session.")
                                StatusRow(title: "Client Connected",
                                          status: settings.clientConnected ? "Yes" : "No",
                                          color: settings.clientConnected ? .green : .secondary,
                                          hint: "Whether the Android client app currently has an active stream session.")
                                StatusRow(
                                    title: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? "Screen & System Audio" : "Screen Recording",
                                    status: settings.hasScreenRecordingPermission ? "Granted" : "Required",
                                    color: settings.hasScreenRecordingPermission ? .green : .red,
                                    hint: "macOS privacy permission required to capture the selected display. Grant in System Settings → Privacy & Security → Screen Recording."
                                )
                                StatusRow(title: "Accessibility",
                                          status: settings.hasAccessibilityPermission ? "Granted" : "Required for CGEvent/TextCommit",
                                          color: settings.hasAccessibilityPermission ? .green : .orange,
                                          hint: "Streaming works without this. CGEvent input and Unicode TextCommit need Accessibility. Basic Virtual HID keyboard and mouse input can avoid it when the helper is healthy.")
                                HStack(spacing: 8) {
                                    Spacer()
                                    Button(action: { settings.onCopyDiagnostics?() }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.on.doc")
                                            Text("Copy Diagnostics")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button(action: { settings.onRefreshPermissions?() }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Refresh Permissions")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                if !settings.diagnosticsMessage.isEmpty {
                                    Text(settings.diagnosticsMessage)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                if settings.isRunning {
                                    StatusRow(title: "Capture Method",
                                              status: settings.captureMethod,
                                              color: settings.captureMethod.contains("fallback") ? .orange : .green,
                                              hint: "Which macOS API is currently capturing the selected display. SCStream is the modern path; CGDisplayStream fallback activates if SCStream fails.")
                                }

                                // Mode-aware contextual rows
                                Divider().padding(.vertical, 4)
                                if settings.connectionMode == .usb {
                                    StatusRow(title: "ADB installed",
                                              status: settings.adbInstalled ? "Installed" : "Missing",
                                              color: settings.adbInstalled ? .green : .red,
                                              hint: "USB mode tunnels the TCP stream through the cable using `adb reverse`. Requires the `adb` command on the Mac. Searched paths: Homebrew, /usr/local/bin, ~/Library/Android/sdk/platform-tools, and PATH (`which adb`).")
                                    if !settings.adbInstalled {
                                        Text("brew install android-platform-tools")
                                            .font(.system(size: 10, design: .monospaced))
                                            .padding(6)
                                            .background(Color.black.opacity(0.08))
                                            .cornerRadius(4)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    StatusRow(title: "ADB reverse",
                                              status: settings.adbReverseConfigured ? "OK" : "Pending",
                                              color: settings.adbReverseConfigured ? .green : .orange,
                                              hint: "Whether `adb reverse tcp:\(settings.port) tcp:\(settings.port)` is currently configured. The Mac app sets this up automatically when you click Start. Goes green within ~2 seconds after the tablet is plugged in and authorized.")
                                    StatusRow(title: "USB device",
                                              status: settings.usbDeviceConnected ? "Detected" : "Not detected",
                                              color: settings.usbDeviceConnected ? .green : .red,
                                              hint: "An Android device authorized for ADB and visible to your Mac. Plug in via USB-C and tap Allow on the device's USB debugging prompt.")
                                } else {
                                    StatusRow(title: "WiFi",
                                              status: settings.wifiConnected ? "Connected" : "Disconnected",
                                              color: settings.wifiConnected ? .green : .red,
                                              hint: "Whether the Mac currently has a working internet route. Wireless mode requires the Mac to be on a WiFi (or Ethernet) network — the same network the tablet is on.")
                                    StatusRow(title: "Listening on",
                                              status: settings.listeningAddress.map { "\($0):\(settings.port)" } ?? "—",
                                              color: settings.listeningAddress != nil ? .green : .secondary,
                                              hint: "The LAN address the tablet must reach. The QR code embeds this exact host:port — if it changes (e.g. you switch WiFi), re-scan the new QR on the tablet.")
                                }

                                if !settings.hasScreenRecordingPermission {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                            Text(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? "Screen & System Audio Recording Required" : "Screen Recording Required")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        Text(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
                                            ? "Required to capture the selected display. Go to System Settings > Privacy & Security > Screen & System Audio Recording."
                                            : "Required to capture the selected display.")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Button(action: {
                                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                                        }) {
                                            HStack {
                                                Image(systemName: "gear")
                                                Text("Open System Settings")
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                    .padding(10)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(8)
                                }

                                if !settings.hasAccessibilityPermission {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "hand.tap.fill")
                                                .foregroundColor(.blue)
                                            Text("Accessibility Needed for Remote Input")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        Text("Grant this if you want tablet touch, mouse, or keyboard input to control the Mac. Video streaming still works without it.")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Button(action: {
                                            settings.onPromptAccessibility?()
                                        }) {
                                            HStack {
                                                Image(systemName: "gear")
                                                Text("Open Accessibility Settings")
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                    .padding(10)
                                    .background(Color.blue.opacity(0.08))
                                    .cornerRadius(8)
                                }
                            }
                        }

                        // Performance (when connected)
                        if settings.clientConnected {
                            FrostedGroupBox(title: "Performance", icon: "speedometer") {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("FPS")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.1f", settings.currentFPS))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.green)
                                    }
                                    Spacer()
                                    VStack(alignment: .leading) {
                                        Text("Bitrate")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.1f Mbps", settings.currentBitrate))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }

                // Footer
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)

                    HStack(spacing: 12) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                settings.toggleServer()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: settings.isRunning ? "stop.fill" : "play.fill")
                                    .font(.system(size: 12))
                                Text(settings.isRunning ? "Stop" : "Start")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(width: 90)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(settings.isRunning ? .red : .accentColor)
                        .controlSize(.large)
                        .disabled(!settings.hasScreenRecordingPermission)

                        if settings.isRunning {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                    .overlay {
                                        Circle()
                                            .stroke(Color.green.opacity(0.3), lineWidth: 2)
                                            .scaleEffect(1.5)
                                    }
                                Text("Running on port \(settings.port)")
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background {
                                Capsule().fill(.ultraThinMaterial)
                                    .overlay {
                                        Capsule().strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                                    }
                            }
                            .transition(.scale.combined(with: .opacity))
                        }

                        Spacer()

                        // Restart button
                        Button(action: {
                            restartApp()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: 32)
                                .background {
                                    Circle().fill(.ultraThinMaterial)
                                        .overlay {
                                            Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                        }
                                }
                        }
                        .buttonStyle(.plain)
                        .help("Restart App")

                        // Quit button
                        Button(action: {
                            NSApp.terminate(nil)
                        }) {
                            Image(systemName: "power")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: 32)
                                .background {
                                    Circle().fill(.ultraThinMaterial)
                                        .overlay {
                                            Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                        }
                                }
                        }
                        .buttonStyle(.plain)
                        .help("Quit Remote Mac (⌘Q)")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .frame(width: 480, height: 780)
    }

    /// Restart the app by launching a new instance and terminating current one
    private func restartApp() {
        // Get the app bundle path
        guard let appPath = Bundle.main.bundlePath as String? else {
            print("❌ Could not get app path")
            return
        }

        // Use Process to launch a new instance after a short delay
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5 && open \"\(appPath)\""]

        do {
            try task.run()
            // Terminate current app
            NSApp.terminate(nil)
        } catch {
            print("❌ Failed to restart: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct ProfileMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.045))
        .cornerRadius(6)
    }
}

struct StatusRow: View {
    let title: String
    let status: String
    let color: Color
    var hint: String?
    @State private var showHint = false
    @State private var hovering = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            if let hint = hint {
                Button(action: { showHint.toggle() }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(hovering ? .accentColor : .secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help(hint)
                .popover(isPresented: $showHint, arrowEdge: .top) {
                    Text(hint)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 280, alignment: .leading)
                        .padding(12)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
            }
        }
    }
}

struct BitrateButton: View {
    let label: String
    let value: Int
    let currentValue: Int
    let disabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var isSelected: Bool { currentValue == value }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                            }
                    }
                }
                .foregroundColor(isSelected ? .white : (disabled ? .secondary : .primary))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Display Settings

class DisplaySettings: ObservableObject {
    private let defaults = UserDefaults.standard
    private let keyPrefix = "SideScreen_"
    private var applyingProfile = false

    @Published var refreshRate: Int {
        didSet {
            save("refreshRate", refreshRate)
            markCustomIfNeeded()
        }
    }
    @Published var bitrate: Int {
        didSet {
            save("bitrate", bitrate)
            markCustomIfNeeded()
        }
    }
    @Published var quality: String {
        didSet {
            save("quality", quality)
            markCustomIfNeeded()
        }
    }
    @Published var gamingBoost: Bool {
        didSet {
            save("gamingBoost", gamingBoost)
            markCustomIfNeeded()
        }
    }
    @Published var streamingProfile: StreamingProfile {
        didSet {
            save("streamingProfile", streamingProfile.rawValue)
        }
    }
    @Published var port: UInt16 {
        didSet {
            let clamped = Self.clampedVideoPort(Int(port))
            if port != clamped {
                port = clamped
                return
            }
            save("port", Int(port))
        }
    }
    @Published var touchEnabled: Bool {
        didSet { save("touchEnabled", touchEnabled) }
    }
    @Published var connectionMode: ConnectionMode {
        didSet { save("connectionMode", connectionMode.rawValue) }
    }
    @Published var selectedRemoteDisplayID: CGDirectDisplayID? {
        didSet {
            if let selectedRemoteDisplayID {
                save("selectedRemoteDisplayID", Int(selectedRemoteDisplayID))
            } else {
                defaults.removeObject(forKey: keyPrefix + "selectedRemoteDisplayID")
            }
        }
    }
    @Published var endpointMode: EndpointMode {
        didSet { save("endpointMode", endpointMode.rawValue) }
    }
    @Published var tailnetHost: String {
        didSet { save("tailnetHost", tailnetHost) }
    }
    @Published var inputBackendMode: InputBackendMode {
        didSet { save("inputBackendMode", inputBackendMode.rawValue) }
    }

    // Runtime state (not persisted)
    @Published var displayCreated = false
    @Published var activeDisplaySourceName: String = "None"
    @Published var activeDisplaySourceKind: String = "none"
    @Published var clientConnected = false
    /// Device identity of the wireless client currently streaming (nil when none).
    /// WirelessSection reads this to show a "Connected" badge on the matching row.
    @Published var currentWirelessDeviceId: String?
    @Published var currentWirelessDevice: String?
    @Published var hasScreenRecordingPermission = false
    @Published var hasAccessibilityPermission = false
    @Published var adbInstalled = false
    @Published var adbReverseConfigured = false
    @Published var usbDeviceConnected = false
    @Published var wifiConnected = false
    @Published var listeningAddress: String?
    @Published var isRunning = false
    @Published var currentFPS: Double = 0
    @Published var currentBitrate: Double = 0
    @Published var captureMethod: String = "Initializing..."
    @Published var activeInputBackend: String = "CGEvent"
    @Published var virtualHIDStatus: String = "Not checked"
    @Published var virtualHIDStatusDetail: String = ""
    @Published var virtualHIDHelperInstalled: Bool = false
    @Published var virtualHIDHelperActionInProgress: Bool = false
    @Published var virtualHIDHelperMessage: String = ""
    @Published var diagnosticsMessage: String = ""
    @Published var inputPressedKeys: Int = 0
    @Published var inputPressedButtons: Int = 0
    @Published var inputReleaseAllCount: UInt64 = 0
    @Published var inputDroppedStaleCount: UInt64 = 0
    @Published var inputSequenceGapCount: UInt64 = 0
    @Published var inputCoalescedPointerMoves: UInt64 = 0
    @Published var inputLastReleaseReason: String = "None"

    var onToggleServer: (() -> Void)?
    var onInstallVirtualHIDHelper: (() -> Void)?
    var onUninstallVirtualHIDHelper: (() -> Void)?
    var onRefreshVirtualHIDStatus: (() -> Void)?
    var onRefreshPermissions: (() -> Void)?
    var onCopyDiagnostics: (() -> Void)?
    var onPromptAccessibility: (() -> Void)?
    var onSetPairedDeviceRevoked: ((String, Bool) -> Void)?
    var onResetWirelessPairing: (() -> Void)?

    init() {
        self.refreshRate = defaults.object(forKey: keyPrefix + "refreshRate") as? Int ?? 60  // Default: 60 — balanced for most tablets. 120 may saturate high-res panel pipelines.
        self.bitrate = defaults.object(forKey: keyPrefix + "bitrate") as? Int ?? 1000  // Default: 1000 Mbps
        self.quality = defaults.string(forKey: keyPrefix + "quality") ?? "ultralow"  // Default: fastest encoding
        self.gamingBoost = defaults.bool(forKey: keyPrefix + "gamingBoost")
        let streamingProfileRaw = defaults.string(forKey: keyPrefix + "streamingProfile") ?? StreamingProfile.custom.rawValue
        self.streamingProfile = StreamingProfile(rawValue: streamingProfileRaw) ?? .custom
        // Default port 54321 (was 8888 in <=0.7.1; 8888 collides with jupyter/splunk/HP printers).
        // Existing users keep their saved value unless it would collide with the input port.
        self.port = Self.clampedVideoPort(defaults.object(forKey: keyPrefix + "port") as? Int ?? 54321)
        self.touchEnabled = defaults.object(forKey: keyPrefix + "touchEnabled") as? Bool ?? true
        let modeRaw = defaults.string(forKey: keyPrefix + "connectionMode") ?? ConnectionMode.usb.rawValue
        self.connectionMode = ConnectionMode(rawValue: modeRaw) ?? .usb
        if let selectedRemoteDisplayInt = defaults.object(forKey: keyPrefix + "selectedRemoteDisplayID") as? Int, selectedRemoteDisplayInt > 0 {
            self.selectedRemoteDisplayID = CGDirectDisplayID(selectedRemoteDisplayInt)
        } else {
            self.selectedRemoteDisplayID = nil
        }
        let endpointRaw = defaults.string(forKey: keyPrefix + "endpointMode") ?? EndpointMode.lan.rawValue
        self.endpointMode = EndpointMode(rawValue: endpointRaw) ?? .lan
        self.tailnetHost = defaults.string(forKey: keyPrefix + "tailnetHost") ?? ""
        let inputBackendRaw = defaults.string(forKey: keyPrefix + "inputBackendMode") ?? InputBackendMode.automatic.rawValue
        self.inputBackendMode = InputBackendMode(rawValue: inputBackendRaw) ?? .automatic

        print("Loaded settings: \(refreshRate)Hz, bitrate=\(bitrate), quality=\(quality)")
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: keyPrefix + key)
    }

    static let maxVideoPort = UInt16.max - 1

    static func clampedVideoPort(_ value: Int) -> UInt16 {
        UInt16(min(max(value, 1), Int(maxVideoPort)))
    }

    var effectiveBitrate: Int {
        return gamingBoost ? 50 : bitrate
    }

    var effectiveQuality: String {
        return gamingBoost ? "ultralow" : quality
    }

    var effectiveRefreshRate: Int {
        return gamingBoost ? 120 : refreshRate
    }

    func applyStreamingProfile(_ profile: StreamingProfile) {
        guard let preset = profile.settings else {
            streamingProfile = .custom
            return
        }
        applyingProfile = true
        refreshRate = preset.refreshRate
        bitrate = preset.bitrate
        quality = preset.quality
        gamingBoost = preset.gamingBoost
        streamingProfile = profile
        applyingProfile = false
    }

    private func markCustomIfNeeded() {
        if !applyingProfile && streamingProfile != .custom {
            streamingProfile = .custom
        }
    }

    func toggleServer() {
        onToggleServer?()
    }

    func resetToDefaults() {
        let keys = ["refreshRate", "bitrate", "quality", "streamingProfile",
                    "gamingBoost", "port", "touchEnabled", "selectedRemoteDisplayID", "endpointMode", "tailnetHost",
                    "inputBackendMode"]
        let legacyDisplayKeys = ["resolution", "hiDPI", "rotation", "showAllResolutions", "customWidth", "customHeight", "displaySourceMode"]
        for key in keys + legacyDisplayKeys {
            defaults.removeObject(forKey: keyPrefix + key)
        }

        refreshRate = 60  // Default: balanced for daily use
        bitrate = 1000  // Default: 1000 Mbps
        quality = "ultralow"  // Default: fastest encoding
        gamingBoost = false
        streamingProfile = .custom
        port = 54321
        touchEnabled = true
        selectedRemoteDisplayID = nil
        endpointMode = .lan
        tailnetHost = ""
        inputBackendMode = .automatic

        print("Settings reset to defaults")
    }
}

// MARK: - Window Controller

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    convenience init(settings: DisplaySettings) {
        let window = ConstrainedWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 780),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Remote Mac"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let screen = window.screen ?? NSScreen.main else { return }

        var frame = window.frame
        let visibleFrame = screen.visibleFrame
        let minVisibleWidth: CGFloat = 100
        let minVisibleHeight: CGFloat = 50

        if frame.maxX < visibleFrame.minX + minVisibleWidth {
            frame.origin.x = visibleFrame.minX - frame.width + minVisibleWidth
        } else if frame.minX > visibleFrame.maxX - minVisibleWidth {
            frame.origin.x = visibleFrame.maxX - minVisibleWidth
        }

        if frame.maxY < visibleFrame.minY + minVisibleHeight {
            frame.origin.y = visibleFrame.minY - frame.height + minVisibleHeight
        } else if frame.minY > visibleFrame.maxY - minVisibleHeight {
            frame.origin.y = visibleFrame.maxY - minVisibleHeight
        }

        if window.frame != frame {
            window.setFrame(frame, display: true)
        }
    }
}

class ConstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen = screen ?? self.screen ?? NSScreen.main else {
            return frameRect
        }

        var constrainedRect = frameRect
        let visibleFrame = screen.visibleFrame
        let minVisibleWidth: CGFloat = 100
        let minVisibleHeight: CGFloat = 50

        if constrainedRect.maxX < visibleFrame.minX + minVisibleWidth {
            constrainedRect.origin.x = visibleFrame.minX - constrainedRect.width + minVisibleWidth
        } else if constrainedRect.minX > visibleFrame.maxX - minVisibleWidth {
            constrainedRect.origin.x = visibleFrame.maxX - minVisibleWidth
        }

        if constrainedRect.maxY < visibleFrame.minY + minVisibleHeight {
            constrainedRect.origin.y = visibleFrame.minY - constrainedRect.height + minVisibleHeight
        } else if constrainedRect.minY > visibleFrame.maxY - minVisibleHeight {
            constrainedRect.origin.y = visibleFrame.maxY - minVisibleHeight
        }

        return constrainedRect
    }
}

// MARK: - Wireless Section

struct WirelessSection: View {
    @ObservedObject var settings: DisplaySettings
    let pairedDeviceStore: PairedDeviceStore
    @State private var qrImage: NSImage?
    @State private var qrUnavailableReason: String?
    @State private var pairedDevices: [PairedDevice] = []
    @State private var showResetConfirm = false
    @State private var tailnetDiagnostic: TailnetDiagnostic?
    /// Used to force the relative-time labels to recompute every tick even when
    /// the underlying lastConnected timestamp hasn't changed (e.g. while a
    /// device is disconnected and we still want "5 minutes ago" to count up).
    @State private var nowTick: Date = Date()

    var body: some View {
        VStack(spacing: 12) {
            if !settings.isRunning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Click Start at the top to begin listening, then scan the QR.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
            FrostedGroupBox(title: "Pair Device", icon: "qrcode") {
                VStack(spacing: 8) {
                    Picker("", selection: $settings.endpointMode) {
                        Text("LAN").tag(EndpointMode.lan)
                        Text("Tailnet").tag(EndpointMode.tailnet)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if settings.endpointMode == .tailnet {
                        TextField("mac-mini.tailnet.ts.net or 100.x.y.z", text: $settings.tailnetHost)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }

                    if let qr = qrImage {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(8)
                    } else {
                        Text(qrUnavailableReason ?? "Generating QR…").foregroundColor(.secondary)
                    }
                    Text("Scan this QR from Remote Mac Android (Wireless tab)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Text(endpointStatusText())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    if settings.endpointMode == .tailnet, let diagnostic = tailnetDiagnostic {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: tailnetDiagnosticIcon(diagnostic.severity))
                                .foregroundColor(tailnetDiagnosticColor(diagnostic.severity))
                                .font(.system(size: 10, weight: .semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diagnostic.summary)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(tailnetDiagnosticColor(diagnostic.severity))
                                Text(diagnostic.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(tailnetDiagnosticColor(diagnostic.severity).opacity(0.10))
                        .cornerRadius(6)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            FrostedGroupBox(
                title: "Paired Devices (\(pairedDevices.count))",
                icon: "ipad.and.iphone",
                content: {
                if pairedDevices.isEmpty {
                    Text("No devices paired yet.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 6) {
                        ForEach(pairedDevices, id: \.id) { device in
                            let isLive = settings.currentWirelessDeviceId == device.id
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name).font(.system(size: 12, weight: .medium))
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(device.revoked ? Color.red : (isLive ? Color.green : Color.secondary))
                                            .frame(width: 6, height: 6)
                                        Text(device.revoked ? "Revoked" : (isLive ? "Connected" : relativeTimeString(from: device.lastConnected, to: nowTick)))
                                            .font(.system(size: 10))
                                            .foregroundColor(device.revoked ? .red : (isLive ? .green : .secondary))
                                        Text(device.id.suffix(8))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button(device.revoked ? "Allow" : "Revoke") {
                                    if device.revoked {
                                        settings.onSetPairedDeviceRevoked?(device.id, false)
                                    } else {
                                        settings.onSetPairedDeviceRevoked?(device.id, true)
                                    }
                                    refreshPaired()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                        }
                    }
                }
                Button("Reset Token (forget all)") {
                    showResetConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(.red)
                .padding(.top, 6)
            },
            trailing: {
                Button(action: {
                    nowTick = Date()
                    refreshPaired()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Refresh list and timestamps")
            })
        }
        .onAppear {
            refreshQR()
            refreshTailnetDiagnostic()
            refreshPaired()
            nowTick = Date()
        }
        // One-parameter onChange(of:perform:) works on macOS 13+. The
        // two-parameter form requires macOS 14 and would block Ventura.
        // Deprecation is a compile-time warning only on Xcode 15+ SDKs.
        .onChange(of: settings.port) { _ in refreshQR() }
        .onChange(of: settings.endpointMode) { _ in
            refreshQR()
            refreshTailnetDiagnostic()
        }
        .onChange(of: settings.tailnetHost) { _ in
            refreshQR()
            refreshTailnetDiagnostic()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { now in
            nowTick = now
            refreshPaired()
        }
        .alert("Reset Token?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settings.onResetWirelessPairing?()
                refreshQR()
                refreshPaired()
            }
        } message: {
            Text("This will disconnect all paired devices. They will need to scan the new QR to connect again.")
        }
    }

    private func refreshQR() {
        let token = WirelessAuth.loadOrCreate()
        guard let host = EndpointAdvertiser.advertisedHost(mode: settings.endpointMode, tailnetHost: settings.tailnetHost) else {
            qrImage = nil
            qrUnavailableReason = settings.endpointMode == .tailnet
                ? "Enter a Tailnet MagicDNS name or 100.x IP to generate the QR."
                : "No LAN address available yet."
            return
        }
        let name = Host.current().localizedName ?? "Mac"
        let url = PairingURL.build(host: host, port: settings.port, token: token, name: name, mode: settings.endpointMode)
        qrImage = QRRenderer.render(url: url, size: 180)
        qrUnavailableReason = nil
    }

    private func refreshTailnetDiagnostic() {
        guard settings.endpointMode == .tailnet else {
            tailnetDiagnostic = nil
            return
        }

        let host = settings.tailnetHost
        tailnetDiagnostic = TailnetDiagnostic(
            severity: .warning,
            summary: "Checking Tailnet route",
            detail: "Validating MagicDNS or Tailnet IP before the QR is scanned."
        )

        Task {
            let diagnostic = await Task.detached(priority: .utility) {
                TailnetDiagnostics.inspect(host: host)
            }.value
            guard settings.endpointMode == .tailnet, settings.tailnetHost == host else { return }
            tailnetDiagnostic = diagnostic
        }
    }

    private func endpointStatusText() -> String {
        switch settings.endpointMode {
        case .lan:
            return LANAddressResolver.primaryIPv4().map { "LAN: \($0):\(settings.port)" } ?? "WiFi disconnected — no LAN address"
        case .tailnet, .manual:
            let host = settings.tailnetHost.trimmingCharacters(in: .whitespacesAndNewlines)
            return host.isEmpty ? "Tailnet host required" : "Tailnet: \(host):\(settings.port)"
        }
    }

    private func tailnetDiagnosticIcon(_ severity: TailnetDiagnostic.Severity) -> String {
        switch severity {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func tailnetDiagnosticColor(_ severity: TailnetDiagnostic.Severity) -> Color {
        switch severity {
        case .ok: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func refreshPaired() {
        pairedDevices = pairedDeviceStore.all()
    }

    private func relativeTimeString(from past: Date, to now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(past))
        if elapsed < 30 { return "just now" }
        if elapsed < 60 { return "\(Int(elapsed)) seconds ago" }
        if elapsed < 3600 {
            let m = Int(elapsed / 60)
            return "\(m) minute\(m == 1 ? "" : "s") ago"
        }
        if elapsed < 86400 {
            let h = Int(elapsed / 3600)
            return "\(h) hour\(h == 1 ? "" : "s") ago"
        }
        let d = Int(elapsed / 86400)
        return "\(d) day\(d == 1 ? "" : "s") ago"
    }
}
