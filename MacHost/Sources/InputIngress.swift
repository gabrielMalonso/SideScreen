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
        lock.lock()
        armWatchdogLocked()
        let shouldProcess = validateSequenceLocked(event)
        if !shouldProcess {
            lock.unlock()
            return
        }

        switch event {
        case .pointerRelative(let move):
            enqueuePointerRelativeLocked(move)
            lock.unlock()
        case .keyboard(let key):
            flushPendingPointerRelativeLocked()
            updateKeyboardStateLocked(key)
            emitDiagnosticsLocked()
            lock.unlock()
            downstream.handle(event)
        case .pointerButton(let button):
            flushPendingPointerRelativeLocked()
            updateButtonStateLocked(button)
            emitDiagnosticsLocked()
            lock.unlock()
            downstream.handle(event)
        case .pointerWheel:
            flushPendingPointerRelativeLocked()
            lock.unlock()
            downstream.handle(event)
        case .allInputsUp:
            flushPendingPointerRelativeLocked()
            pressedKeys.removeAll()
            pressedButtons.removeAll()
            emitDiagnosticsLocked()
            lock.unlock()
            downstream.handle(event)
        case .ping:
            flushPendingPointerRelativeLocked()
            lock.unlock()
            downstream.handle(event)
        }
    }

    func releaseAll(reason: String) {
        lock.lock()
        flushPendingPointerRelativeLocked()
        pressedKeys.removeAll()
        pressedButtons.removeAll()
        releaseAllCount += 1
        lastReleaseReason = reason
        emitDiagnosticsLocked()
        lock.unlock()
        downstream.releaseAll(reason: reason)
    }

    func endSession(reason: String) {
        lock.lock()
        watchdog?.cancel()
        watchdog = nil
        flushPendingPointerRelativeLocked()
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

        downstream.releaseAll(reason: reason)

        if coalesced > 0 {
            debugLog("InputIngress session ended — coalesced pointer moves=\(coalesced)")
        }
    }

    private func validateSequenceLocked(_ event: RemoteInputEvent) -> Bool {
        let sequence = event.sequence
        defer { lastSequence = max(lastSequence ?? 0, sequence) }

        guard let previous = lastSequence else { return true }
        if sequence <= previous {
            if case .allInputsUp = event {
                debugLog("InputIngress processing stale all-inputs-up seq=\(sequence), last=\(previous)")
                return true
            }
            droppedStaleCount += 1
            emitDiagnosticsLocked()
            debugLog("InputIngress dropped stale input seq=\(sequence), last=\(previous)")
            return false
        }
        if sequence > previous + 1 {
            sequenceGapCount += 1
            debugLog("InputIngress sequence gap: last=\(previous), next=\(sequence)")
        }
        return true
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

    private func flushPendingPointerRelativeLocked() {
        guard let pending = pendingPointerRelative else { return }
        pendingPointerRelative = nil
        downstream.handle(.pointerRelative(pending))
    }

    private func schedulePointerFlush() {
        watchdogQueue.asyncAfter(deadline: .now() + .milliseconds(4)) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.flushPendingPointerRelativeLocked()
            self.lock.unlock()
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
