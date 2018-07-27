import Foundation

let clientId = "00f34fed06ffad73fe17"
let serverHostname = "canopy.codebasesaga.com"
let serverBaseUri = "http://\(serverHostname)"
let redirectUri = "\(serverBaseUri)/oauth"
let hookUri = "\(serverBaseUri)/github"

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
