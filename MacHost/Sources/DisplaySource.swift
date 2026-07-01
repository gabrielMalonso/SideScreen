import AppKit
import CoreGraphics
import Foundation

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

struct DisplaySourceCatalog {
    private let listDisplays: () -> [ExistingDisplaySource]

    init(listDisplays: @escaping () -> [ExistingDisplaySource] = DisplaySourceCatalog.onlineDisplays) {
        self.listDisplays = listDisplays
    }

    func displays() -> [ExistingDisplaySource] {
        let sources = listDisplays()
            .filter { $0.physicalWidth > 0 && $0.physicalHeight > 0 }
            .sorted { lhs, rhs in
                if lhs.isMain != rhs.isMain { return lhs.isMain }
                if lhs.bounds.minY != rhs.bounds.minY { return lhs.bounds.minY < rhs.bounds.minY }
                if lhs.bounds.minX != rhs.bounds.minX { return lhs.bounds.minX < rhs.bounds.minX }
                return lhs.displayID < rhs.displayID
            }
        return sources.isEmpty ? [.main()] : sources
    }

    func source(preferredID: CGDirectDisplayID?) -> ExistingDisplaySource {
        let available = displays()
        if let preferredID, let match = available.first(where: { $0.displayID == preferredID }) {
            return match
        }
        if let main = available.first(where: \.isMain) {
            return main
        }
        return available[0]
    }

    func contains(displayID: CGDirectDisplayID) -> Bool {
        displays().contains { $0.displayID == displayID }
    }

    static func onlineDisplays() -> [ExistingDisplaySource] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return [.main()]
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displayIDs, &count) == .success else {
            return [.main()]
        }

        return displayIDs.prefix(Int(count)).map { displayID in
            ExistingDisplaySource.make(
                displayID: displayID,
                name: name(for: displayID),
                isMain: displayID == CGMainDisplayID()
            )
        }
    }

    private static func name(for displayID: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == displayID
        }) {
            return screen.localizedName
        }
        return displayID == CGMainDisplayID() ? "Main Display" : "Display \(displayID)"
    }
}

enum DisplaySource: Equatable {
    case existing(ExistingDisplaySource)

    var displayID: CGDirectDisplayID {
        switch self {
        case .existing(let source): return source.displayID
        }
    }

    var diagnosticKind: String {
        "existingDisplay"
    }

    var title: String {
        switch self {
        case .existing(let source): return source.name
        }
    }

    var hevcDisplayConfigSize: (width: Int, height: Int) {
        switch self {
        case .existing(let source):
            return (source.physicalWidth, source.physicalHeight)
        }
    }
}

struct DisplayControlDisplay: Codable, Equatable {
    let id: UInt32
    let name: String
    let isMain: Bool
    let width: Int
    let height: Int
    let scale: Double

    init(source: ExistingDisplaySource) {
        self.id = source.displayID
        self.name = source.name
        self.isMain = source.isMain
        self.width = source.physicalWidth
        self.height = source.physicalHeight
        self.scale = Double(source.scale)
    }
}

struct DisplayControlEnvelope: Codable, Equatable {
    enum MessageType: String, Codable {
        case requestDisplayList
        case displayList
        case selectDisplay
        case selectDisplayResult
    }

    let type: MessageType
    let selectedDisplayId: UInt32?
    let displays: [DisplayControlDisplay]?
    let displayId: UInt32?
    let status: String?
    let message: String?

    static func requestDisplayList() -> DisplayControlEnvelope {
        DisplayControlEnvelope(
            type: .requestDisplayList,
            selectedDisplayId: nil,
            displays: nil,
            displayId: nil,
            status: nil,
            message: nil
        )
    }

    static func displayList(selectedDisplayId: UInt32, displays: [ExistingDisplaySource]) -> DisplayControlEnvelope {
        DisplayControlEnvelope(
            type: .displayList,
            selectedDisplayId: selectedDisplayId,
            displays: displays.map(DisplayControlDisplay.init),
            displayId: nil,
            status: nil,
            message: nil
        )
    }

    static func selectDisplay(_ displayId: UInt32) -> DisplayControlEnvelope {
        DisplayControlEnvelope(
            type: .selectDisplay,
            selectedDisplayId: nil,
            displays: nil,
            displayId: displayId,
            status: nil,
            message: nil
        )
    }

    static func selectDisplayResult(displayId: UInt32, status: String, message: String? = nil) -> DisplayControlEnvelope {
        DisplayControlEnvelope(
            type: .selectDisplayResult,
            selectedDisplayId: nil,
            displays: nil,
            displayId: displayId,
            status: status,
            message: message
        )
    }

    func validated() throws -> DisplayControlEnvelope {
        switch type {
        case .requestDisplayList:
            return self
        case .displayList:
            guard selectedDisplayId != nil, let displays, !displays.isEmpty else {
                throw DisplayControlCodecError.invalidEnvelope
            }
        case .selectDisplay:
            guard displayId != nil else {
                throw DisplayControlCodecError.invalidEnvelope
            }
        case .selectDisplayResult:
            guard displayId != nil, status == "ok" || status == "error" else {
                throw DisplayControlCodecError.invalidEnvelope
            }
        }
        return self
    }
}

enum DisplayControlCodecError: Error, Equatable {
    case invalidEnvelope
    case payloadTooLarge
}

enum DisplayControlCodec {
    static let maxPayloadBytes = 64 * 1024

    static func encode(_ envelope: DisplayControlEnvelope) throws -> Data {
        _ = try envelope.validated()
        let data = try JSONEncoder().encode(envelope)
        guard data.count <= maxPayloadBytes else { throw DisplayControlCodecError.payloadTooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> DisplayControlEnvelope {
        guard data.count <= maxPayloadBytes else { throw DisplayControlCodecError.payloadTooLarge }
        return try JSONDecoder().decode(DisplayControlEnvelope.self, from: data).validated()
    }
}
