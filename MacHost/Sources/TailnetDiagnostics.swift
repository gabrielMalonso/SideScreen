import Darwin
import Foundation

struct TailnetDiagnostic: Equatable {
    enum Severity: Equatable {
        case ok
        case warning
        case error
    }

    let severity: Severity
    let summary: String
    let detail: String
}

enum TailnetDiagnostics {
    static func inspect(
        host rawHost: String,
        resolver: (String) -> [String] = resolveIPv4
    ) -> TailnetDiagnostic {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return TailnetDiagnostic(
                severity: .error,
                summary: "Tailnet host missing",
                detail: "Enter the Mac's MagicDNS name or its 100.64.x.x Tailnet IP."
            )
        }

        guard !host.contains("://"), !host.contains("/"), !host.contains(":") else {
            return TailnetDiagnostic(
                severity: .error,
                summary: "Use host only",
                detail: "Do not include scheme, path, or port. Example: mac-mini.tailnet.ts.net"
            )
        }

        if let ip = IPv4Address(host) {
            if ip.isTailscaleCGNAT {
                return TailnetDiagnostic(
                    severity: .ok,
                    summary: "Tailnet IP ready",
                    detail: "\(host) is inside Tailscale's 100.64.0.0/10 range."
                )
            }
            return TailnetDiagnostic(
                severity: .warning,
                summary: "Not a Tailnet IP",
                detail: "\(host) is not in 100.64.0.0/10. Use Tailnet mode only if routing is intentional."
            )
        }

        let lowercasedHost = host.lowercased()
        if lowercasedHost.hasSuffix(".ts.net") {
            let resolved = resolver(host).compactMap(IPv4Address.init)
            if resolved.isEmpty {
                return TailnetDiagnostic(
                    severity: .warning,
                    summary: "MagicDNS not resolved",
                    detail: "Check Tailscale on this Mac or use the Mac's 100.x Tailnet IP."
                )
            }
            if resolved.contains(where: \.isTailscaleCGNAT) {
                return TailnetDiagnostic(
                    severity: .ok,
                    summary: "MagicDNS resolves to Tailnet",
                    detail: "\(host) resolved to \(resolved.map(\.description).joined(separator: ", "))."
                )
            }
            return TailnetDiagnostic(
                severity: .warning,
                summary: "MagicDNS resolved outside Tailnet",
                detail: "\(host) resolved, but not to a 100.64.0.0/10 address."
            )
        }

        return TailnetDiagnostic(
            severity: .warning,
            summary: "Manual host",
            detail: "Prefer a .ts.net MagicDNS name or 100.64.x.x Tailnet IP for predictable routing."
        )
    }

    private static func resolveIPv4(host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let result else {
            return []
        }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = result
        while let current = cursor {
            let sockaddr = current.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var address = sockaddr.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                addresses.append(String(cString: buffer))
            }
            cursor = current.pointee.ai_next
        }
        return Array(Set(addresses)).sorted()
    }
}

private struct IPv4Address: Equatable, CustomStringConvertible {
    let octets: [UInt8]

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let parsed = parts.compactMap { UInt8(String($0)) }
        guard parsed.count == 4, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        octets = parsed
    }

    var isTailscaleCGNAT: Bool {
        octets[0] == 100 && (64...127).contains(octets[1])
    }

    var description: String {
        octets.map(String.init).joined(separator: ".")
    }
}
