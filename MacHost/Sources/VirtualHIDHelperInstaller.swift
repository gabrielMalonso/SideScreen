import Foundation

struct VirtualHIDHelperInstallStatus: Equatable {
    let helperBinaryInstalled: Bool
    let launchDaemonInstalled: Bool
    let helperSocketAvailable: Bool

    var installed: Bool {
        helperBinaryInstalled && launchDaemonInstalled
    }
}

enum VirtualHIDHelperInstaller {
    static let helperInstallPath = "/Library/PrivilegedHelperTools/com.sidescreen.SideScreenVirtualHIDHelper"

    static func launchDaemonLabel(uid: uid_t = getuid()) -> String {
        "com.sidescreen.virtualhidhelper.\(uid)"
    }

    static func launchDaemonPath(uid: uid_t = getuid()) -> String {
        "/Library/LaunchDaemons/\(launchDaemonLabel(uid: uid)).plist"
    }

    static func status(uid: uid_t = getuid()) -> VirtualHIDHelperInstallStatus {
        VirtualHIDHelperInstallStatus(
            helperBinaryInstalled: FileManager.default.isExecutableFile(atPath: helperInstallPath),
            launchDaemonInstalled: FileManager.default.fileExists(atPath: launchDaemonPath(uid: uid)),
            helperSocketAvailable: FileManager.default.fileExists(atPath: SideScreenVirtualHIDHelperCodec.helperSocketPath(uid: uid))
        )
    }

    static func installForCurrentUser() throws {
        let uid = getuid()
        let helperSource = try bundledHelperPath()
        let plistPath = try writeTemporaryLaunchDaemonPlist(uid: uid)
        defer {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: plistPath))
        }

        let label = launchDaemonLabel(uid: uid)
        let destinationPlist = launchDaemonPath(uid: uid)
        let command = [
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "/bin/cp \(shellQuote(helperSource)) \(shellQuote(helperInstallPath))",
            "/usr/sbin/chown root:wheel \(shellQuote(helperInstallPath))",
            "/bin/chmod 755 \(shellQuote(helperInstallPath))",
            "/bin/cp \(shellQuote(plistPath)) \(shellQuote(destinationPlist))",
            "/usr/sbin/chown root:wheel \(shellQuote(destinationPlist))",
            "/bin/chmod 644 \(shellQuote(destinationPlist))",
            "/bin/launchctl bootout system/\(shellQuote(label)) >/dev/null 2>&1 || true",
            "/bin/launchctl bootstrap system \(shellQuote(destinationPlist))",
            "/bin/launchctl kickstart -k system/\(shellQuote(label))"
        ].joined(separator: " && ")

        try runAsAdministrator(command)
    }

    static func uninstallForCurrentUser() throws {
        let uid = getuid()
        let label = launchDaemonLabel(uid: uid)
        let daemonPath = launchDaemonPath(uid: uid)
        let socketPath = SideScreenVirtualHIDHelperCodec.helperSocketPath(uid: uid)
        let command = [
            "/bin/launchctl bootout system/\(shellQuote(label)) >/dev/null 2>&1 || true",
            "/bin/rm -f \(shellQuote(daemonPath))",
            "/bin/rm -f \(shellQuote(socketPath))"
        ].joined(separator: " && ")

        try runAsAdministrator(command)
    }

    static func helperSourceCandidates(
        executableDirectory: String?,
        resourceDirectory: String?,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> [String] {
        [
            executableDirectory.map { "\($0)/SideScreenVirtualHIDHelper" },
            resourceDirectory.map { "\($0)/SideScreenVirtualHIDHelper" },
            resourceDirectory.map { "\($0)/../Library/PrivilegedHelperTools/SideScreenVirtualHIDHelper" },
            "\(currentDirectory)/.build/out/Products/Release/SideScreenVirtualHIDHelper",
            "\(currentDirectory)/.build/out/Products/Debug/SideScreenVirtualHIDHelper",
            "\(currentDirectory)/.build/release/SideScreenVirtualHIDHelper",
            "\(currentDirectory)/.build/debug/SideScreenVirtualHIDHelper"
        ].compactMap { $0 }
    }

    private static func bundledHelperPath() throws -> String {
        let executableDirectory = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .path
        let resourceDirectory = Bundle.main.resourceURL?.path
        let candidates = helperSourceCandidates(
            executableDirectory: executableDirectory,
            resourceDirectory: resourceDirectory
        )

        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw NSError(
            domain: "SideScreen.VirtualHIDHelperInstaller",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "SideScreenVirtualHIDHelper was not found next to the app executable, app resources, or Swift build products."]
        )
    }

    static func launchDaemonPlistData(uid: uid_t) throws -> Data {
        let socketPath = SideScreenVirtualHIDHelperCodec.helperSocketPath(uid: uid)
        let plist: [String: Any] = [
            "Label": launchDaemonLabel(uid: uid),
            "ProgramArguments": [
                helperInstallPath,
                "--allowed-uid",
                "\(uid)",
                "--socket",
                socketPath
            ],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": "/tmp/sidescreen-virtualhid-helper-\(uid).log",
            "StandardErrorPath": "/tmp/sidescreen-virtualhid-helper-\(uid).err"
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private static func writeTemporaryLaunchDaemonPlist(uid: uid_t) throws -> String {
        let path = NSTemporaryDirectory() + "\(launchDaemonLabel(uid: uid)).plist"
        try launchDaemonPlistData(uid: uid).write(to: URL(fileURLWithPath: path), options: .atomic)
        return path
    }

    private static func runAsAdministrator(_ command: String) throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "SideScreen.VirtualHIDHelperInstaller",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Administrator helper command failed."]
            )
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
