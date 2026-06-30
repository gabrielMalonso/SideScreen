import Foundation

enum EndpointMode: String, Codable, CaseIterable {
    case lan
    case tailnet
    case manual

    var queryValue: String {
        rawValue
    }
}

