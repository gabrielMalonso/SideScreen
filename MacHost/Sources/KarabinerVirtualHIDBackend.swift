import Darwin
import Foundation

enum KarabinerVirtualHIDError: Error, Equatable {
    case socketUnavailable
    case connectFailed(Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
    case invalidResponse
    case unexpectedResponse
}

protocol VirtualHIDReportClient: AnyObject {
    func initializeDevices() throws
    func resetDevices() throws
    func postKeyboardReport(modifiers: UInt8, keys: [UInt16]) throws
    func postPointingReport(buttonMask: UInt32, dx: Int8, dy: Int8, verticalWheel: Int8, horizontalWheel: Int8) throws
}

enum KarabinerVirtualHIDReportCodec {
    static let clientProtocolVersion: UInt16 = 6
    static let keyboardReportLength = 67
    static let pointingReportLength = 8

    enum Request: UInt8 {
        case getStatus = 0
        case virtualHIDKeyboardInitialize = 1
        case virtualHIDKeyboardReset = 3
        case virtualHIDPointingInitialize = 4
        case virtualHIDPointingReset = 6
        case postKeyboardInputReport = 7
        case postPointingInputReport = 12
    }

    enum FrameType: UInt8 {
        case heartbeat = 0
        case request = 4
        case response = 5
        case healthCheck = 2
        case healthCheckResponse = 3
    }

    static func servicePayload(request: Request, payload: Data = Data()) -> Data {
        var data = Data()
        data.appendUInt16LE(clientProtocolVersion)
        data.append(request.rawValue)
        data.append(payload)
        return data
    }

    static func requestFrame(requestId: UInt64, payload: Data) -> Data {
        let bodyLength = 1 + 8 + payload.count
        var data = Data()
        data.appendUInt32BE(UInt32(bodyLength))
        data.append(FrameType.request.rawValue)
        data.appendUInt64BE(requestId)
        data.append(payload)
        return data
    }

    static func healthCheckResponseFrame() -> Data {
        var data = Data()
        data.appendUInt32BE(1)
        data.append(FrameType.healthCheckResponse.rawValue)
        return data
    }

    static func keyboardParameters(vendorId: UInt64 = 0x16c0, productId: UInt64 = 0x27db, countryCode: UInt64 = 0) -> Data {
        var data = Data()
        data.appendUInt64LE(vendorId)
        data.appendUInt64LE(productId)
        data.appendUInt64LE(countryCode)
        return data
    }

    static func keyboardReport(modifiers: UInt8, keys: [UInt16]) -> Data {
        var data = Data()
        data.append(1)
        data.append(modifiers)
        data.append(0)
        for index in 0..<32 {
            data.appendUInt16LE(index < keys.count ? keys[index] : 0)
        }
        return data
    }

    static func pointingReport(buttonMask: UInt32, dx: Int8 = 0, dy: Int8 = 0, verticalWheel: Int8 = 0, horizontalWheel: Int8 = 0) -> Data {
        var data = Data()
        data.appendUInt32LE(buttonMask)
        data.append(UInt8(bitPattern: dx))
        data.append(UInt8(bitPattern: dy))
        data.append(UInt8(bitPattern: verticalWheel))
        data.append(UInt8(bitPattern: horizontalWheel))
        return data
    }
}

enum SideScreenVirtualHIDHelperCodec {
    static let requestMagic = Array("SSHV".utf8)
    static let responseMagic = Array("SSHR".utf8)
    static let version: UInt8 = 1
    static let requestHeaderLength = 8
    static let responseLength = 5

    enum Command: UInt8 {
        case initializeDevices = 1
        case resetDevices = 2
        case keyboardReport = 3
        case pointingReport = 4
    }

    enum ResponseStatus: UInt8 {
        case ok = 0
        case invalidRequest = 1
        case upstreamFailed = 2
    }

    static func helperSocketPath(uid: uid_t = getuid()) -> String {
        "/tmp/sidescreen-virtualhid-\(uid).sock"
    }

    static func request(command: Command, payload: Data = Data()) throws -> Data {
        switch command {
        case .keyboardReport:
            guard payload.count == KarabinerVirtualHIDReportCodec.keyboardReportLength else {
                throw KarabinerVirtualHIDError.invalidResponse
            }
        case .pointingReport:
            guard payload.count == KarabinerVirtualHIDReportCodec.pointingReportLength else {
                throw KarabinerVirtualHIDError.invalidResponse
            }
        case .initializeDevices, .resetDevices:
            guard payload.isEmpty else { throw KarabinerVirtualHIDError.invalidResponse }
        }

        var data = Data(requestMagic)
        data.append(version)
        data.append(command.rawValue)
        data.appendUInt16BE(UInt16(payload.count))
        data.append(payload)
        return data
    }

