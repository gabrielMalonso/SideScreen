import Foundation

enum RemoteInputProtocolError: Error, Equatable {
    case invalidHello
    case invalidToken
    case invalidVersion
    case invalidFrame
    case unsupportedEvent
    case deviceRevoked
}

enum RemoteInputEventType: UInt8 {
    case keyboardKey = 0x01
    case pointerRelative = 0x10
    case pointerButton = 0x11
    case pointerWheel = 0x12
    case allInputsUp = 0x20
    case inputPing = 0x30
    case inputPong = 0x31
}

enum RemoteInputAction: UInt8 {
    case down = 0
    case up = 1
}

struct InputChannelHello {
    let token: Data
    let deviceId: String
    let sessionId: Data?
    let capabilities: UInt32
}

struct RemoteInputEnvelope {
    static let headerLength = 21

    let eventType: RemoteInputEventType
    let sequence: UInt64
    let androidTimestampNanos: UInt64
    let payload: Data

    static func parseHeader(_ data: Data) throws -> (RemoteInputEventType, UInt64, UInt64, Int) {
        let bytes = [UInt8](data)
        guard bytes.count == headerLength,
              let eventType = RemoteInputEventType(rawValue: bytes[0]) else {
            throw RemoteInputProtocolError.invalidFrame
        }
        let sequence = bytes.readUInt64LE(at: 1)
        let timestamp = bytes.readUInt64LE(at: 9)
        let payloadLength = Int(bytes.readUInt16LE(at: 19))
        guard payloadLength <= 4096 else { throw RemoteInputProtocolError.invalidFrame }
        return (eventType, sequence, timestamp, payloadLength)
    }
}

enum RemoteInputEvent {
    case keyboard(KeyboardKeyEvent)
    case pointerRelative(PointerRelativeEvent)
    case pointerButton(PointerButtonEvent)
    case pointerWheel(PointerWheelEvent)
    case allInputsUp(sequence: UInt64)
    case ping(sequence: UInt64, value: UInt64)
    case pong(InputPongEvent)

    var sequence: UInt64 {
        switch self {
        case .keyboard(let event): return event.sequence
        case .pointerRelative(let event): return event.sequence
        case .pointerButton(let event): return event.sequence
        case .pointerWheel(let event): return event.sequence
        case .allInputsUp(let sequence): return sequence
        case .ping(let sequence, _): return sequence
        case .pong(let event): return event.sequence
        }
    }

    static func parse(type: RemoteInputEventType, sequence: UInt64, timestamp: UInt64, payload: Data) throws -> RemoteInputEvent {
        let bytes = [UInt8](payload)
        switch type {
        case .keyboardKey:
            guard bytes.count == 24,
                  let action = RemoteInputAction(rawValue: bytes[0]) else {
                throw RemoteInputProtocolError.invalidFrame
            }
            return .keyboard(KeyboardKeyEvent(
                action: action,
                usagePage: bytes.readUInt16LE(at: 1),
                usageId: bytes.readUInt16LE(at: 3),
                scanCode: bytes.readInt32LE(at: 5),
                androidKeyCode: bytes.readInt32LE(at: 9),
                location: bytes[13],
                repeatCount: bytes.readUInt16LE(at: 14),
                modifiersSnapshot: bytes.readUInt32LE(at: 16),
                flags: bytes.readUInt32LE(at: 20),
                sequence: sequence,
                androidTimestampNanos: timestamp
            ))
        case .pointerRelative:
            guard bytes.count == 13 else { throw RemoteInputProtocolError.invalidFrame }
            return .pointerRelative(PointerRelativeEvent(
                dx: bytes.readFloat32LE(at: 0),
                dy: bytes.readFloat32LE(at: 4),
                unit: bytes[8],
                flags: bytes.readUInt32LE(at: 9),
                sequence: sequence
            ))
        case .pointerButton:
            guard bytes.count == 6,
                  let action = RemoteInputAction(rawValue: bytes[0]) else {
                throw RemoteInputProtocolError.invalidFrame
            }
            return .pointerButton(PointerButtonEvent(
                action: action,
                button: bytes[1],
                flags: bytes.readUInt32LE(at: 2),
                sequence: sequence
            ))
        case .pointerWheel:
            guard bytes.count == 13 else { throw RemoteInputProtocolError.invalidFrame }
            return .pointerWheel(PointerWheelEvent(
                deltaX: bytes.readFloat32LE(at: 0),
                deltaY: bytes.readFloat32LE(at: 4),
                unit: bytes[8],
                flags: bytes.readUInt32LE(at: 9),
                sequence: sequence
            ))
        case .allInputsUp:
            guard bytes.isEmpty else { throw RemoteInputProtocolError.invalidFrame }
            return .allInputsUp(sequence: sequence)
        case .inputPing:
            guard bytes.count == 8 else { throw RemoteInputProtocolError.invalidFrame }
            return .ping(sequence: sequence, value: bytes.readUInt64LE(at: 0))
        case .inputPong:
            guard bytes.count == 16 else { throw RemoteInputProtocolError.invalidFrame }
            return .pong(InputPongEvent(
                clientTimestampNanos: bytes.readUInt64LE(at: 0),
                serverTimestampNanos: bytes.readUInt64LE(at: 8),
                sequence: sequence
            ))
        }
    }
}

