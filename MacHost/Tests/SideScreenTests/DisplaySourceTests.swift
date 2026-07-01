import CoreGraphics
import XCTest
@testable import SideScreen

final class DisplaySourceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearSideScreenDefaults()
    }

    override func tearDown() {
        clearSideScreenDefaults()
        super.tearDown()
    }

    func testSettingsDefaultToRemoteDesktopMode() {
        let settings = DisplaySettings()

        XCTAssertEqual(settings.displaySourceMode, .remoteDesktop)
    }

    func testExistingDisplaySourceCannotAlsoOwnVirtualDisplay() {
        let existing = ExistingDisplaySource(
            displayID: 42,
            name: "Main Display",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            physicalWidth: 3840,
            physicalHeight: 2160,
            scale: 2,
            isMain: true
        )
        let source = DisplaySource.existing(existing)

        XCTAssertFalse(source.isVirtual)
        XCTAssertEqual(source.displayID, 42)
        XCTAssertEqual(source.diagnosticKind, "existingDisplay")
        XCTAssertEqual(source.hevcDisplayConfigSize.width, 3840)
        XCTAssertEqual(source.hevcDisplayConfigSize.height, 2160)
    }

    func testVirtualDisplaySourceKeepsRequestedDisplayConfigSize() {
        let virtual = VirtualDisplaySource(
            displayID: 99,
            requestedWidth: 1920,
            requestedHeight: 1200,
            hiDPI: true,
            refreshRate: 60
        )
        let source = DisplaySource.virtual(virtual)

        XCTAssertTrue(source.isVirtual)
        XCTAssertEqual(source.displayID, 99)
        XCTAssertEqual(source.diagnosticKind, "virtualDisplay")
        XCTAssertEqual(source.hevcDisplayConfigSize.width, 1920)
        XCTAssertEqual(source.hevcDisplayConfigSize.height, 1200)
    }

    private func clearSideScreenDefaults() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("SideScreen_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
