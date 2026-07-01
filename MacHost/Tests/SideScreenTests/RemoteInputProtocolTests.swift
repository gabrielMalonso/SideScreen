import XCTest
@testable import SideScreen

final class RemoteInputProtocolTests: XCTestCase {
    func testParsesHello() throws {
        let token = Data((0..<32).map { UInt8($0) })
        let device = Array("Tablet".utf8)
        var prefix = Data(RemoteInputCodec.helloMagic)
        prefix.append(1)
        prefix.append(0)
        prefix.append(token)
        prefix.append(UInt8(device.count))

        var suffix = Data(device)
        suffix.append(contentsOf: [0x05, 0x00, 0x00, 0x00])

        let hello = try RemoteInputCodec.parseHello(prefix: prefix, suffix: suffix)
        XCTAssertEqual(hello.token, token)
        XCTAssertEqual(hello.deviceId, "Tablet")
        XCTAssertNil(hello.sessionId)
        XCTAssertEqual(hello.capabilities, 5)
    }

    func testParsesHelloWithSessionId() throws {
        let token = Data((0..<32).map { UInt8($0) })
        let device = Array("Tablet".utf8)
        let sessionId = Data((64..<80).map { UInt8($0) })
        var prefix = Data(RemoteInputCodec.helloMagic)
        prefix.append(1)
        prefix.append(1)
        prefix.append(token)
        prefix.append(UInt8(device.count))

        var suffix = Data(device)
        suffix.append(contentsOf: [0x05, 0x00, 0x00, 0x00])
        suffix.append(sessionId)

        let hello = try RemoteInputCodec.parseHello(prefix: prefix, suffix: suffix)
        XCTAssertEqual(hello.token, token)
        XCTAssertEqual(hello.deviceId, "Tablet")
        XCTAssertEqual(hello.sessionId, sessionId)
        XCTAssertEqual(hello.capabilities, 5)
    }

    func testParsesKeyboardFrame() throws {
        var payload = Data()
        payload.append(0)
        payload.append(contentsOf: [0x07, 0x00])
        payload.append(contentsOf: [0x04, 0x00])
        payload.append(contentsOf: [0x1E, 0x00, 0x00, 0x00])
        payload.append(contentsOf: [0x1D, 0x00, 0x00, 0x00])
        payload.append(0)
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        payload.append(contentsOf: [0x01, 0x00, 0x00, 0x00])

        let event = try RemoteInputEvent.parse(type: .keyboardKey, sequence: 7, timestamp: 99, payload: payload)
        guard case .keyboard(let key) = event else {
            XCTFail("expected keyboard event")
            return
        }
        XCTAssertEqual(key.action, .down)
        XCTAssertEqual(key.usagePage, 0x07)
        XCTAssertEqual(key.usageId, 0x04)
        XCTAssertEqual(key.sequence, 7)
    }

    func testAllInputsUpKeepsSequence() throws {
        let event = try RemoteInputEvent.parse(type: .allInputsUp, sequence: 42, timestamp: 99, payload: Data())
        XCTAssertEqual(event.sequence, 42)
        guard case .allInputsUp(let allUp) = event else {
            XCTFail("expected all-inputs-up")
            return
        }
        XCTAssertEqual(allUp.sequence, 42)
        XCTAssertEqual(allUp.reason, 0)
    }

    func testAllInputsUpParsesReason() throws {
        let event = try RemoteInputEvent.parse(type: .allInputsUp, sequence: 42, timestamp: 99, payload: Data([2]))

        guard case .allInputsUp(let allUp) = event else {
            XCTFail("expected all-inputs-up")
            return
        }
        XCTAssertEqual(allUp.sequence, 42)
        XCTAssertEqual(allUp.reason, 2)
        XCTAssertEqual(allUp.diagnosticReason, "pointer capture lost")
    }

    func testParsesTextCommit() throws {
        let text = "ação çãõ é 🧪"
        let textBytes = Array(text.utf8)
        var payload = Data()
        payload.append(UInt8(textBytes.count & 0xff))
        payload.append(UInt8((textBytes.count >> 8) & 0xff))
        payload.append(contentsOf: textBytes)

        let event = try RemoteInputEvent.parse(type: .textCommit, sequence: 41, timestamp: 99, payload: payload)

        XCTAssertEqual(event.sequence, 41)
        guard case .textCommit(let commit) = event else {
            XCTFail("expected text commit")
            return
        }
        XCTAssertEqual(commit.text, text)
        XCTAssertEqual(commit.androidTimestampNanos, 99)
    }

