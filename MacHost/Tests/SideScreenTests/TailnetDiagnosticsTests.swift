import XCTest
@testable import SideScreen

final class TailnetDiagnosticsTests: XCTestCase {
    func testAcceptsTailscaleIpRange() {
        let diagnostic = TailnetDiagnostics.inspect(host: "100.92.12.4")

        XCTAssertEqual(diagnostic.severity, .ok)
        XCTAssertEqual(diagnostic.summary, "Tailnet IP ready")
    }

    func testWarnsForNonTailnetIp() {
        let diagnostic = TailnetDiagnostics.inspect(host: "192.168.1.42")

        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.summary, "Not a Tailnet IP")
    }

    func testRejectsUrlInsteadOfHost() {
        let diagnostic = TailnetDiagnostics.inspect(host: "https://mac-mini.tailnet.ts.net:54321")

        XCTAssertEqual(diagnostic.severity, .error)
        XCTAssertEqual(diagnostic.summary, "Use host only")
    }

    func testMagicDnsOkWhenResolverReturnsTailnetIp() {
        let diagnostic = TailnetDiagnostics.inspect(host: "mac-mini.tailnet.ts.net") { _ in
            ["100.92.12.4"]
        }

        XCTAssertEqual(diagnostic.severity, .ok)
        XCTAssertEqual(diagnostic.summary, "MagicDNS resolves to Tailnet")
    }

    func testMagicDnsWarnsWhenResolverFails() {
        let diagnostic = TailnetDiagnostics.inspect(host: "mac-mini.tailnet.ts.net") { _ in
            []
        }

        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.summary, "MagicDNS not resolved")
    }
}
