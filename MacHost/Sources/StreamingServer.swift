import Foundation
import Network

private enum WireMessage {
    static let legacyVideoFrame: UInt8 = 0
    static let displayConfig: UInt8 = 1
    static let touchEvent: UInt8 = 2
    static let ping: UInt8 = 4
    static let pong: UInt8 = 5
    static let videoFrameWithMetadata: UInt8 = 6
    static let keyframeRequest: UInt8 = 7
    static let clientSupportsFrameMetadata: UInt8 = 8
    /// Client→server, payload-free (old hosts consume 1 byte safely):
    /// "this device has no HEVC decoder".
    static let clientAvcOnly: UInt8 = 9
    /// Server→client, 1-byte payload (StreamCodec.wireId). Sent ONLY to
    /// clients that sent clientAvcOnly — old clients disconnect on unknown
    /// message types, so this must never be sent unsolicited.
    static let codecSelected: UInt8 = 10
    static let clientSupportsDisplayControl: UInt8 = 11
    static let displayControlJson: UInt8 = 12
}

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

class StreamingServer {
    private let port: UInt16
    private var listener: NWListener?
    private var connection: NWConnection?
    var onClientConnected: (() -> Void)?
    var onClientDisconnected: (() -> Void)?
    /// Fired once per connection during protocol startup, BEFORE the display
    /// config is sent, for every outcome (.hevc or .h264) — so the capture
    /// pipeline can also revert to HEVC after an AVC-only client goes away.
    var onCodecNegotiated: ((StreamCodec) -> Void)?
    // Touch callback: (x1, y1, action, pointerCount, x2, y2)
    var onTouchEvent: ((Float, Float, Int, Int, Float, Float) -> Void)?
    var onStats: ((Double, Double) -> Void)?
    var onKeyframeRequested: ((Bool) -> Void)?
    var onDisplayControlReady: (() -> Void)?
    var onDisplayControlMessage: ((DisplayControlEnvelope) -> Void)?
    // Whether host wants to receive touch events from client. Ping/pong is
    // handled regardless. When false, incoming touch frames are dropped
    // immediately without parsing or dispatching to main queue.
    var touchEnabled: Bool = true

    // Wireless auth: when non-nil, non-loopback connections must present this
    // 32-byte token before being allowed to proceed. nil means wireless mode
    // is inactive — non-loopback connections are rejected immediately.
    var expectedAuthToken: Data?
    var onWirelessClientPaired: ((String, String, Data?) -> Void)?
    var isWirelessDeviceRevoked: ((String) -> Bool)?
    var wirelessDeviceSecret: ((String) -> Data?)?
    var makeWirelessSessionCredentials: ((String) throws -> RemoteSessionCredentials?)?

    private let frameQueue = DispatchQueue(label: "frameQueue", qos: .userInteractive)
    private let receiveQueue = DispatchQueue(label: "receiveQueue", qos: .userInteractive)
    private let networkQueue = DispatchQueue(label: "networkQueue", qos: .userInteractive)
    private var bytesSent: UInt64 = 0
    private var frameCount: UInt64 = 0
    private var droppedFrames: UInt64 = 0
    private var lastStatsTime = DispatchTime.now()
    private var displayWidth = 1920
    private var displayHeight = 1080
    private var rotation = 0
    private var isReceiving = false
    private var isStopped = false
    private var connectionReady = false
    private var waitingForSyncFrame = false
    private var clientSupportsFrameMetadata = false
    private var clientIsAvcOnly = false
    private var clientSupportsDisplayControl = false
    private var inputBuffer = Data()
    private var seenAuthNonces = Set<String>()

    init(port: UInt16) {
        self.port = port
    }

    func start() {
        isStopped = false
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            // Optimize TCP for low-latency streaming
            if let tcpOptions = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcpOptions.noDelay = true  // Disable Nagle's algorithm
                tcpOptions.enableFastOpen = true
            }

            listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))

            listener?.newConnectionHandler = { [weak self] newConnection in
                self?.handleConnection(newConnection)
            }

            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    debugLog("TCP Server listening on port \(self.port)")
                case .failed(let error):
                    debugLog("Server failed: \(error)")
                default:
                    break
                }
            }

            listener?.start(queue: networkQueue)
        } catch {
            debugLog("Failed to start server: \(error)")
        }
    }

    private func handleConnection(_ newConnection: NWConnection) {
        debugLog("New connection incoming...")

        // Clean up old connection properly
        if let oldConnection = connection {
            debugLog("Replacing active stream connection")
            isReceiving = false
            oldConnection.cancel()
            onClientDisconnected?()
        }

        connectionReady = false
        clientSupportsFrameMetadata = false
        clientIsAvcOnly = false
        clientSupportsDisplayControl = false
        waitingForSyncFrame = true
        inputBuffer.removeAll(keepingCapacity: true)
        connection = newConnection
        droppedFrames = 0

        connection?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            guard self.connection === newConnection else {
                debugLog("Ignoring stale stream connection state: \(state)")
                return
            }
            debugLog("Connection state: \(state)")
            switch state {
            case .ready:
                self.onConnectionReady(newConnection)
            case .failed(let error):
                debugLog("Connection failed: \(error)")
                self.onClientDisconnected?()
            case .cancelled:
                debugLog("Connection cancelled")
                self.onClientDisconnected?()
            default:
                break
            }
        }

        connection?.start(queue: networkQueue)
    }

    private func onConnectionReady(_ conn: NWConnection) {
        if conn.endpoint.isLoopback {
            debugLog("Client connected via loopback (USB) — skipping auth")
            beginExistingProtocol(on: conn)
            return
        }
        guard let expected = expectedAuthToken else {
            debugLog("Rejecting non-loopback client: wireless mode not active")
            conn.cancel()
            return
        }
        debugLog("Client connected via LAN — running auth handshake")
        runAuthHandshake(connection: conn, expectedToken: expected)
    }

    private func beginExistingProtocol(on conn: NWConnection) {
        startReceivingTouch()

        // Give new clients a short chance to opt in before the first frame.
        // Legacy clients send no capability message, so we continue shortly
        // after this window with the old frame type.
        networkQueue.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self, weak conn] in
            guard let self = self, let conn = conn else { return }
            self.finishProtocolStartup(on: conn)
        }
    }

    private func finishProtocolStartup(on conn: NWConnection) {
        guard connection === conn, !isStopped, !connectionReady else { return }

        let codec: StreamCodec = clientIsAvcOnly ? .h264 : .hevc
        if clientIsAvcOnly {
            // Safe to send: this client opted in via type 9. Must precede the
            // display config so the client knows the codec before it sizes
            // and configures its decoder.
            let msg = Data([WireMessage.codecSelected, codec.wireId])
            conn.send(content: msg, completion: .contentProcessed { _ in })
            debugLog("Sent codecSelected: H.264")
        }
        // Synchronous, before sendDisplaySize(): the handler switches the
        // encoder AND updates displayWidth/Height (clamped for H.264) so the
        // display config below carries decoder-safe dimensions.
        onCodecNegotiated?(codec)

        debugLog("Client connected - sending display config first")
        sendDisplaySize()
        connectionReady = true
        debugLog("Connection ready for frames (metadata=\(clientSupportsFrameMetadata ? "on" : "off"), codec=\(codec))")
        onClientConnected?()
    }

    private func runAuthHandshake(connection conn: NWConnection, expectedToken: Data) {
        conn.receive(minimumIncompleteLength: HandshakeCodec.fixedPrefixLen,
                     maximumLength: HandshakeCodec.fixedPrefixLen) { [weak self] prefixData, _, _, error in
            guard let self else { return }
            if let error {
                debugLog("Auth read error: \(error)")
                conn.cancel()
                return
            }
            guard let prefix = prefixData, prefix.count == HandshakeCodec.fixedPrefixLen else {
                self.sendAuthResponse(conn, status: .invalidMagic, thenClose: true)
                return
            }

            let format: HandshakeCodec.RequestFormat
            let nameLen: Int
            do {
                format = try HandshakeCodec.requestFormat(fromPrefix: prefix)
                nameLen = try HandshakeCodec.nameLength(fromPrefix: prefix)
            } catch HandshakeError.invalidName {
                self.sendAuthResponse(conn, status: .invalidName, thenClose: true)
                return
            } catch {
                self.sendAuthResponse(conn, status: .invalidMagic, thenClose: true)
                return
            }

            conn.receive(minimumIncompleteLength: nameLen, maximumLength: nameLen) { [weak self] nameData, _, _, error in
                guard let self else { return }
                if let error {
                    debugLog("Auth name read error: \(error)")
                    conn.cancel()
                    return
                }
                guard let nameData, nameData.count == nameLen else {
                    self.sendAuthResponse(conn, status: .invalidName, thenClose: true)
                    return
                }
                let prefixAndName = prefix + nameData
                if format != .legacy {
                    self.receiveAuthDeviceId(prefixAndName: prefixAndName, format: format, connection: conn, expectedToken: expectedToken)
                } else {
                    self.finishAuthHandshake(request: prefixAndName, connection: conn, expectedToken: expectedToken)
                }
            }
        }
    }

    private func receiveAuthDeviceId(
        prefixAndName: Data,
        format: HandshakeCodec.RequestFormat,
        connection conn: NWConnection,
        expectedToken: Data
    ) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] lengthData, _, _, error in
            guard let self else { return }
            if let error {
                debugLog("Auth device id length read error: \(error)")
                conn.cancel()
                return
            }
            guard let lengthData, lengthData.count == 1, let deviceIdLength = lengthData.first, (1...64).contains(Int(deviceIdLength)) else {
                self.sendAuthResponse(conn, status: .invalidName, thenClose: true)
                return
            }
            conn.receive(minimumIncompleteLength: Int(deviceIdLength), maximumLength: Int(deviceIdLength)) { [weak self] deviceIdData, _, _, error in
                guard let self else { return }
                if let error {
                    debugLog("Auth device id read error: \(error)")
                    conn.cancel()
                    return
                }
                guard let deviceIdData, deviceIdData.count == Int(deviceIdLength) else {
                    self.sendAuthResponse(conn, status: .invalidName, thenClose: true)
                    return
                }
                let requestWithoutSecret = prefixAndName + lengthData + deviceIdData
                if format == .deviceSecret {
                    self.receiveAuthDeviceAuthenticator(requestWithoutSecret: requestWithoutSecret, connection: conn, expectedToken: expectedToken)
                } else {
                    self.finishAuthHandshake(request: requestWithoutSecret, connection: conn, expectedToken: expectedToken)
                }
            }
        }
    }

    private func receiveAuthDeviceAuthenticator(requestWithoutSecret: Data, connection conn: NWConnection, expectedToken: Data) {
        let authLength = HandshakeCodec.deviceSecretLength + HandshakeCodec.authNonceLength + HandshakeCodec.authTagLength
        conn.receive(minimumIncompleteLength: authLength, maximumLength: authLength) { [weak self] secretData, _, _, error in
            guard let self else { return }
            if let error {
                debugLog("Auth device authenticator read error: \(error)")
                conn.cancel()
                return
            }
            guard let secretData, secretData.count == authLength else {
                self.sendAuthResponse(conn, status: .invalidName, thenClose: true)
                return
            }
            self.finishAuthHandshake(request: requestWithoutSecret + secretData, connection: conn, expectedToken: expectedToken)
        }
    }

    private func finishAuthHandshake(request: Data, connection conn: NWConnection, expectedToken: Data) {
        do {
            let parsed = try HandshakeCodec.parseRequest(request)
            let tokenValid = WirelessAuth.validate(parsed.token, expected: expectedToken)
            let storedSecret = wirelessDeviceSecret?(parsed.deviceId)
            let hmacValidWithSentSecret = HandshakeCodec.validateAuthenticationTag(
                parsed.authTag,
                deviceSecret: parsed.deviceSecret,
                deviceId: parsed.deviceId,
                deviceName: parsed.deviceName,
                clientNonce: parsed.clientNonce
            )
            let hmacValidWithStoredSecret = HandshakeCodec.validateAuthenticationTag(
                parsed.authTag,
                deviceSecret: storedSecret,
                deviceId: parsed.deviceId,
                deviceName: parsed.deviceName,
                clientNonce: parsed.clientNonce
            )

            let acceptedByLegacyToken = parsed.isLegacyIdentity || parsed.deviceSecret == nil
            let acceptedByPairingToken = tokenValid && (acceptedByLegacyToken || hmacValidWithSentSecret)
            let acceptedByDeviceSecret = !tokenValid && hmacValidWithStoredSecret
            guard acceptedByPairingToken || acceptedByDeviceSecret else {
                debugLog("Wireless auth rejected: token/HMAC mismatch id=...\(parsed.deviceId.suffix(4))")
                sendAuthResponse(conn, status: .invalidToken, thenClose: true)
                return
            }
            if !parsed.isLegacyIdentity,
               let clientNonce = parsed.clientNonce,
               !rememberAuthNonce(clientNonce, deviceId: parsed.deviceId) {
                debugLog("Wireless auth rejected: replayed nonce id=...\(parsed.deviceId.suffix(4))")
                sendAuthResponse(conn, status: .invalidToken, thenClose: true)
                return
            }
            if isWirelessDeviceRevoked?(parsed.deviceId) == true {
                debugLog("Wireless auth rejected: device revoked id=...\(parsed.deviceId.suffix(4))")
                sendAuthResponse(conn, status: .deviceRevoked, thenClose: true)
                return
            }
            debugLog("Wireless auth OK — device: \(parsed.deviceName), id=...\(parsed.deviceId.suffix(4))")
            if parsed.isLegacyIdentity {
                sendAuthResponse(conn, status: .ok, thenClose: false)
            } else if let credentials = try makeWirelessSessionCredentials?(parsed.deviceId) {
                sendAuthResponse(conn, bytes: HandshakeCodec.encodeV2AcceptResponse(credentials: credentials), thenClose: false)
            } else {
                debugLog("Wireless auth rejected: session creation failed")
                sendAuthResponse(conn, status: .invalidToken, thenClose: true)
                return
            }
            let secretToStore = tokenValid && hmacValidWithSentSecret ? parsed.deviceSecret : nil
            onWirelessClientPaired?(parsed.deviceId, parsed.deviceName, secretToStore)
            beginExistingProtocol(on: conn)
        } catch HandshakeError.invalidMagic {
            sendAuthResponse(conn, status: .invalidMagic, thenClose: true)
        } catch HandshakeError.invalidName {
            sendAuthResponse(conn, status: .invalidName, thenClose: true)
        } catch HandshakeError.invalidDeviceId {
            sendAuthResponse(conn, status: .invalidName, thenClose: true)
        } catch {
            sendAuthResponse(conn, status: .invalidMagic, thenClose: true)
        }
    }

    private func rememberAuthNonce(_ nonce: Data, deviceId: String) -> Bool {
        let key = "\(deviceId):\(nonce.base64EncodedString())"
        if seenAuthNonces.count > 4096 {
            seenAuthNonces.removeAll(keepingCapacity: true)
        }
        return seenAuthNonces.insert(key).inserted
    }

    private func sendAuthResponse(_ conn: NWConnection, status: HandshakeStatus, thenClose: Bool) {
        sendAuthResponse(conn, bytes: HandshakeCodec.encodeResponse(status: status), thenClose: thenClose)
    }

    private func sendAuthResponse(_ conn: NWConnection, bytes: Data, thenClose: Bool) {
        conn.send(content: bytes, completion: .contentProcessed { _ in
            if thenClose {
                debugLog("Auth rejected, closing connection")
                conn.cancel()
            }
        })
    }

    func setDisplaySize(width: Int, height: Int, rotation: Int = 0) {
        displayWidth = width
        displayHeight = height
        self.rotation = rotation
    }

    /// Update rotation and send to connected client
    func updateRotation(_ rotation: Int) {
        self.rotation = rotation
        sendDisplaySize() // Re-send display config with new rotation
    }

    func sendDisplaySize() {
        guard let connection = connection else { return }

        var data = Data()
        data.append(WireMessage.displayConfig) // Type: Display size + rotation
        data.append(contentsOf: withUnsafeBytes(of: Int32(displayWidth).bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(displayHeight).bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(rotation).bigEndian) { Data($0) })

        connection.send(content: data, completion: .contentProcessed { _ in })
        debugLog("Sent display config: \(displayWidth)x\(displayHeight) @ \(rotation)°")
    }

    func sendDisplayControl(_ envelope: DisplayControlEnvelope) {
        guard let connection = connection, clientSupportsDisplayControl else { return }
        do {
            let payload = try DisplayControlCodec.encode(envelope)
            var data = Data(capacity: 5 + payload.count)
            data.append(WireMessage.displayControlJson)
            var length = UInt32(payload.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(payload)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    debugLog("Display control send failed: \(error)")
                }
            })
            debugLog("Sent display control message: \(envelope.type.rawValue)")
        } catch {
            debugLog("Failed to encode display control message: \(error)")
        }
    }

    private func startReceivingTouch() {
        guard !isReceiving else {
            debugLog("Already receiving touch events")
            return
        }
        isReceiving = true
        debugLog("Starting input receive loop... (touch=\(touchEnabled ? "on" : "off"))")

        // Use loop-based pattern instead of recursion to prevent stack overflow
        receiveQueue.async { [weak self] in
            self?.touchReceiveLoop()
        }
    }

    private func touchReceiveLoop() {
        guard let connection = connection, isReceiving, !isStopped else {
            isReceiving = false
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { [weak self] data, _, isComplete, error in
            guard let self = self, self.isReceiving, !self.isStopped else { return }
            guard self.connection === connection else {
                debugLog("Ignoring stale stream input callback")
                return
            }

            if error != nil || isComplete {
                self.isReceiving = false
                self.inputBuffer.removeAll(keepingCapacity: true)
                return
            }

            if let data = data, !data.isEmpty {
                self.inputBuffer.append(data)
                self.processInputBuffer(connection: connection)
            }

            self.receiveQueue.async {
                self.touchReceiveLoop()
            }
        }
    }

    private func processInputBuffer(connection: NWConnection) {
        while let msgType = inputBuffer.first {
            switch msgType {
            case WireMessage.touchEvent:
                // Touch event: 1 type + 1 pointerCount + N*(4x+4y) + 4 action.
                // 1 finger: 14 bytes, 2 fingers: 22 bytes.
                guard inputBuffer.count >= 2 else { return }

                let pointerCount = Int(inputByte(at: 1))
                guard pointerCount == 1 || pointerCount == 2 else {
                    debugLog("Invalid touch pointer count: \(pointerCount)")
                    consumeInputBytes(1)
                    continue
                }

                let expectedSize = 2 + pointerCount * 8 + 4
                guard inputBuffer.count >= expectedSize else { return }

                let message = Data(inputBuffer.prefix(expectedSize))
                consumeInputBytes(expectedSize)

                // Drop early if host has touch disabled, after consuming exactly
                // this touch frame so coalesced ping/keyframe messages survive.
                if touchEnabled {
                    handleTouchMessage(message, pointerCount: pointerCount)
                }

            case WireMessage.ping:
                // Ping from client: echo back as pong (type=5) with client's timestamp.
                guard inputBuffer.count >= 9 else { return }

                let clientTimestamp = Data(inputBuffer.dropFirst().prefix(8))
                consumeInputBytes(9)

                var pong = Data(capacity: 9)
                pong.append(WireMessage.pong) // Type: Pong
                pong.append(clientTimestamp)
                connection.send(content: pong, completion: .contentProcessed { _ in })

            case WireMessage.keyframeRequest:
                // Keyframe request from Android decoder. The client sends a
                // two-byte message: type + flags.
                guard inputBuffer.count >= 2 else { return }

                let flags = inputByte(at: 1)
                consumeInputBytes(2)
                onKeyframeRequested?((flags & 1) != 0)

            case WireMessage.clientSupportsFrameMetadata:
                // One-byte opt-in from newer clients. Keeping this payload-free
                // lets older hosts safely ignore it without misaligning input.
                consumeInputBytes(1)
                if !clientSupportsFrameMetadata {
                    clientSupportsFrameMetadata = true
                    debugLog("Client supports video frame metadata")
                }
                finishProtocolStartup(on: connection)

            case WireMessage.clientAvcOnly:
                // Payload-free opt-in (same convention as type 8): the client
                // has no HEVC decoder, stream H.264 instead. Clients send this
                // BEFORE type 8, so it lands before finishProtocolStartup runs.
                consumeInputBytes(1)
                if !clientIsAvcOnly {
                    clientIsAvcOnly = true
                    debugLog("Client is AVC-only — will negotiate H.264")
                }

            case WireMessage.clientSupportsDisplayControl:
                consumeInputBytes(1)
                if !clientSupportsDisplayControl {
                    clientSupportsDisplayControl = true
                    debugLog("Client supports display control")
                    onDisplayControlReady?()
                }

            case WireMessage.displayControlJson:
                guard inputBuffer.count >= 5 else { return }
                let payloadLength = Int(inputBuffer.dropFirst().prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
                guard payloadLength <= DisplayControlCodec.maxPayloadBytes else {
                    debugLog("Display control payload too large: \(payloadLength)")
                    consumeInputBytes(1)
                    continue
                }
                let expectedSize = 5 + payloadLength
                guard inputBuffer.count >= expectedSize else { return }
                let payload = Data(inputBuffer.dropFirst(5).prefix(payloadLength))
                consumeInputBytes(expectedSize)
                do {
                    let envelope = try DisplayControlCodec.decode(payload)
                    onDisplayControlMessage?(envelope)
                } catch {
                    debugLog("Invalid display control payload: \(error)")
                }

            default:
                debugLog("Unknown client input type: \(msgType)")
                consumeInputBytes(1)
            }
        }
    }

    private func handleTouchMessage(_ data: Data, pointerCount: Int) {
        let x1 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 2, as: Float.self) }
        let y1 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 6, as: Float.self) }

        var x2: Float = 0
        var y2: Float = 0
        if pointerCount >= 2 {
            x2 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 10, as: Float.self) }
            y2 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 14, as: Float.self) }
        }

        let actionOffset = 2 + pointerCount * 8
        let action = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: actionOffset, as: Int32.self) }

        DispatchQueue.main.async {
            self.onTouchEvent?(x1, y1, Int(action), pointerCount, x2, y2)
        }
    }

    private func inputByte(at offset: Int) -> UInt8 {
        inputBuffer[inputBuffer.index(inputBuffer.startIndex, offsetBy: offset)]
    }

    private func consumeInputBytes(_ count: Int) {
        let endIndex = inputBuffer.index(inputBuffer.startIndex, offsetBy: count)
        inputBuffer.removeSubrange(inputBuffer.startIndex..<endIndex)
    }

    func sendFrame(_ data: Data, timestamp: UInt64, isKeyframe: Bool = false) {
        guard let connection = connection, !isStopped, connectionReady else { return }

        // With short-GOP encoding, a fresh client must start on a keyframe —
        // sending P-frames before the first IDR would feed garbage to its decoder.
        if waitingForSyncFrame {
            guard isKeyframe else {
                droppedFrames += 1
                return
            }
            waitingForSyncFrame = false
            debugLog("First keyframe sent to new client")
        }

        // No frame-age dropping or backpressure — send everything immediately.
        // The encode queue depth limit (2 pending) in ScreenCapture handles flow control.
        frameQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.connection === connection, !self.isStopped, self.connectionReady else { return }

            let packet = self.makeFramePacket(data, timestamp: timestamp, isKeyframe: isKeyframe)

            connection.send(content: packet, completion: .contentProcessed { error in
                if error != nil {
                    self.droppedFrames += 1
                }
            })

            // Track frame age at send time for pipeline profiling
            let sendAge = DispatchTime.now().uptimeNanoseconds - timestamp
            self.updateStats(bytes: data.count, frameAgeNs: sendAge)
        }
    }

    private func makeFramePacket(_ data: Data, timestamp: UInt64, isKeyframe: Bool) -> Data {
        if clientSupportsFrameMetadata {
            var packet = Data(capacity: data.count + 14)
            packet.append(WireMessage.videoFrameWithMetadata)
            appendFrameSize(data.count, to: &packet)
            packet.append(isKeyframe ? 1 : 0)
            var captureTimestamp = timestamp.bigEndian
            withUnsafeBytes(of: &captureTimestamp) { packet.append(contentsOf: $0) }
            packet.append(data)
            return packet
        }

        // Keep legacy frame type 0 for clients that do not advertise
        // metadata support; remove after legacy clients age out.
        var packet = Data(capacity: data.count + 5)
        packet.append(WireMessage.legacyVideoFrame)
        appendFrameSize(data.count, to: &packet)
        packet.append(data)
        return packet
    }

    private func appendFrameSize(_ size: Int, to packet: inout Data) {
        var frameSize = Int32(size).bigEndian
        withUnsafeBytes(of: &frameSize) { packet.append(contentsOf: $0) }
    }

    // Pipeline profiling: track frame age at send time
    private var totalFrameAgeNs: UInt64 = 0
    private var profiledFrameCount: UInt64 = 0

    private func updateStats(bytes: Int, frameAgeNs: UInt64 = 0) {
        bytesSent += UInt64(bytes)
        frameCount += 1
        if frameAgeNs > 0 {
            totalFrameAgeNs += frameAgeNs
            profiledFrameCount += 1
        }

        let now = DispatchTime.now()
        let elapsed = Double(now.uptimeNanoseconds - lastStatsTime.uptimeNanoseconds) / 1_000_000_000

        if elapsed >= 1.0 {
            let mbps = Double(bytesSent * 8) / elapsed / 1_000_000
            let fps = Double(frameCount) / elapsed
            onStats?(fps, mbps)

            // Log pipeline latency profile
            if profiledFrameCount > 0 {
                let avgAgeMs = Double(totalFrameAgeNs) / Double(profiledFrameCount) / 1_000_000.0
                debugLog("Pipeline: \(String(format: "%.1f", fps))fps, \(String(format: "%.1f", mbps))Mbps, avg frame age: \(String(format: "%.1f", avgAgeMs))ms, dropped: \(droppedFrames)")
            }

            bytesSent = 0
            frameCount = 0
            droppedFrames = 0
            totalFrameAgeNs = 0
            profiledFrameCount = 0
            lastStatsTime = now
        }
    }

    func stop() {
        isStopped = true
        isReceiving = false

        // Wait for pending operations before cancelling
        frameQueue.sync {}
        receiveQueue.sync {}

        connection?.cancel()
        listener?.cancel()
        connection = nil
        listener = nil
    }

    func dropActiveConnection(reason: String) {
        debugLog("Dropping active stream connection: \(reason)")
        isReceiving = false
        connection?.cancel()
        connection = nil
        connectionReady = false
    }
}