    func testRejectsOversizedPayloadHeader() {
        var header = Data()
        header.append(RemoteInputEventType.textCommit.rawValue)
        header.append(contentsOf: Array(repeating: 0, count: 16))
        header.append(contentsOf: [0x01, 0x10]) // 4097 bytes

        XCTAssertThrowsError(try RemoteInputEnvelope.parseHeader(header))
    }

    func testRejectsInvalidTextCommitLength() {
        let payload = Data([0x03, 0x00, 0x61])

        XCTAssertThrowsError(try RemoteInputEvent.parse(type: .textCommit, sequence: 41, timestamp: 99, payload: payload))
    }

    func testParsesInputPing() throws {
        let payload = Data([0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
        let event = try RemoteInputEvent.parse(type: .inputPing, sequence: 43, timestamp: 99, payload: payload)

        XCTAssertEqual(event.sequence, 43)
        guard case .ping(let sequence, let value) = event else {
            XCTFail("expected input ping")
            return
        }
        XCTAssertEqual(sequence, 43)
        XCTAssertEqual(value, 0x0102_0304_0506_0708)
    }

    func testInputPongFrameCarriesClientAndServerTimestamps() throws {
        let frame = RemoteInputCodec.inputPongFrame(
            sequence: 44,
            clientTimestampNanos: 0x0102_0304_0506_0708,
            serverTimestampNanos: 0x1112_1314_1516_1718
        )

        let header = try RemoteInputEnvelope.parseHeader(Data(frame.prefix(RemoteInputEnvelope.headerLength)))
        XCTAssertEqual(header.eventType, .inputPong)
        XCTAssertEqual(header.sequence, 44)
        XCTAssertEqual(header.timestamp, 0x1112_1314_1516_1718)
        XCTAssertEqual(header.payloadLength, 16)

        let event = try RemoteInputEvent.parse(
            type: header.eventType,
            sequence: header.sequence,
            timestamp: header.timestamp,
            payload: Data(frame.dropFirst(RemoteInputEnvelope.headerLength))
        )
        guard case .pong(let pong) = event else {
            XCTFail("expected input pong")
            return
        }
        XCTAssertEqual(pong.clientTimestampNanos, 0x0102_0304_0506_0708)
        XCTAssertEqual(pong.serverTimestampNanos, 0x1112_1314_1516_1718)
        XCTAssertEqual(pong.sequence, 44)
    }
}

final class InputIngressTests: XCTestCase {
    func testDropsStaleKeyboardEvents() {
        let backend = RecordingInputBackend()
        let ingress = InputIngress(downstream: backend)
        ingress.beginSession(deviceId: "tablet")

        ingress.handle(.keyboard(key(sequence: 2, action: .down)))
        ingress.handle(.keyboard(key(sequence: 1, action: .up)))

        XCTAssertEqual(backend.events.map(\.sequence), [2])
        ingress.endSession(reason: "test")
    }

    func testFlushesCoalescedPointerBeforeButton() {
        let backend = RecordingInputBackend()
        let ingress = InputIngress(downstream: backend)
        ingress.beginSession(deviceId: "tablet")

        ingress.handle(.pointerRelative(PointerRelativeEvent(dx: 1, dy: 2, unit: 0, flags: 0, sequence: 1)))
        ingress.handle(.pointerRelative(PointerRelativeEvent(dx: 3, dy: 4, unit: 0, flags: 0, sequence: 2)))
        ingress.handle(.pointerButton(PointerButtonEvent(action: .down, button: 0, flags: 0, sequence: 3)))

        guard case .pointerRelative(let move) = backend.events.first else {
            XCTFail("expected pointer relative first")
            return
        }
        XCTAssertEqual(move.dx, 4)
        XCTAssertEqual(move.dy, 6)
        XCTAssertEqual(backend.events.map(\.sequence), [2, 3])
        ingress.endSession(reason: "test")
    }

    func testPublishesDiagnosticsForPressedStateAndReleaseAll() {
        let backend = RecordingInputBackend()
        var snapshots: [InputIngressDiagnostics] = []
        let ingress = InputIngress(downstream: backend) { snapshots.append($0) }
        ingress.beginSession(deviceId: "tablet")

        ingress.handle(.keyboard(key(sequence: 1, action: .down)))
        ingress.releaseAll(reason: "test release")

        XCTAssertEqual(snapshots.last?.pressedKeyCount, 0)
        XCTAssertEqual(snapshots.last?.releaseAllCount, 1)
        XCTAssertEqual(snapshots.last?.lastReleaseReason, "test release")
    }

    func testAllInputsUpUpdatesDiagnostics() {
        let backend = RecordingInputBackend()
        var snapshots: [InputIngressDiagnostics] = []
        let ingress = InputIngress(downstream: backend) { snapshots.append($0) }
        ingress.beginSession(deviceId: "tablet")

        ingress.handle(.keyboard(key(sequence: 1, action: .down)))
        ingress.handle(.allInputsUp(AllInputsUpEvent(reason: 2, sequence: 2)))

        XCTAssertEqual(snapshots.last?.pressedKeyCount, 0)
        XCTAssertEqual(snapshots.last?.releaseAllCount, 1)
        XCTAssertEqual(snapshots.last?.lastReleaseReason, "client all-inputs-up: pointer capture lost")
        ingress.endSession(reason: "test")
    }

    func testSequenceGapReleasesPressedState() {
        let backend = RecordingInputBackend()
        var snapshots: [InputIngressDiagnostics] = []
        let ingress = InputIngress(downstream: backend) { snapshots.append($0) }
        ingress.beginSession(deviceId: "tablet")

        ingress.handle(.keyboard(key(sequence: 1, action: .down)))
        ingress.handle(.keyboard(key(sequence: 3, action: .up)))

        XCTAssertEqual(backend.releaseReasons, ["sequence gap"])
        XCTAssertEqual(snapshots.last?.pressedKeyCount, 0)
        XCTAssertEqual(snapshots.last?.releaseAllCount, 1)
        XCTAssertEqual(snapshots.last?.sequenceGapCount, 1)
        ingress.endSession(reason: "test")
    }

    func testPingKeepsPressedStateAndSequenceAlive() {
        let backend = RecordingInputBackend()
        var snapshots: [InputIngressDiagnostics] = []
        let ingress = InputIngress(downstream: backend) { snapshots.append($0) }
        ingress.beginSession(deviceId: "tablet")

        ingress.handle(.keyboard(key(sequence: 1, action: .down)))
        ingress.handle(.ping(sequence: 2, value: 123))

        XCTAssertEqual(snapshots.last?.pressedKeyCount, 1)
        XCTAssertEqual(snapshots.last?.releaseAllCount, 0)
        XCTAssertEqual(backend.events.map(\.sequence), [1, 2])
        ingress.endSession(reason: "test")
    }

    func testEndSessionPropagatesToDownstreamBackend() {
        let backend = LifecycleRecordingInputBackend()
        let ingress = InputIngress(downstream: backend)
        ingress.beginSession(deviceId: "tablet")

        ingress.endSession(reason: "stream disconnected")

        XCTAssertEqual(backend.beginDeviceIds, ["tablet"])
        XCTAssertEqual(backend.endReasons, ["stream disconnected"])
    }

    private func key(sequence: UInt64, action: RemoteInputAction) -> KeyboardKeyEvent {
        KeyboardKeyEvent(
            action: action,
            usagePage: 0x07,
            usageId: 0x04,
            scanCode: 30,
            androidKeyCode: 29,
            location: 0,
            repeatCount: 0,
            modifiersSnapshot: 0,
            flags: 1,
            sequence: sequence,
            androidTimestampNanos: 0
        )
    }
}

private final class RecordingInputBackend: InputBackend {
    var events: [RemoteInputEvent] = []
    var releaseReasons: [String] = []

    func handle(_ event: RemoteInputEvent) {
        events.append(event)
    }

    func releaseAll(reason: String) {
        releaseReasons.append(reason)
    }
}

private final class LifecycleRecordingInputBackend: InputBackend {
    var beginDeviceIds: [String] = []
    var endReasons: [String] = []

    func beginSession(deviceId: String) {
        beginDeviceIds.append(deviceId)
    }

    func handle(_ event: RemoteInputEvent) {}

    func releaseAll(reason: String) {}

    func endSession(reason: String) {
        endReasons.append(reason)
    }
}
