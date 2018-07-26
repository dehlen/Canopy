import Foundation

let clientId = "00f34fed06ffad73fe17"
let redirectUri = "http://ci.codebasesaga.com:1889/oauth"
let hookUri = "http://ci.codebasesaga.com:1889/github"

enum EE: Error {
    case unexpected
}

struct TokenUpdate: Codable {
    let oauthToken: String
    let deviceToken: String
    let apnsTopic: String
    let production: Bool
}

struct SignIn: Codable {
    let deviceToken: String
    let apnsTopic: String
    let production: Bool
}

#if !swift(>=4.1.5)
extension Collection where Element: Equatable {
    public func firstIndex(of member: Element) -> Self.Index? {
        return self.index(of: member)
    }
}
#endif
