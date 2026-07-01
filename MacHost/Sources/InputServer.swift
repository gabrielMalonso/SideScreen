import Foundation
import Network

private extension NWEndpoint {
    var isLoopback: Bool {
        switch self {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let v4): return v4.isLoopback
            case .ipv6(let v6): return v6.isLoopback
            case .name(let name, _): return name == "localhost"
            @unknown default: return false
            }
        default:
            return false
        }
    }
}

final class InputServer {
    private let port: UInt16
    private let validateAuthToken: ((Data, String, Data?) -> Bool)?
    private let backend: InputBackend
    private let activeBackend: ActiveInputBackend
    private let isDeviceRevoked: (String) -> Bool
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "inputServerQueue", qos: .userInteractive)

    init(
        port: UInt16,
        validateAuthToken: ((Data, String, Data?) -> Bool)?,
        backend: InputBackend,
        activeBackend: ActiveInputBackend,
        isDeviceRevoked: @escaping (String) -> Bool = { _ in false }
    ) {
        self.port = port
        self.validateAuthToken = validateAuthToken
        self.backend = backend
        self.activeBackend = activeBackend
        self.isDeviceRevoked = isDeviceRevoked
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            if let tcpOptions = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcpOptions.noDelay = true
            }
            listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
            listener?.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            listener?.stateUpdateHandler = { state in
                if case .ready = state {
                    debugLog("InputServer listening on port \(self.port)")
                } else if case .failed(let error) = state {
                    debugLog("InputServer failed: \(error)")
                }
            }
            listener?.start(queue: queue)
        } catch {
            debugLog("InputServer failed to start: \(error)")
        }
    }

    func stop() {
        connection?.cancel()
        listener?.cancel()
        connection = nil
        listener = nil
        backend.endSession(reason: "input server stopped")
    }

    private func handleConnection(_ conn: NWConnection) {
        debugLog("InputServer incoming connection")
        connection?.cancel()
        backend.endSession(reason: "new input connection")
        connection = conn

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn else { return }
            switch state {
            case .ready:
                self.receiveHelloPrefix(on: conn)
            case .failed(let error):
                debugLog("InputServer connection failed: \(error)")
                self.backend.endSession(reason: "input connection failed")
            case .cancelled:
                debugLog("InputServer connection cancelled")
                self.backend.endSession(reason: "input connection cancelled")
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func receiveHelloPrefix(on conn: NWConnection) {
        receiveExact(RemoteInputCodec.helloFixedLength, on: conn) { [weak self, weak conn] prefix in
            guard let self, let conn else { return }
            do {
                let parsed = try RemoteInputCodec.parseHelloPrefix(prefix)
                self.receiveHelloSuffix(length: RemoteInputCodec.helloSuffixLength(for: parsed), prefix: prefix, on: conn)
            } catch {
                self.reject(conn, reason: 1)
            }
        }
    }

    private func receiveHelloSuffix(length: Int, prefix: Data, on conn: NWConnection) {
        receiveExact(length, on: conn) { [weak self, weak conn] suffix in
            guard let self, let conn else { return }
            do {
                let hello = try RemoteInputCodec.parseHello(prefix: prefix, suffix: suffix)
                try self.authorize(hello, connection: conn)
                debugLog("InputServer auth OK — device=\(hello.deviceId), caps=\(hello.capabilities)")
                self.backend.beginSession(deviceId: hello.deviceId)
                conn.send(content: RemoteInputCodec.acceptResponse(backend: self.activeBackend.rawValue), completion: .contentProcessed { _ in })
                self.receiveEventHeader(on: conn)
            } catch RemoteInputProtocolError.invalidToken {
                self.reject(conn, reason: 2)
            } catch RemoteInputProtocolError.deviceRevoked {
                self.reject(conn, reason: 3)
            } catch {
                self.reject(conn, reason: 1)
            }
        }
    }

    private func authorize(_ hello: InputChannelHello, connection: NWConnection) throws {
        if let validateAuthToken {
            guard validateAuthToken(hello.token, hello.deviceId, hello.sessionId) else {
                throw RemoteInputProtocolError.invalidToken
            }
            if isDeviceRevoked(hello.deviceId) {
                throw RemoteInputProtocolError.deviceRevoked
            }
        } else if !connection.endpoint.isLoopback {
            throw RemoteInputProtocolError.invalidToken
        }
    }

    private func reject(_ conn: NWConnection, reason: UInt8) {
        let reasonText: String
        switch reason {
        case 1: reasonText = "invalid hello"
        case 2: reasonText = "invalid token"
        case 3: reasonText = "device revoked"
        default: reasonText = "unknown \(reason)"
        }
        debugLog("InputServer rejecting connection: \(reasonText)")
        conn.send(content: RemoteInputCodec.rejectResponse(reason: reason), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private func receiveEventHeader(on conn: NWConnection) {
        receiveExact(RemoteInputEnvelope.headerLength, on: conn) { [weak self, weak conn] header in
            guard let self, let conn else { return }
            do {
                let parsedHeader = try RemoteInputEnvelope.parseHeader(header)
                if parsedHeader.payloadLength == 0 {
                    let event = try RemoteInputEvent.parse(
                        type: parsedHeader.eventType,
                        sequence: parsedHeader.sequence,
                        timestamp: parsedHeader.timestamp,
                        payload: Data()
                    )
                    self.handleParsedEvent(event, on: conn)
                    self.receiveEventHeader(on: conn)
                } else {
                    self.receiveEventPayload(
                        type: parsedHeader.eventType,
                        sequence: parsedHeader.sequence,
                        timestamp: parsedHeader.timestamp,
                        length: parsedHeader.payloadLength,
                        on: conn
                    )
                }
            } catch {
                debugLog("InputServer invalid header: \(error)")
                self.backend.endSession(reason: "invalid input header")
                conn.cancel()
            }
        }
    }

    private func receiveEventPayload(type: RemoteInputEventType, sequence: UInt64, timestamp: UInt64, length: Int, on conn: NWConnection) {
        receiveExact(length, on: conn) { [weak self, weak conn] payload in
            guard let self, let conn else { return }
            do {
                let event = try RemoteInputEvent.parse(type: type, sequence: sequence, timestamp: timestamp, payload: payload)
                self.handleParsedEvent(event, on: conn)
                self.receiveEventHeader(on: conn)
            } catch {
                debugLog("InputServer invalid payload: \(error)")
                self.backend.endSession(reason: "invalid input payload")
                conn.cancel()
            }
        }
    }

    private func handleParsedEvent(_ event: RemoteInputEvent, on conn: NWConnection) {
        backend.handle(event)
        if case .ping(let sequence, let clientTimestampNanos) = event {
            conn.send(
                content: RemoteInputCodec.inputPongFrame(
                    sequence: sequence,
                    clientTimestampNanos: clientTimestampNanos
                ),
                completion: .contentProcessed { error in
                    if let error {
                        debugLog("InputServer pong send failed: \(error)")
                    }
                }
            )
        }
    }

    private func receiveExact(_ length: Int, on conn: NWConnection, completion: @escaping (Data) -> Void) {
        conn.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                debugLog("InputServer receive error: \(error)")
                self.backend.endSession(reason: "input receive error")
                conn.cancel()
                return
            }
            guard let data, data.count == length, !isComplete else {
                self.backend.endSession(reason: "input closed")
                conn.cancel()
                return
            }
            completion(data)
        }
    }
}
