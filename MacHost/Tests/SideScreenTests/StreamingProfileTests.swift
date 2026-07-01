import XCTest
@testable import SideScreen

final class StreamingProfileTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearSideScreenDefaults()
    }

    override func tearDown() {
        clearSideScreenDefaults()
        super.tearDown()
    }

    func testLowBandwidthProfileAppliesConcreteStreamingSettings() {
        let settings = DisplaySettings()

        settings.applyStreamingProfile(.lowBandwidth)

        XCTAssertEqual(settings.streamingProfile, .lowBandwidth)
        XCTAssertEqual(settings.resolution, "1280x800")
        XCTAssertEqual(settings.refreshRate, 30)
        XCTAssertEqual(settings.bitrate, 60)
        XCTAssertEqual(settings.quality, "low")
        XCTAssertFalse(settings.hiDPI)
        XCTAssertFalse(settings.gamingBoost)
    }

    func testManualChangeMarksProfileAsCustom() {
        let settings = DisplaySettings()

        settings.applyStreamingProfile(.productivity)
        settings.bitrate = 800

        XCTAssertEqual(settings.streamingProfile, .custom)
        XCTAssertEqual(settings.bitrate, 800)
    }

    func testGamingBoostEffectiveBitrateMatchesEncoderCap() {
        let settings = DisplaySettings()

        settings.gamingBoost = true

        XCTAssertEqual(settings.effectiveBitrate, 50)
        XCTAssertEqual(settings.effectiveQuality, "ultralow")
        XCTAssertEqual(settings.effectiveRefreshRate, 120)
    }

    private func clearSideScreenDefaults() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("SideScreen_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