struct KeyboardKeyEvent {
    let action: RemoteInputAction
    let usagePage: UInt16
    let usageId: UInt16
    let scanCode: Int32
    let androidKeyCode: Int32
    let location: UInt8
    let repeatCount: UInt16
    let modifiersSnapshot: UInt32
    let flags: UInt32
    let sequence: UInt64
    let androidTimestampNanos: UInt64
}

struct PointerRelativeEvent {
    let dx: Float
    let dy: Float
    let unit: UInt8
    let flags: UInt32
    let sequence: UInt64
}

struct PointerButtonEvent {
    let action: RemoteInputAction
    let button: UInt8
    let flags: UInt32
    let sequence: UInt64
}

struct PointerWheelEvent {
    let deltaX: Float
    let deltaY: Float
    let unit: UInt8
    let flags: UInt32
    let sequence: UInt64
}

struct InputPongEvent {
    let clientTimestampNanos: UInt64
    let serverTimestampNanos: UInt64
    let sequence: UInt64
}

enum RemoteInputCodec {
    static let helloMagic = Array("RMIP".utf8)
    static let acceptMagic = Array("RMIA".utf8)
    static let rejectMagic = Array("RMIR".utf8)
    static let helloFixedLength = 4 + 1 + 1 + 32 + 1
    private static let flagHasSessionId: UInt8 = 0x01

    static func parseHelloPrefix(_ data: Data) throws -> (token: Data, flags: UInt8, deviceIdLength: Int) {
        let bytes = [UInt8](data)
        guard bytes.count == helloFixedLength,
              Array(bytes[0..<4]) == helloMagic else {
            throw RemoteInputProtocolError.invalidHello
        }
        guard bytes[4] == 1 else { throw RemoteInputProtocolError.invalidVersion }
        let flags = bytes[5]
        guard flags & ~flagHasSessionId == 0 else { throw RemoteInputProtocolError.invalidHello }
        let token = Data(bytes[6..<38])
        let deviceIdLength = Int(bytes[38])
        guard (1...64).contains(deviceIdLength) else {
            throw RemoteInputProtocolError.invalidHello
        }
        return (token, flags, deviceIdLength)
    }

    static func parseHello(prefix: Data, suffix: Data) throws -> InputChannelHello {
        let parsed = try parseHelloPrefix(prefix)
        let bytes = [UInt8](suffix)
        let expectedLength = parsed.deviceIdLength + 4 + ((parsed.flags & flagHasSessionId) != 0 ? RemoteSessionCredentials.sessionIdLength : 0)
        guard bytes.count == expectedLength else {
            throw RemoteInputProtocolError.invalidHello
        }
        let nameBytes = Array(bytes[0..<parsed.deviceIdLength])
        guard let deviceId = String(bytes: nameBytes, encoding: .utf8), !deviceId.isEmpty else {
            throw RemoteInputProtocolError.invalidHello
        }
        let capabilities = bytes.readUInt32LE(at: parsed.deviceIdLength)
        let sessionId: Data?
        if (parsed.flags & flagHasSessionId) != 0 {
            let start = parsed.deviceIdLength + 4
            sessionId = Data(bytes[start..<(start + RemoteSessionCredentials.sessionIdLength)])
        } else {
            sessionId = nil
        }
        return InputChannelHello(token: parsed.token, deviceId: deviceId, sessionId: sessionId, capabilities: capabilities)
    }

    static func acceptResponse(backend: UInt8 = 1) -> Data {
        Data(acceptMagic + [0x00, backend])
    }

    static func rejectResponse(reason: UInt8) -> Data {
        Data(rejectMagic + [reason])
    }

    static func inputPongFrame(
        sequence: UInt64,
        clientTimestampNanos: UInt64,
        serverTimestampNanos: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Data {
        var payload = Data()
        payload.appendUInt64LE(clientTimestampNanos)
        payload.appendUInt64LE(serverTimestampNanos)

        var data = Data()
        data.append(RemoteInputEventType.inputPong.rawValue)
        data.appendUInt64LE(sequence)
        data.appendUInt64LE(serverTimestampNanos)
        data.appendUInt16LE(UInt16(payload.count))
        data.append(payload)
        return data
    }
}

private extension Array where Element == UInt8 {
    func readUInt16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }

    func readUInt64LE(at offset: Int) -> UInt64 {
        UInt64(readUInt32LE(at: offset)) | (UInt64(readUInt32LE(at: offset + 4)) << 32)
    }

    func readInt32LE(at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32LE(at: offset))
    }

    func readFloat32LE(at offset: Int) -> Float {
        Float(bitPattern: readUInt32LE(at: offset))
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt64LE(_ value: UInt64) {
        for shift in stride(from: 0, through: 56, by: 8) {
            append(UInt8((value >> UInt64(shift)) & 0xff))
        }
    }
}
