import Darwin
import Foundation

private enum HelperStatus: UInt8, Error {
    case ok = 0
    case invalidRequest = 1
    case upstreamFailed = 2
}

private enum HelperCommand: UInt8 {
    case initializeDevices = 1
    case resetDevices = 2
    case keyboardReport = 3
    case pointingReport = 4
}

private enum HelperProtocol {
    static let requestMagic = Array("SSHV".utf8)
    static let responseMagic = Array("SSHR".utf8)
    static let version: UInt8 = 1
    static let requestHeaderLength = 8
    static let responseLength = 5
    static let keyboardReportLength = 67
    static let pointingReportLength = 8

    static func socketPath(uid: uid_t) -> String {
        "/tmp/sidescreen-virtualhid-\(uid).sock"
    }

    static func response(_ status: HelperStatus) -> Data {
        Data(responseMagic + [status.rawValue])
    }
}

private enum KarabinerRequest: UInt8 {
    case virtualHIDKeyboardInitialize = 1
    case virtualHIDKeyboardReset = 3
    case virtualHIDPointingInitialize = 4
    case virtualHIDPointingReset = 6
    case postKeyboardInputReport = 7
    case postPointingInputReport = 12
}

private enum KarabinerFrameType: UInt8 {
    case heartbeat = 0
    case healthCheck = 2
    case healthCheckResponse = 3
    case request = 4
    case response = 5
}

private final class KarabinerClient {
    private static let socketPath = "/Library/Application Support/org.pqrs/tmp/rootonly/karabiner_virtual_hid_device_service.sock"
    private static let clientProtocolVersion: UInt16 = 6
    private var fd: Int32 = -1
    private var nextRequestId: UInt64 = 1

    deinit {
        closeSocket()
    }

    func initializeDevices() throws {
        _ = try send(.virtualHIDKeyboardInitialize, payload: keyboardParameters())
        _ = try send(.virtualHIDPointingInitialize)
    }

    func resetDevices() throws {
        _ = try send(.virtualHIDKeyboardReset)
        _ = try send(.virtualHIDPointingReset)
    }

    func postKeyboardReport(_ payload: Data) throws {
        guard payload.count == HelperProtocol.keyboardReportLength else { throw HelperStatus.invalidRequest }
        _ = try send(.postKeyboardInputReport, payload: payload)
    }

    func postPointingReport(_ payload: Data) throws {
        guard payload.count == HelperProtocol.pointingReportLength else { throw HelperStatus.invalidRequest }
        _ = try send(.postPointingInputReport, payload: payload)
    }

    private func send(_ request: KarabinerRequest, payload: Data = Data()) throws -> Data {
        try connectIfNeeded()
        let requestId = nextRequestId
        nextRequestId &+= 1

        var servicePayload = Data()
        servicePayload.appendUInt16LE(Self.clientProtocolVersion)
        servicePayload.append(request.rawValue)
        servicePayload.append(payload)

        var frame = Data()
        frame.appendUInt32BE(UInt32(1 + 8 + servicePayload.count))
        frame.append(KarabinerFrameType.request.rawValue)
        frame.appendUInt64BE(requestId)
        frame.append(servicePayload)

        do {
            try writeAll(frame)
            return try readResponse(requestId: requestId)
        } catch {
            closeSocket()
            throw error
        }
    }

    private func connectIfNeeded() throws {
        guard fd < 0 else { return }
        let socketFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFd >= 0 else { throw HelperStatus.upstreamFailed }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(socketFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard fillSunPath(&address, path: Self.socketPath) else {
            Darwin.close(socketFd)
            throw HelperStatus.upstreamFailed
        }

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(socketFd)
            throw HelperStatus.upstreamFailed
        }
        fd = socketFd
    }

    private func readResponse(requestId: UInt64) throws -> Data {
        while true {
            let header = try readExact(fd: fd, byteCount: 4)
            let bodyLength = Int(header.readUInt32BE(at: 0))
            guard bodyLength >= 1 && bodyLength <= 1033 else { throw HelperStatus.upstreamFailed }
            let body = try readExact(fd: fd, byteCount: bodyLength)
            guard let rawType = body.first,
                  let type = KarabinerFrameType(rawValue: rawType) else {
                throw HelperStatus.upstreamFailed
            }

            switch type {
            case .heartbeat:
                continue
            case .healthCheck:
                var pong = Data()
                pong.appendUInt32BE(1)
                pong.append(KarabinerFrameType.healthCheckResponse.rawValue)
                try writeAll(pong)
            case .response:
                guard body.count >= 9 else { throw HelperStatus.upstreamFailed }
                guard body.readUInt64BE(at: 1) == requestId else { continue }
                return body.subdata(in: 9..<body.count)
            default:
                throw HelperStatus.upstreamFailed
            }
        }
    }

