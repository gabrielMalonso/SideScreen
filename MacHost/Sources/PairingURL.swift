import Foundation

enum PairingURL {
    static func build(host: String, port: UInt16, token: Data, name: String, mode: EndpointMode = .lan) -> String {
        let tokenStr = base64URLEncode(token)
        var nameAllowed = CharacterSet.urlQueryAllowed
        nameAllowed.remove(charactersIn: "&=?#")
        let nameEncoded = name.addingPercentEncoding(withAllowedCharacters: nameAllowed) ?? ""
        return "sidescreen://\(host):\(port)?t=\(tokenStr)&name=\(nameEncoded)&mode=\(mode.queryValue)"
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
