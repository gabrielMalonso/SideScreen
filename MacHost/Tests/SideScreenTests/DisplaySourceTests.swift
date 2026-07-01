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
        XCTAssertNil(settings.selectedRemoteDisplayID)
    }

    func testSelectedRemoteDisplayPersistsAndResets() {
        let settings = DisplaySettings()
        settings.selectedRemoteDisplayID = 77

        XCTAssertEqual(DisplaySettings().selectedRemoteDisplayID, 77)

        settings.resetToDefaults()

        XCTAssertNil(DisplaySettings().selectedRemoteDisplayID)
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

    func testCatalogPrefersSelectedDisplayWhenAvailable() {
        let main = ExistingDisplaySource(
            displayID: 1,
            name: "Main",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            physicalWidth: 1920,
            physicalHeight: 1080,
            scale: 1,
            isMain: true
        )
        let side = ExistingDisplaySource(
            displayID: 2,
            name: "Side",
            bounds: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
            physicalWidth: 2560,
            physicalHeight: 1440,
            scale: 1,
            isMain: false
        )
        let catalog = DisplaySourceCatalog(listDisplays: { [main, side] })

        XCTAssertEqual(catalog.source(preferredID: 2), side)
    }

    func testCatalogFallsBackToMainDisplayWhenSelectionIsMissing() {
        let main = ExistingDisplaySource(
            displayID: 1,
            name: "Main",
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            physicalWidth: 1920,
            physicalHeight: 1080,
            scale: 1,
            isMain: true
        )
        let side = ExistingDisplaySource(
            displayID: 2,
            name: "Side",
            bounds: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
            physicalWidth: 2560,
            physicalHeight: 1440,
            scale: 1,
            isMain: false
        )
        let catalog = DisplaySourceCatalog(listDisplays: { [side, main] })

        XCTAssertEqual(catalog.source(preferredID: 404), main)
    }

    func testDisplayControlCodecRoundTripsDisplayList() throws {
        let display = ExistingDisplaySource(
            displayID: 9,
            name: "Studio Display",
            bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            physicalWidth: 5120,
            physicalHeight: 2880,
            scale: 2,
            isMain: true
        )
        let envelope = DisplayControlEnvelope.displayList(selectedDisplayId: 9, displays: [display])

        let decoded = try DisplayControlCodec.decode(try DisplayControlCodec.encode(envelope))

        XCTAssertEqual(decoded, envelope)
    }

    func testDisplayControlCodecRejectsInvalidSelectDisplay() {
        let envelope = DisplayControlEnvelope(
            type: .selectDisplay,
            selectedDisplayId: nil,
            displays: nil,
            displayId: nil,
            status: nil,
            message: nil
        )

        XCTAssertThrowsError(try DisplayControlCodec.encode(envelope))
    }

    private func clearSideScreenDefaults() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("SideScreen_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