    static func parseResponse(_ data: Data) throws -> ResponseStatus {
        let bytes = [UInt8](data)
        guard bytes.count == responseLength,
              Array(bytes[0..<4]) == responseMagic,
              let status = ResponseStatus(rawValue: bytes[4]) else {
            throw KarabinerVirtualHIDError.invalidResponse
        }
        return status
    }

    static func response(status: ResponseStatus) -> Data {
        Data(responseMagic + [status.rawValue])
    }
}

final class KarabinerVirtualHIDServiceClient: VirtualHIDReportClient {
    private let socketPath: String
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var nextRequestId: UInt64 = 1

    init(socketPath: String = KarabinerVirtualHIDDetector.socketPath) {
        self.socketPath = socketPath
    }

    deinit {
        closeSocket()
    }

    func initializeDevices() throws {
        lock.lock()
        defer { lock.unlock() }

        _ = try sendRequestLocked(.virtualHIDKeyboardInitialize, payload: KarabinerVirtualHIDReportCodec.keyboardParameters())
        _ = try sendRequestLocked(.virtualHIDPointingInitialize)
    }

    func resetDevices() throws {
        lock.lock()
        defer { lock.unlock() }

        _ = try sendRequestLocked(.virtualHIDKeyboardReset)
        _ = try sendRequestLocked(.virtualHIDPointingReset)
    }

    func postKeyboardReport(modifiers: UInt8, keys: [UInt16]) throws {
        lock.lock()
        defer { lock.unlock() }

        let report = KarabinerVirtualHIDReportCodec.keyboardReport(modifiers: modifiers, keys: keys)
        _ = try sendRequestLocked(.postKeyboardInputReport, payload: report)
    }

    func postPointingReport(buttonMask: UInt32, dx: Int8 = 0, dy: Int8 = 0, verticalWheel: Int8 = 0, horizontalWheel: Int8 = 0) throws {
        lock.lock()
        defer { lock.unlock() }

        let report = KarabinerVirtualHIDReportCodec.pointingReport(buttonMask: buttonMask, dx: dx, dy: dy, verticalWheel: verticalWheel, horizontalWheel: horizontalWheel)
        _ = try sendRequestLocked(.postPointingInputReport, payload: report)
    }

    private func sendRequestLocked(_ request: KarabinerVirtualHIDReportCodec.Request, payload: Data = Data()) throws -> Data {
        try connectIfNeededLocked()
        let requestId = nextRequestId
        nextRequestId &+= 1
        let servicePayload = KarabinerVirtualHIDReportCodec.servicePayload(request: request, payload: payload)
        let frame = KarabinerVirtualHIDReportCodec.requestFrame(requestId: requestId, payload: servicePayload)

        do {
            try writeAllLocked(frame)
            return try readResponseLocked(requestId: requestId)
        } catch {
            closeSocketLocked()
            throw error
        }
    }

    private func connectIfNeededLocked() throws {
        guard fd < 0 else { return }
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw KarabinerVirtualHIDError.socketUnavailable
        }

        let socketFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFd >= 0 else {
            throw KarabinerVirtualHIDError.connectFailed(errno)
        }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(socketFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let sunPathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        let copied = socketPath.withCString { pathPointer -> Bool in
            withUnsafeMutablePointer(to: &address.sun_path) { sunPathPointer in
                sunPathPointer.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { destination in
                    guard strlen(pathPointer) < sunPathCapacity else { return false }
                    strncpy(destination, pathPointer, sunPathCapacity - 1)
                    return true
                }
            }
        }
        guard copied else {
            Darwin.close(socketFd)
            throw KarabinerVirtualHIDError.socketUnavailable
        }

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(socketFd)
            throw KarabinerVirtualHIDError.connectFailed(code)
        }
        fd = socketFd
    }

