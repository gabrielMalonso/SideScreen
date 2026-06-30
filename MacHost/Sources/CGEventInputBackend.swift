import ApplicationServices
import Foundation

protocol InputBackend: AnyObject {
    func beginSession(deviceId: String)
    func handle(_ event: RemoteInputEvent)
    func releaseAll(reason: String)
    func endSession(reason: String)
}

extension InputBackend {
    func beginSession(deviceId: String) {}
    func endSession(reason: String) {
        releaseAll(reason: reason)
    }
}

final class CGEventInputBackend: InputBackend {
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private var pressedKeys = Set<UInt32>()
    private var pressedButtons = Set<UInt8>()

    func handle(_ event: RemoteInputEvent) {
        switch event {
        case .keyboard(let key):
            handleKeyboard(key)
        case .pointerRelative(let pointer):
            handlePointerRelative(pointer)
        case .pointerButton(let button):
            handlePointerButton(button)
        case .pointerWheel(let wheel):
            handlePointerWheel(wheel)
        case .allInputsUp:
            releaseAll(reason: "client all-inputs-up")
        case .ping:
            break
        }
    }

    func releaseAll(reason: String) {
        if !pressedKeys.isEmpty || !pressedButtons.isEmpty {
            debugLog("Input release-all: \(reason), keys=\(pressedKeys.count), buttons=\(pressedButtons.count)")
        }
        for identity in pressedKeys {
            let usageId = UInt16(identity & 0xFFFF)
            if let keyCode = Self.cgKeyCodeForKeyboardUsage(usageId) {
                CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)?
                    .post(tap: .cghidEventTap)
            }
        }
        pressedKeys.removeAll()

        let location = currentPointerLocation()
        for button in pressedButtons {
            postMouseButton(button, down: false, at: location)
        }
        pressedButtons.removeAll()
    }

    private func handleKeyboard(_ key: KeyboardKeyEvent) {
        guard key.usagePage == 0x07,
              let keyCode = Self.cgKeyCodeForKeyboardUsage(key.usageId) else {
            debugLog("Input keyboard ignored: usagePage=\(key.usagePage), usageId=\(key.usageId), androidKeyCode=\(key.androidKeyCode)")
            return
        }

        let identity = UInt32(key.usagePage) << 16 | UInt32(key.usageId)
        let isDown = key.action == .down
        if isDown {
            pressedKeys.insert(identity)
        } else {
            pressedKeys.remove(identity)
        }

        CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: isDown)?
            .post(tap: .cghidEventTap)
    }

    private func handlePointerRelative(_ pointer: PointerRelativeEvent) {
        let current = currentPointerLocation()
        let target = CGPoint(
            x: current.x + CGFloat(pointer.dx),
            y: current.y + CGFloat(pointer.dy)
        )
        let type: CGEventType
        let button: CGMouseButton
        if pressedButtons.contains(0) {
            type = .leftMouseDragged
            button = .left
        } else if pressedButtons.contains(1) {
            type = .rightMouseDragged
            button = .right
        } else {
            type = .mouseMoved
            button = .left
        }
        CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: target, mouseButton: button)?
            .post(tap: .cghidEventTap)
    }

    private func handlePointerButton(_ button: PointerButtonEvent) {
        let location = currentPointerLocation()
        if button.action == .down {
            pressedButtons.insert(button.button)
        } else {
            pressedButtons.remove(button.button)
        }
        postMouseButton(button.button, down: button.action == .down, at: location)
    }

    private func handlePointerWheel(_ wheel: PointerWheelEvent) {
        let vertical = Int32((-wheel.deltaY).rounded())
        let horizontal = Int32((-wheel.deltaX).rounded())
        CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        )?.post(tap: .cghidEventTap)
    }

    private func postMouseButton(_ button: UInt8, down: Bool, at location: CGPoint) {
        let eventType: CGEventType
        let mouseButton: CGMouseButton
        switch button {
        case 1:
            eventType = down ? .rightMouseDown : .rightMouseUp
            mouseButton = .right
        case 2:
            eventType = down ? .otherMouseDown : .otherMouseUp
            mouseButton = .center
        default:
            eventType = down ? .leftMouseDown : .leftMouseUp
            mouseButton = .left
        }
        CGEvent(mouseEventSource: eventSource, mouseType: eventType, mouseCursorPosition: location, mouseButton: mouseButton)?
            .post(tap: .cghidEventTap)
    }

    private func currentPointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private static func cgKeyCodeForKeyboardUsage(_ usageId: UInt16) -> CGKeyCode? {
        keyboardUsageMap[usageId]
    }

    private static let keyboardUsageMap: [UInt16: CGKeyCode] = [
        0x04: 0, 0x05: 11, 0x06: 8, 0x07: 2, 0x08: 14, 0x09: 3, 0x0A: 5,
        0x0B: 4, 0x0C: 34, 0x0D: 38, 0x0E: 40, 0x0F: 37, 0x10: 46, 0x11: 45,
        0x12: 31, 0x13: 35, 0x14: 12, 0x15: 15, 0x16: 1, 0x17: 17, 0x18: 32,
        0x19: 9, 0x1A: 13, 0x1B: 7, 0x1C: 16, 0x1D: 6,
        0x1E: 18, 0x1F: 19, 0x20: 20, 0x21: 21, 0x22: 23, 0x23: 22, 0x24: 26,
        0x25: 28, 0x26: 25, 0x27: 29,
        0x28: 36, 0x29: 53, 0x2A: 51, 0x2B: 48, 0x2C: 49, 0x2D: 27, 0x2E: 24,
        0x2F: 33, 0x30: 30, 0x31: 42, 0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43,
        0x37: 47, 0x38: 44, 0x39: 57,
        0x3A: 122, 0x3B: 120, 0x3C: 99, 0x3D: 118, 0x3E: 96, 0x3F: 97,
        0x40: 98, 0x41: 100, 0x42: 101, 0x43: 109, 0x44: 103, 0x45: 111,
        0x4A: 115, 0x4B: 116, 0x4C: 117, 0x4D: 119, 0x4E: 121,
        0x4F: 124, 0x50: 123, 0x51: 125, 0x52: 126,
        0x54: 75, 0x55: 67, 0x56: 78, 0x57: 69, 0x58: 76, 0x59: 83, 0x5A: 84,
        0x5B: 85, 0x5C: 86, 0x5D: 87, 0x5E: 88, 0x5F: 89, 0x60: 91, 0x61: 92,
        0x62: 82, 0x63: 65,
        0xE0: 59, 0xE1: 56, 0xE2: 58, 0xE3: 55,
        0xE4: 62, 0xE5: 60, 0xE6: 61, 0xE7: 54
    ]
}