    private func writeAll(_ data: Data) throws {
        try writeAllToSocket(fd: fd, data: data)
    }

    private func closeSocket() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    private func keyboardParameters() -> Data {
        var data = Data()
        data.appendUInt64LE(0x16c0)
        data.appendUInt64LE(0x27db)
        data.appendUInt64LE(0)
        return data
    }
}

private struct HelperArguments {
    let allowedUID: uid_t
    let socketPath: String

    static func parse(_ arguments: [String]) -> HelperArguments? {
        var allowedUID: uid_t?
        var socketPath: String?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--allowed-uid":
                guard index + 1 < arguments.count, let value = UInt32(arguments[index + 1]) else { return nil }
                allowedUID = uid_t(value)
                index += 2
            case "--socket":
                guard index + 1 < arguments.count else { return nil }
                socketPath = arguments[index + 1]
                index += 2
            default:
                return nil
            }
        }
        guard let allowedUID else { return nil }
        return HelperArguments(
            allowedUID: allowedUID,
            socketPath: socketPath ?? HelperProtocol.socketPath(uid: allowedUID)
        )
    }
}

private final class HelperServer {
    private let allowedUID: uid_t
    private let socketPath: String
    private let karabiner = KarabinerClient()
    private var serverFd: Int32 = -1

    init(allowedUID: uid_t, socketPath: String) {
        self.allowedUID = allowedUID
        self.socketPath = socketPath
    }

    deinit {
        stop()
    }

    func run() throws -> Never {
        guard geteuid() == 0 else {
            fputs("SideScreenVirtualHIDHelper must run as root.\n", stderr)
            exit(2)
        }

        try startListening()
        print("SideScreenVirtualHIDHelper listening at \(socketPath) for uid \(allowedUID)")
        while true {
            var peerAddress = sockaddr_un()
            var peerLength = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFd = withUnsafeMutablePointer(to: &peerAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverFd, $0, &peerLength)
                }
            }
            if clientFd < 0 {
                continue
            }
            handle(clientFd)
            Darwin.close(clientFd)
        }
    }

    private func startListening() throws {
        unlink(socketPath)
        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else { throw HelperStatus.upstreamFailed }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard fillSunPath(&address, path: socketPath) else { throw HelperStatus.invalidRequest }

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw HelperStatus.upstreamFailed }
        chown(socketPath, allowedUID, gid_t.max)
        chmod(socketPath, S_IRUSR | S_IWUSR)

        guard listen(serverFd, 8) == 0 else { throw HelperStatus.upstreamFailed }
    }

    private func handle(_ clientFd: Int32) {
        guard peerUID(clientFd) == allowedUID else {
            return
        }

        while true {
            do {
                let header = try readExact(fd: clientFd, byteCount: HelperProtocol.requestHeaderLength)
                let bytes = [UInt8](header)
                guard Array(bytes[0..<4]) == HelperProtocol.requestMagic,
                      bytes[4] == HelperProtocol.version,
                      let command = HelperCommand(rawValue: bytes[5]) else {
                    try writeAllToSocket(fd: clientFd, data: HelperProtocol.response(.invalidRequest))
                    return
                }

                let payloadLength = Int(header.readUInt16BE(at: 6))
                guard payloadLength <= 1024 else {
                    try writeAllToSocket(fd: clientFd, data: HelperProtocol.response(.invalidRequest))
                    return
                }
                let payload = try readExact(fd: clientFd, byteCount: payloadLength)
                try handle(command, payload: payload)
                try writeAllToSocket(fd: clientFd, data: HelperProtocol.response(.ok))
            } catch let status as HelperStatus {
                let responseStatus: HelperStatus = status == .invalidRequest ? .invalidRequest : .upstreamFailed
                try? writeAllToSocket(fd: clientFd, data: HelperProtocol.response(responseStatus))
                return
            } catch {
                try? writeAllToSocket(fd: clientFd, data: HelperProtocol.response(.upstreamFailed))
                return
            }
        }
    }

    private func handle(_ command: HelperCommand, payload: Data) throws {
        switch command {
        case .initializeDevices:
            guard payload.isEmpty else { throw HelperStatus.invalidRequest }
            try karabiner.initializeDevices()
        case .resetDevices:
            guard payload.isEmpty else { throw HelperStatus.invalidRequest }
            try karabiner.resetDevices()
        case .keyboardReport:
            guard payload.count == HelperProtocol.keyboardReportLength else { throw HelperStatus.invalidRequest }
            try karabiner.postKeyboardReport(payload)
        case .pointingReport:
            guard payload.count == HelperProtocol.pointingReportLength else { throw HelperStatus.invalidRequest }
            try karabiner.postPointingReport(payload)
        }
    }

    private func stop() {
        if serverFd >= 0 {
            Darwin.close(serverFd)
            serverFd = -1
        }
        unlink(socketPath)
    }
}