    private func writeAllLocked(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let count = Darwin.write(fd, base.advanced(by: sent), data.count - sent)
                if count <= 0 {
                    throw KarabinerVirtualHIDError.writeFailed(errno)
                }
                sent += count
            }
        }
    }

    private func readResponseLocked(requestId: UInt64) throws -> Data {
        while true {
            let header = try readExactLocked(byteCount: 4)
            let bodyLength = Int(header.readUInt32BE(at: 0))
            guard bodyLength >= 1 && bodyLength <= 1024 + 1 + 8 else {
                throw KarabinerVirtualHIDError.invalidResponse
            }
            let body = try readExactLocked(byteCount: bodyLength)
            guard let typeByte = body.first,
                  let type = KarabinerVirtualHIDReportCodec.FrameType(rawValue: typeByte) else {
                throw KarabinerVirtualHIDError.invalidResponse
            }

            switch type {
            case .heartbeat:
                continue
            case .healthCheck:
                try writeAllLocked(KarabinerVirtualHIDReportCodec.healthCheckResponseFrame())
            case .response:
                guard body.count >= 9 else { throw KarabinerVirtualHIDError.invalidResponse }
                let receivedRequestId = body.readUInt64BE(at: 1)
                guard receivedRequestId == requestId else { continue }
                return body.subdata(in: 9..<body.count)
            default:
                throw KarabinerVirtualHIDError.unexpectedResponse
            }
        }
    }

    private func readExactLocked(byteCount: Int) throws -> Data {
        var data = Data(count: byteCount)
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var received = 0
            while received < byteCount {
                let count = Darwin.read(fd, base.advanced(by: received), byteCount - received)
                if count <= 0 {
                    throw KarabinerVirtualHIDError.readFailed(errno)
                }
                received += count
            }
        }
        return data
    }

    private func closeSocket() {
        lock.lock()
        defer { lock.unlock() }
        closeSocketLocked()
    }

    private func closeSocketLocked() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }
}

final class SideScreenVirtualHIDHelperClient: VirtualHIDReportClient {
    private let socketPath: String
    private let lock = NSLock()
    private var fd: Int32 = -1

    init(socketPath: String = SideScreenVirtualHIDHelperCodec.helperSocketPath()) {
        self.socketPath = socketPath
    }

    deinit {
        closeSocket()
    }

    func initializeDevices() throws {
        try send(.initializeDevices)
    }

    func resetDevices() throws {
        try send(.resetDevices)
    }

    func postKeyboardReport(modifiers: UInt8, keys: [UInt16]) throws {
        let report = KarabinerVirtualHIDReportCodec.keyboardReport(modifiers: modifiers, keys: keys)
        try send(.keyboardReport, payload: report)
    }

    func postPointingReport(buttonMask: UInt32, dx: Int8 = 0, dy: Int8 = 0, verticalWheel: Int8 = 0, horizontalWheel: Int8 = 0) throws {
        let report = KarabinerVirtualHIDReportCodec.pointingReport(buttonMask: buttonMask, dx: dx, dy: dy, verticalWheel: verticalWheel, horizontalWheel: horizontalWheel)
        try send(.pointingReport, payload: report)
    }

    private func send(_ command: SideScreenVirtualHIDHelperCodec.Command, payload: Data = Data()) throws {
        lock.lock()
        defer { lock.unlock() }

        try connectIfNeededLocked()
        let request = try SideScreenVirtualHIDHelperCodec.request(command: command, payload: payload)
        do {
            try writeAllLocked(request)
            let response = try readExactLocked(byteCount: SideScreenVirtualHIDHelperCodec.responseLength)
            switch try SideScreenVirtualHIDHelperCodec.parseResponse(response) {
            case .ok:
                return
            case .invalidRequest:
                throw KarabinerVirtualHIDError.invalidResponse
            case .upstreamFailed:
                throw KarabinerVirtualHIDError.unexpectedResponse
            }
        } catch {
            closeSocketLocked()
            throw error
        }
    }

    private func connectIfNeededLocked() throws {
        guard fd < 0 else { return }
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw KarabinerVirtualHIDError.socketUnavailable
        }

        let socketFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFd >= 0 else {
            throw KarabinerVirtualHIDError.connectFailed(errno)
        }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(socketFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let sunPathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        let copied = socketPath.withCString { pathPointer -> Bool in
            withUnsafeMutablePointer(to: &address.sun_path) { sunPathPointer in
                sunPathPointer.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { destination in
                    guard strlen(pathPointer) < sunPathCapacity else { return false }
                    strncpy(destination, pathPointer, sunPathCapacity - 1)
                    return true
                }
            }
        }
        guard copied else {
            Darwin.close(socketFd)
            throw KarabinerVirtualHIDError.socketUnavailable
        }

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(socketFd)
            throw KarabinerVirtualHIDError.connectFailed(code)
        }
        fd = socketFd
    }

    private func writeAllLocked(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let count = Darwin.write(fd, base.advanced(by: sent), data.count - sent)
                if count <= 0 {
                    throw KarabinerVirtualHIDError.writeFailed(errno)
                }
                sent += count
            }
        }
    }

    private func readExactLocked(byteCount: Int) throws -> Data {
        var data = Data(count: byteCount)
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var received = 0
            while received < byteCount {
                let count = Darwin.read(fd, base.advanced(by: received), byteCount - received)
                if count <= 0 {
                    throw KarabinerVirtualHIDError.readFailed(errno)
                }
                received += count
            }
        }
        return data
    }

    private func closeSocket() {
        lock.lock()
        defer { lock.unlock() }
        closeSocketLocked()
    }

    private func closeSocketLocked() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }
}

