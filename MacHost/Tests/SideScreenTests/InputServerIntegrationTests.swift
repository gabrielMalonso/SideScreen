import Darwin
import Foundation
import Network
import XCTest
@testable import SideScreen

final class InputServerIntegrationTests: XCTestCase {
    func testAcceptsLoopbackClientAndDispatchesKeyboardEvent() throws {
        let token = Data((0..<32).map(UInt8.init))
        let backend = SocketRecordingInputBackend()
        let receivedEvent = expectation(description: "backend received keyboard event")
        backend.onEvent = { event in
            if case .keyboard(let key) = event, key.usageId == 0x04 {
                receivedEvent.fulfill()
            }
        }

        let port = try Self.freePort()
        let server = InputServer(
            port: port,
            validateAuthToken: { receivedToken, deviceId, _ in
                receivedToken == token && deviceId == "tablet"
            },
            backend: backend,
            activeBackend: .cgevent
        )
        server.start()
        defer { server.stop() }

        let accepted = expectation(description: "server accepted input channel")
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(integerLiteral: port),
            using: .tcp
        )
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: Self.hello(token: token, deviceId: "tablet"), completion: .contentProcessed { _ in })
                connection.receive(minimumIncompleteLength: 6, maximumLength: 6) { data, _, _, _ in
                    XCTAssertEqual(data, RemoteInputCodec.acceptResponse(backend: ActiveInputBackend.cgevent.rawValue))
                    accepted.fulfill()
                    connection.send(content: Self.keyboardFrame(), completion: .contentProcessed { _ in })
                }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        defer { connection.cancel() }

        wait(for: [accepted, receivedEvent], timeout: 3)
    }

    func testAcceptsWirelessHelloWithSessionId() throws {
        let token = Data((0..<32).map(UInt8.init))
        let sessionId = Data((64..<80).map(UInt8.init))
        let backend = SocketRecordingInputBackend()

        let port = try Self.freePort()
        let server = InputServer(
            port: port,
            validateAuthToken: { receivedToken, deviceId, receivedSessionId in
                receivedToken == token &&
                    deviceId == "tablet" &&
                    receivedSessionId == sessionId
            },
            backend: backend,
            activeBackend: .cgevent
        )
        server.start()
        defer { server.stop() }

        let accepted = expectation(description: "server accepted session-authenticated input channel")
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(integerLiteral: port),
            using: .tcp
        )
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(
                    content: Self.hello(token: token, deviceId: "tablet", sessionId: sessionId),
                    completion: .contentProcessed { _ in }
                )
                connection.receive(minimumIncompleteLength: 6, maximumLength: 6) { data, _, _, _ in
                    XCTAssertEqual(data, RemoteInputCodec.acceptResponse(backend: ActiveInputBackend.cgevent.rawValue))
                    accepted.fulfill()
                }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        defer { connection.cancel() }

        wait(for: [accepted], timeout: 3)
    }

    func testDropActiveConnectionKeepsListenerReadyForReconnect() throws {
        let token = Data((0..<32).map(UInt8.init))
        let backend = SocketRecordingInputBackend()
        let port = try Self.freePort()
        let server = InputServer(
            port: port,
            validateAuthToken: { receivedToken, deviceId, _ in
                receivedToken == token && deviceId == "tablet"
            },
            backend: backend,
            activeBackend: .cgevent
        )
        server.start()
        defer { server.stop() }

        try Self.connectAndExpectAccept(port: port, token: token)
        server.dropActiveConnection(reason: "stream disconnected")
        try Self.connectAndExpectAccept(port: port, token: token)
    }

    private static func hello(token: Data, deviceId: String, sessionId: Data? = nil) -> Data {
        let device = Array(deviceId.utf8)
        var data = Data(RemoteInputCodec.helloMagic)
        data.append(1)
        data.append(sessionId == nil ? 0 : 1)
        data.append(token)
        data.append(UInt8(device.count))
        data.append(contentsOf: device)
        data.append(contentsOf: [0x80, 0x00, 0x00, 0x00])
        if let sessionId {
            data.append(sessionId)
        }
        return data
    }

    private static func keyboardFrame() -> Data {
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

        var frame = Data([RemoteInputEventType.keyboardKey.rawValue])
        frame.appendUInt64LEForTest(1)
        frame.appendUInt64LEForTest(99)
        frame.appendUInt16LEForTest(UInt16(payload.count))
        frame.append(payload)
        return frame
    }

    private static func freePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult =
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        XCTAssertEqual(bindResult, 0)

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult =
            withUnsafeMutablePointer(to: &bound) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(fd, $0, &len)
                }
            }
        XCTAssertEqual(nameResult, 0)
        return UInt16(bigEndian: bound.sin_port)
    }

    private static func connectAndExpectAccept(port: UInt16, token: Data) throws {
        let accepted = XCTestExpectation(description: "server accepted input channel")
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(integerLiteral: port),
            using: .tcp
        )
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: hello(token: token, deviceId: "tablet"), completion: .contentProcessed { _ in })
                connection.receive(minimumIncompleteLength: 6, maximumLength: 6) { data, _, _, _ in
                    XCTAssertEqual(data, RemoteInputCodec.acceptResponse(backend: ActiveInputBackend.cgevent.rawValue))
                    accepted.fulfill()
                }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        defer { connection.cancel() }

        let result = XCTWaiter.wait(for: [accepted], timeout: 3)
        XCTAssertEqual(result, .completed)
    }
}

private final class SocketRecordingInputBackend: InputBackend {
    var onEvent: ((RemoteInputEvent) -> Void)?

    func handle(_ event: RemoteInputEvent) {
        onEvent?(event)
    }

    func releaseAll(reason: String) {}
}

private extension Data {
    mutating func appendUInt16LEForTest(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt64LEForTest(_ value: UInt64) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 32) & 0xff))
        append(UInt8((value >> 40) & 0xff))
        append(UInt8((value >> 48) & 0xff))
        append(UInt8((value >> 56) & 0xff))
    }
}
