import Foundation

let clientId = "00f34fed06ffad73fe17"
let redirectUri = "http://ci.codebasesaga.com:1889/oauth"
let hookUri = "http://ci.codebasesaga.com:1889/github"

enum EE: Error {
    case unexpected
}

struct UpdateTokens: Codable {
    let oauth: String
    let device: String
    let apnsTopic: String
}

struct SignIn: Codable {
    let deviceToken: String
    let apnsTopic: String
}
