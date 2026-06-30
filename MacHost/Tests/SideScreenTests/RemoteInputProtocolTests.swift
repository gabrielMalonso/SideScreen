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
        guard case .allInputsUp(let sequence) = event else {
            XCTFail("expected all-inputs-up")
            return
        }
        XCTAssertEqual(sequence, 42)
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
