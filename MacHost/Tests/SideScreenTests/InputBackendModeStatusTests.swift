import XCTest
@testable import SideScreen

final class InputBackendModeStatusTests: XCTestCase {
    func testHelperReadinessDoesNotRequireUserReadableKarabinerSocket() {
        let status = KarabinerVirtualHIDStatus(
            managerInstalled: true,
            daemonInstalled: true,
            daemonRunning: true,
            socketAvailable: false,
            helperBinaryInstalled: true,
            helperLaunchDaemonInstalled: true,
            helperSocketAvailable: true,
            directProbeSucceeded: false,
            helperStatus: SideScreenVirtualHIDHelperStatus(
                helperProtocolVersion: SideScreenVirtualHIDHelperCodec.version,
                helperBuildVersion: SideScreenVirtualHIDHelperCodec.helperBuildVersion,
                karabinerClientProtocolVersion: 6,
                upstreamAvailable: true
            ),
            probeFailure: nil
        )

        XCTAssertTrue(status.canUseThroughHelper)
        XCTAssertEqual(status.title, "Ready via helper")
        XCTAssertEqual(status.fallbackReason, "")
    }
}
