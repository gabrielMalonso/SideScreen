import XCTest
@testable import SideScreen

final class KarabinerVirtualHIDBackendTests: XCTestCase {
    func testKeyboardParametersMatchKarabinerLayout() {
        let bytes = KarabinerVirtualHIDReportCodec.keyboardParameters()
        XCTAssertEqual(bytes.count, 24)
        XCTAssertEqual(Array(bytes.prefix(8)), [0xC0, 0x16, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(bytes.dropFirst(8).prefix(8)), [0xDB, 0x27, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(bytes.dropFirst(16).prefix(8)), [0, 0, 0, 0, 0, 0, 0, 0])
    }

    func testKeyboardReportMatchesKarabinerLayout() {
        let bytes = KarabinerVirtualHIDReportCodec.keyboardReport(modifiers: 0x02, keys: [0x04, 0x05])
        XCTAssertEqual(bytes.count, KarabinerVirtualHIDReportCodec.keyboardReportLength)
        XCTAssertEqual(Array(bytes.prefix(7)), [0x01, 0x02, 0x00, 0x04, 0x00, 0x05, 0x00])
        XCTAssertEqual(Set(bytes.dropFirst(7)), [0])
    }

    func testPointingReportMatchesKarabinerLayout() {
        let bytes = KarabinerVirtualHIDReportCodec.pointingReport(
            buttonMask: 0x0000_0005,
            dx: -2,
            dy: 3,
            verticalWheel: -1,
            horizontalWheel: 4
        )
        XCTAssertEqual(bytes.count, KarabinerVirtualHIDReportCodec.pointingReportLength)
        XCTAssertEqual(Array(bytes), [0x05, 0x00, 0x00, 0x00, 0xFE, 0x03, 0xFF, 0x04])
    }

    func testRequestFrameUsesPqrsUnixDomainStreamFraming() {
        let payload = KarabinerVirtualHIDReportCodec.servicePayload(request: .postPointingInputReport, payload: Data([0xAA]))
        let frame = KarabinerVirtualHIDReportCodec.requestFrame(requestId: 0x0102_0304_0506_0708, payload: payload)

        XCTAssertEqual(Array(frame.prefix(4)), [0, 0, 0, 13])
        XCTAssertEqual(frame[frame.index(frame.startIndex, offsetBy: 4)], KarabinerVirtualHIDReportCodec.FrameType.request.rawValue)
        XCTAssertEqual(Array(frame.dropFirst(5).prefix(8)), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(Array(frame.dropFirst(13)), [0x06, 0x00, 0x0C, 0xAA])
    }

    func testHelperRequestFramesKeyboardReport() throws {
        let report = KarabinerVirtualHIDReportCodec.keyboardReport(modifiers: 0, keys: [0x04])
        let request = try SideScreenVirtualHIDHelperCodec.request(command: .keyboardReport, payload: report)

        XCTAssertEqual(Array(request.prefix(4)), Array("SSHV".utf8))
        XCTAssertEqual(request[request.index(request.startIndex, offsetBy: 4)], 1)
        XCTAssertEqual(request[request.index(request.startIndex, offsetBy: 5)], SideScreenVirtualHIDHelperCodec.Command.keyboardReport.rawValue)
        XCTAssertEqual(Array(request.dropFirst(6).prefix(2)), [0, 67])
        XCTAssertEqual(request.dropFirst(SideScreenVirtualHIDHelperCodec.requestHeaderLength), report)
    }

    func testHelperRejectsWrongPayloadSizeBeforeSending() {
        XCTAssertThrowsError(try SideScreenVirtualHIDHelperCodec.request(command: .keyboardReport, payload: Data(repeating: 0, count: 66)))
        XCTAssertThrowsError(try SideScreenVirtualHIDHelperCodec.request(command: .pointingReport, payload: Data(repeating: 0, count: 7)))
        XCTAssertThrowsError(try SideScreenVirtualHIDHelperCodec.request(command: .initializeDevices, payload: Data([1])))
    }

    func testHelperResponseParsing() throws {
        XCTAssertEqual(
            try SideScreenVirtualHIDHelperCodec.parseResponse(Data(Array("SSHR".utf8) + [0])),
            .ok
        )
        XCTAssertEqual(SideScreenVirtualHIDHelperCodec.response(status: .upstreamFailed), Data(Array("SSHR".utf8) + [2]))
        XCTAssertThrowsError(try SideScreenVirtualHIDHelperCodec.parseResponse(Data(Array("NOPE".utf8) + [0])))
    }

    func testHelperStatusResponseParsing() throws {
        let payload = SideScreenVirtualHIDHelperStatus(
            helperProtocolVersion: 1,
            helperBuildVersion: 2,
            karabinerClientProtocolVersion: 6,
            upstreamAvailable: true
        )
        let response = SideScreenVirtualHIDHelperCodec.statusResponse(status: .ok, payload: payload)

        XCTAssertEqual(try SideScreenVirtualHIDHelperCodec.parseStatusResponse(response), payload)
        XCTAssertThrowsError(try SideScreenVirtualHIDHelperCodec.parseStatusResponse(Data(Array("SSHR".utf8) + [0])))
    }

    func testHelperInstallerBuildsLaunchDaemonPlist() throws {
        let data = try VirtualHIDHelperInstaller.launchDaemonPlistData(uid: 501)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["Label"] as? String, "com.sidescreen.virtualhidhelper.501")
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["KeepAlive"] as? Bool, true)
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            [
                VirtualHIDHelperInstaller.helperInstallPath,
                "--allowed-uid",
                "501",
                "--socket",
                "/tmp/sidescreen-virtualhid-501.sock"
            ]
        )
    }

    func testHelperInstallerSearchesSwiftBuildAndAppLocations() {
        let candidates = VirtualHIDHelperInstaller.helperSourceCandidates(
            executableDirectory: "/App/Contents/MacOS",
            resourceDirectory: "/App/Contents/Resources",
            currentDirectory: "/repo/MacHost"
        )

        XCTAssertTrue(candidates.contains("/App/Contents/MacOS/SideScreenVirtualHIDHelper"))
        XCTAssertTrue(candidates.contains("/App/Contents/Resources/../Library/PrivilegedHelperTools/SideScreenVirtualHIDHelper"))
        XCTAssertTrue(candidates.contains("/repo/MacHost/.build/out/Products/Release/SideScreenVirtualHIDHelper"))
        XCTAssertTrue(candidates.contains("/repo/MacHost/.build/out/Products/Debug/SideScreenVirtualHIDHelper"))
    }
}
