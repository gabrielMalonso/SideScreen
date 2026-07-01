import CoreGraphics
import Foundation

enum DisplaySourceMode: String, Codable, CaseIterable {
    case remoteDesktop
    case extendedDisplay

    var title: String {
        switch self {
        case .remoteDesktop: return "Remote Desktop"
        case .extendedDisplay: return "Extended Display"
        }
    }
}

struct ExistingDisplaySource: Equatable {
    let displayID: CGDirectDisplayID
    let name: String
    let bounds: CGRect
    let physicalWidth: Int
    let physicalHeight: Int
    let scale: CGFloat
    let isMain: Bool

    init(
        displayID: CGDirectDisplayID,
        name: String,
        bounds: CGRect,
        physicalWidth: Int,
        physicalHeight: Int,
        scale: CGFloat,
        isMain: Bool
    ) {
        self.displayID = displayID
        self.name = name
        self.bounds = bounds
        self.physicalWidth = max(physicalWidth, 1)
        self.physicalHeight = max(physicalHeight, 1)
        self.scale = max(scale, 1)
        self.isMain = isMain
    }

    static func main() -> ExistingDisplaySource {
        make(displayID: CGMainDisplayID(), name: "Main Display", isMain: true)
    }

    static func make(displayID: CGDirectDisplayID, name: String? = nil, isMain: Bool? = nil) -> ExistingDisplaySource {
        let bounds = CGDisplayBounds(displayID)
        let physical = ScreenCapture.physicalSize(for: displayID)
        let scaleX = bounds.width > 0 ? CGFloat(physical.width) / bounds.width : 1
        let scaleY = bounds.height > 0 ? CGFloat(physical.height) / bounds.height : scaleX
        let scale = max(scaleX, scaleY, 1)
        let mainDisplay = CGMainDisplayID()
        return ExistingDisplaySource(
            displayID: displayID,
            name: name ?? (displayID == mainDisplay ? "Main Display" : "Display \(displayID)"),
            bounds: bounds,
            physicalWidth: physical.width,
            physicalHeight: physical.height,
            scale: scale,
            isMain: isMain ?? (displayID == mainDisplay)
        )
    }
}

struct VirtualDisplaySource: Equatable {
    let displayID: CGDirectDisplayID
    let requestedWidth: Int
    let requestedHeight: Int
    let hiDPI: Bool
    let refreshRate: Int

    var requestedSize: (width: Int, height: Int) {
        (requestedWidth, requestedHeight)
    }
}

enum DisplaySource: Equatable {
    case existing(ExistingDisplaySource)
    case virtual(VirtualDisplaySource)

    var displayID: CGDirectDisplayID {
        switch self {
        case .existing(let source): return source.displayID
        case .virtual(let source): return source.displayID
        }
    }

    var isVirtual: Bool {
        if case .virtual = self { return true }
        return false
    }

    var diagnosticKind: String {
        switch self {
        case .existing: return "existingDisplay"
        case .virtual: return "virtualDisplay"
        }
    }

    var title: String {
        switch self {
        case .existing(let source): return source.name
        case .virtual: return "Virtual Display"
        }
    }

    var hevcDisplayConfigSize: (width: Int, height: Int) {
        switch self {
        case .existing(let source):
            return (source.physicalWidth, source.physicalHeight)
        case .virtual(let source):
            return source.requestedSize
        }
    }
}
