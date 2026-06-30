import Foundation

struct EndpointAdvertiser {
    static func advertisedHost(mode: EndpointMode, tailnetHost: String) -> String? {
        switch mode {
        case .lan:
            return LANAddressResolver.primaryIPv4()
        case .tailnet, .manual:
            let trimmed = tailnetHost.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