final class KarabinerVirtualHIDBackend: InputBackend {
    private let client: VirtualHIDReportClient
    private var pressedKeys = Set<UInt16>()
    private var pressedButtons = Set<UInt8>()

    init(client: VirtualHIDReportClient = KarabinerVirtualHIDServiceClient()) {
        self.client = client
    }

    func beginSession(deviceId: String) {
        do {
            try client.initializeDevices()
            try postKeyboardState()
            try postPointingState()
            debugLog("Karabiner VirtualHID session started — device=\(deviceId)")
        } catch {
            debugLog("Karabiner VirtualHID begin failed: \(error)")
        }
    }

    func handle(_ event: RemoteInputEvent) {
        do {
            switch event {
            case .keyboard(let key):
                guard key.usagePage == 0x07 else { return }
                if key.action == .down {
                    pressedKeys.insert(key.usageId)
                } else {
                    pressedKeys.remove(key.usageId)
                }
                try postKeyboardState()
            case .pointerRelative(let pointer):
                try postPointerRelative(pointer)
            case .pointerButton(let button):
                if button.action == .down {
                    pressedButtons.insert(button.button)
                } else {
                    pressedButtons.remove(button.button)
                }
                try postPointingState()
            case .pointerWheel(let wheel):
                try postPointerWheel(wheel)
            case .allInputsUp:
                releaseAll(reason: "client all-inputs-up")
            case .ping, .pong:
                break
            }
        } catch {
            debugLog("Karabiner VirtualHID input failed: \(error)")
        }
    }

    func releaseAll(reason: String) {
        pressedKeys.removeAll()
        pressedButtons.removeAll()
        do {
            try postKeyboardState()
            try postPointingState()
            debugLog("Karabiner VirtualHID release-all: \(reason)")
        } catch {
            debugLog("Karabiner VirtualHID release-all failed: \(error)")
        }
    }

    func endSession(reason: String) {
        releaseAll(reason: reason)
        do {
            try client.resetDevices()
        } catch {
            debugLog("Karabiner VirtualHID reset failed: \(error)")
        }
    }

    private func postKeyboardState() throws {
        try client.postKeyboardReport(modifiers: modifierByte(), keys: nonModifierKeys())
    }

    private func postPointingState(dx: Int8 = 0, dy: Int8 = 0, verticalWheel: Int8 = 0, horizontalWheel: Int8 = 0) throws {
        try client.postPointingReport(buttonMask: buttonMask(), dx: dx, dy: dy, verticalWheel: verticalWheel, horizontalWheel: horizontalWheel)
    }

    private func postPointerRelative(_ pointer: PointerRelativeEvent) throws {
        var dx = Int(pointer.dx.rounded())
        var dy = Int(pointer.dy.rounded())
        while dx != 0 || dy != 0 {
            let chunkX = max(-127, min(127, dx))
            let chunkY = max(-127, min(127, dy))
            try postPointingState(dx: Int8(chunkX), dy: Int8(chunkY))
            dx -= chunkX
            dy -= chunkY
        }
    }

    private func postPointerWheel(_ wheel: PointerWheelEvent) throws {
        let vertical = Int8(clamping: Int((-wheel.deltaY).rounded()))
        let horizontal = Int8(clamping: Int((-wheel.deltaX).rounded()))
        try postPointingState(verticalWheel: vertical, horizontalWheel: horizontal)
    }

    private func modifierByte() -> UInt8 {
        var byte: UInt8 = 0
        for usage in pressedKeys {
            switch usage {
            case 0xE0: byte |= 1 << 0
            case 0xE1: byte |= 1 << 1
            case 0xE2: byte |= 1 << 2
            case 0xE3: byte |= 1 << 3
            case 0xE4: byte |= 1 << 4
            case 0xE5: byte |= 1 << 5
            case 0xE6: byte |= 1 << 6
            case 0xE7: byte |= 1 << 7
            default: break
            }
        }
        return byte
    }

    private func nonModifierKeys() -> [UInt16] {
        pressedKeys
            .filter { !(0xE0...0xE7).contains($0) }
            .sorted()
            .prefix(32)
            .map { $0 }
    }

    private func buttonMask() -> UInt32 {
        var mask: UInt32 = 0
        for button in pressedButtons {
            let karabinerButton = UInt32(button) + 1
            if (1...32).contains(karabinerButton) {
                mask |= 1 << (karabinerButton - 1)
            }
        }
        return mask
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    mutating func appendUInt64LE(_ value: UInt64) {
        appendUInt32LE(UInt32(value & 0xffff_ffff))
        appendUInt32LE(UInt32((value >> 32) & 0xffff_ffff))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendUInt16BE(_ value: UInt16) {
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