private func peerUID(_ fd: Int32) -> uid_t? {
    var uid = uid_t()
    var gid = gid_t()
    return getpeereid(fd, &uid, &gid) == 0 ? uid : nil
}

private func fillSunPath(_ address: inout sockaddr_un, path: String) -> Bool {
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    return path.withCString { pathPointer -> Bool in
        withUnsafeMutablePointer(to: &address.sun_path) { sunPathPointer in
            sunPathPointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                guard strlen(pathPointer) < capacity else { return false }
                memset(destination, 0, capacity)
                strncpy(destination, pathPointer, capacity - 1)
                return true
            }
        }
    }
}

private func readExact(fd: Int32, byteCount: Int) throws -> Data {
    var data = Data(count: byteCount)
    try data.withUnsafeMutableBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else { return }
        var received = 0
        while received < byteCount {
            let count = Darwin.read(fd, base.advanced(by: received), byteCount - received)
            if count <= 0 {
                throw HelperStatus.upstreamFailed
            }
            received += count
        }
    }
    return data
}

private func writeAllToSocket(fd: Int32, data: Data) throws {
    try data.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else { return }
        var sent = 0
        while sent < data.count {
            let count = Darwin.write(fd, base.advanced(by: sent), data.count - sent)
            if count <= 0 {
                throw HelperStatus.upstreamFailed
            }
            sent += count
        }
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendUInt64BE(_ value: UInt64) {
        append(UInt8((value >> 56) & 0xff))
        append(UInt8((value >> 48) & 0xff))
        append(UInt8((value >> 40) & 0xff))
        append(UInt8((value >> 32) & 0xff))
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendUInt64LE(_ value: UInt64) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 32) & 0xff))
        append(UInt8((value >> 40) & 0xff))
        append(UInt8((value >> 48) & 0xff))
        append(UInt8((value >> 56) & 0xff))
    }

    func readUInt16BE(at offset: Int) -> UInt16 {
        let bytes = [UInt8](self)
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        let bytes = [UInt8](self)
        return (UInt32(bytes[offset]) << 24) |
            (UInt32(bytes[offset + 1]) << 16) |
            (UInt32(bytes[offset + 2]) << 8) |
            UInt32(bytes[offset + 3])
    }

    func readUInt64BE(at offset: Int) -> UInt64 {
        let bytes = [UInt8](self)
        return (UInt64(bytes[offset]) << 56) |
            (UInt64(bytes[offset + 1]) << 48) |
            (UInt64(bytes[offset + 2]) << 40) |
            (UInt64(bytes[offset + 3]) << 32) |
            (UInt64(bytes[offset + 4]) << 24) |
            (UInt64(bytes[offset + 5]) << 16) |
            (UInt64(bytes[offset + 6]) << 8) |
            UInt64(bytes[offset + 7])
    }
}

guard let arguments = HelperArguments.parse(CommandLine.arguments) else {
    fputs("Usage: SideScreenVirtualHIDHelper --allowed-uid <uid> [--socket <path>]\n", stderr)
    exit(64)
}

do {
    try HelperServer(allowedUID: arguments.allowedUID, socketPath: arguments.socketPath).run()
} catch {
    fputs("SideScreenVirtualHIDHelper failed: \(error)\n", stderr)
    exit(1)
}
