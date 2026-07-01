import Foundation

struct InputIngressDiagnostics {
    let pressedKeyCount: Int
    let pressedButtonCount: Int
    let releaseAllCount: UInt64
    let droppedStaleCount: UInt64
    let sequenceGapCount: UInt64
    let coalescedPointerMoves: UInt64
    let lastReleaseReason: String
}

private enum InputIngressDownstreamOperation {
    case event(RemoteInputEvent)
    case releaseAll(String)
}

final class InputIngress: InputBackend {
    private let downstream: InputBackend
    private let onDiagnosticsChanged: ((InputIngressDiagnostics) -> Void)?
    private let lock = NSLock()
    private var activeDeviceId: String?
    private var lastSequence: UInt64?
    private var pressedKeys = Set<UInt32>()
    private var pressedButtons = Set<UInt8>()
    private var pendingPointerRelative: PointerRelativeEvent?
    private var coalescedPointerMoves: UInt64 = 0
    private var releaseAllCount: UInt64 = 0
    private var droppedStaleCount: UInt64 = 0
    private var sequenceGapCount: UInt64 = 0
    private var lastReleaseReason = "None"
    private var watchdog: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "inputIngressWatchdogQueue", qos: .userInteractive)

    init(downstream: InputBackend, onDiagnosticsChanged: ((InputIngressDiagnostics) -> Void)? = nil) {
        self.downstream = downstream
        self.onDiagnosticsChanged = onDiagnosticsChanged
    }

    func beginSession(deviceId: String) {
        lock.lock()
        activeDeviceId = deviceId
        lastSequence = nil
        pressedKeys.removeAll()
        pressedButtons.removeAll()
        pendingPointerRelative = nil
        coalescedPointerMoves = 0
        releaseAllCount = 0
        droppedStaleCount = 0
        sequenceGapCount = 0
        lastReleaseReason = "None"
        armWatchdogLocked()
        emitDiagnosticsLocked()
        lock.unlock()

        downstream.beginSession(deviceId: deviceId)
        debugLog("InputIngress session started — device=\(deviceId)")
    }

    func handle(_ event: RemoteInputEvent) {
        var downstreamOperations: [InputIngressDownstreamOperation] = []

        lock.lock()
        armWatchdogLocked()
        let validation = validateSequenceLocked(event)
        if !validation.shouldProcess {
            lock.unlock()
            return
        }
        if let releaseReason = validation.releaseReason {
            if let pending = takePendingPointerRelativeLocked() {
                downstreamOperations.append(.event(pending))
            }
            pressedKeys.removeAll()
            pressedButtons.removeAll()
            releaseAllCount += 1
            lastReleaseReason = releaseReason
            emitDiagnosticsLocked()
            downstreamOperations.append(.releaseAll(releaseReason))
        }

        switch event {
        case .pointerRelative(let move):
            enqueuePointerRelativeLocked(move)
            lock.unlock()
        case .textCommit:
            if let pending = takePendingPointerRelativeLocked() {
                downstreamOperations.append(.event(pending))
            }
            lock.unlock()
            downstreamOperations.append(.event(event))
        case .keyboard(let key):
            if let pending = takePendingPointerRelativeLocked() {
                downstreamOperations.append(.event(pending))
            }
            updateKeyboardStateLocked(key)
            emitDiagnosticsLocked()
            lock.unlock()
            downstreamOperations.append(.event(event))
        case .pointerButton(let button):
            if let pending = takePendingPointerRelativeLocked() {
                downstreamOperations.append(.event(pending))
            }
            updateButtonStateLocked(button)
            emitDiagnosticsLocked()
            lock.unlock()
            downstreamOperations.append(.event(event))
        case .pointerWheel:
            if let pending = takePendingPointerRelativeLocked() {
                downstreamOperations.append(.event(pending))
            }
            lock.unlock()
            downstreamOperations.append(.event(event))
        case .allInputsUp(let allUp):
            if let pending = takePendingPointerRelativeLocked() {
                downstreamOperations.append(.event(pending))
            }
            pressedKeys.removeAll()
            pressedButtons.removeAll()
            releaseAllCount += 1
            lastReleaseReason = "client all-inputs-up: \(allUp.diagnosticReason)"
            emitDiagnosticsLocked()
            lock.unlock()
            downstreamOperations.append(.event(event))
        case .ping, .pong:
            if let pending = takePendingPointerRelativeLocked() {
                downstreamOperations.append(.event(pending))
            }
            lock.unlock()
            downstreamOperations.append(.event(event))
        }

        for operation in downstreamOperations {
            switch operation {
            case .event(let forwarded):
                downstream.handle(forwarded)
            case .releaseAll(let reason):
                downstream.releaseAll(reason: reason)
            }
        }
    }

    func releaseAll(reason: String) {
        var pendingEvent: RemoteInputEvent?
        lock.lock()
        pendingEvent = takePendingPointerRelativeLocked()
        pressedKeys.removeAll()
        pressedButtons.removeAll()
        releaseAllCount += 1
        lastReleaseReason = reason
        emitDiagnosticsLocked()
        lock.unlock()
        if let pendingEvent {
            downstream.handle(pendingEvent)
        }
        downstream.releaseAll(reason: reason)
    }

    func endSession(reason: String) {
        var pendingEvent: RemoteInputEvent?
        lock.lock()
        watchdog?.cancel()
        watchdog = nil
        pendingEvent = takePendingPointerRelativeLocked()
        pressedKeys.removeAll()
        pressedButtons.removeAll()
        releaseAllCount += 1
        lastReleaseReason = reason
        let coalesced = coalescedPointerMoves
        activeDeviceId = nil
        lastSequence = nil
        coalescedPointerMoves = 0
        emitDiagnosticsLocked()
        lock.unlock()

        if let pendingEvent {
            downstream.handle(pendingEvent)
        }
        downstream.endSession(reason: reason)

        if coalesced > 0 {
            debugLog("InputIngress session ended — coalesced pointer moves=\(coalesced)")
        }
    }

    private func validateSequenceLocked(_ event: RemoteInputEvent) -> (shouldProcess: Bool, releaseReason: String?) {
        let sequence = event.sequence
        defer { lastSequence = max(lastSequence ?? 0, sequence) }

        guard let previous = lastSequence else { return (true, nil) }
        if sequence <= previous {
            if case .allInputsUp = event {
                debugLog("InputIngress processing stale all-inputs-up seq=\(sequence), last=\(previous)")
                return (true, nil)
            }
            droppedStaleCount += 1
            emitDiagnosticsLocked()
            debugLog("InputIngress dropped stale input seq=\(sequence), last=\(previous)")
            return (false, nil)
        }
        if sequence > previous + 1 {
            sequenceGapCount += 1
            let reason = "sequence gap: last=\(previous), next=\(sequence)"
            debugLog("InputIngress \(reason)")
            if !pressedKeys.isEmpty || !pressedButtons.isEmpty {
                return (true, reason)
            }
        }
        return (true, nil)
    }

    private func enqueuePointerRelativeLocked(_ move: PointerRelativeEvent) {
        if let pending = pendingPointerRelative {
            pendingPointerRelative = PointerRelativeEvent(
                dx: pending.dx + move.dx,
                dy: pending.dy + move.dy,
                unit: pending.unit,
                flags: pending.flags | move.flags,
                sequence: move.sequence
            )
            coalescedPointerMoves += 1
            emitDiagnosticsLocked()
        } else {
            pendingPointerRelative = move
            schedulePointerFlush()
        }
    }

    private func takePendingPointerRelativeLocked() -> RemoteInputEvent? {
        guard let pending = pendingPointerRelative else { return nil }
        pendingPointerRelative = nil
        return .pointerRelative(pending)
    }

    private func schedulePointerFlush() {
        watchdogQueue.asyncAfter(deadline: .now() + .milliseconds(4)) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let pending = self.takePendingPointerRelativeLocked()
            self.lock.unlock()
            if let pending {
                self.downstream.handle(pending)
            }
        }
    }

    private func updateKeyboardStateLocked(_ key: KeyboardKeyEvent) {
        let identity = UInt32(key.usagePage) << 16 | UInt32(key.usageId)
        if key.action == .down {
            pressedKeys.insert(identity)
        } else {
            pressedKeys.remove(identity)
        }
    }

    private func updateButtonStateLocked(_ button: PointerButtonEvent) {
        if button.action == .down {
            pressedButtons.insert(button.button)
        } else {
            pressedButtons.remove(button.button)
        }
    }

    private func armWatchdogLocked() {
        watchdog?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.releaseAll(reason: "input idle watchdog")
        }
        watchdog = timer
        timer.resume()
    }

    private func emitDiagnosticsLocked() {
        onDiagnosticsChanged?(InputIngressDiagnostics(
            pressedKeyCount: pressedKeys.count,
            pressedButtonCount: pressedButtons.count,
            releaseAllCount: releaseAllCount,
            droppedStaleCount: droppedStaleCount,
            sequenceGapCount: sequenceGapCount,
            coalescedPointerMoves: coalescedPointerMoves,
            lastReleaseReason: lastReleaseReason
        ))
    }
}
