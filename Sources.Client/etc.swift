import Foundation

enum E: Error {
    case unexpected
}

extension URL {
    var gitHubParameters: (state: String, code: String)? {
        guard let cc = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        guard let queries = cc.queryItems else { return nil }
        var state: String?
        var code: String?
        for query in queries {
            if query.name == "state" { state = query.value }
            if query.name == "code" { code = query.value }
        }
        if let state = state, let code = code {
            return (state, code)
        } else {
            return nil
        }
    }
}

extension UserDefaults {
    var gitHubToken: String? {
        set { set(newValue, forKey: "token") }
        get { return string(forKey: "token") }
    }
}

let clientId = "00f34fed06ffad73fe17"
let redirectUri = "http://ci.codebasesaga.com:1889/oauth"
