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
        let settings = RemoteSessionSettings()

        settings.applyStreamingProfile(.lowBandwidth)

        XCTAssertEqual(settings.streamingProfile, .lowBandwidth)
        XCTAssertEqual(settings.refreshRate, 30)
        XCTAssertEqual(settings.bitrate, 60)
        XCTAssertEqual(settings.quality, "low")
        XCTAssertFalse(settings.gamingBoost)
    }

    func testQualityProfileAppliesSharpDailySettings() {
        let settings = RemoteSessionSettings()

        settings.applyStreamingProfile(.quality)

        XCTAssertEqual(settings.streamingProfile, .quality)
        XCTAssertEqual(settings.refreshRate, 60)
        XCTAssertEqual(settings.bitrate, 800)
        XCTAssertEqual(settings.quality, "high")
        XCTAssertFalse(settings.gamingBoost)
    }

    func testResetUsesBalancedDailyRefreshRate() {
        let settings = RemoteSessionSettings()

        settings.refreshRate = 120
        settings.resetToDefaults()

        XCTAssertEqual(settings.refreshRate, 60)
    }

    func testManualChangeMarksProfileAsCustom() {
        let settings = RemoteSessionSettings()

        settings.applyStreamingProfile(.productivity)
        settings.bitrate = 800

        XCTAssertEqual(settings.streamingProfile, .custom)
        XCTAssertEqual(settings.bitrate, 800)
    }

    func testGamingBoostEffectiveBitrateMatchesEncoderCap() {
        let settings = RemoteSessionSettings()

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
