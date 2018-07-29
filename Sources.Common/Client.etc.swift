import Foundation
import PromiseKit

extension String {
    init(deviceToken: Data) {
        self.init(deviceToken.map{ String(format: "%02.2hhx", $0) }.joined())
    }
}

extension PMKHTTPError {
    func gitHubDescription(defaultTitle: String) -> (String, String) {
        switch self {
        case .badStatusCode(_, let data, _):
            struct Response: Decodable {
                let message: String
                let errors: [E]
                struct E: Decodable {
                    let message: String?
                }
            }
            guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
                return (legibleDescription, defaultTitle)
            }
            let more = response.errors.compactMap(\.message)
            if !more.isEmpty {
                return (more.joined(separator: ". ") + ".", response.message)
            } else {
                return (legibleDescription, response.message)
            }
        }
    }
}

extension UserDefaults {
    @objc dynamic var gitHubOAuthToken: String? {
        get {
            return string(forKey: #function)
        }
        set {
            set(newValue, forKey: #function)
        }
    }

    func removeGitHubOAuthToken() {
        removeObject(forKey: "gitHubOAuthToken")
    }
}

struct Repo: Decodable {
    let id: Int
    let full_name: String
    let owner: Owner
    let `private`: Bool

    struct Owner: Decodable, Hashable {
        let id: Int
        let login: String
        let type: String
    }

    var isPartOfOrganization: Bool {
        return owner.type.lowercased() == "organization"
    }
}

extension Repo: Hashable, Equatable {
    static func == (lhs: Repo, rhs: Repo) -> Bool {
        return lhs.id == rhs.id
    }

#if swift(>=4.2)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
#else
    var hashValue: Int {
        return id
    }
#endif
}

extension Sequence {
    //@inlinable
    func map<T>(_ keyPath: KeyPath<Element, T>) -> [T] {
        return map {
            $0[keyPath: keyPath]
        }
    }

    //@inlinable
    func compactMap<T>(_ keyPath: KeyPath<Element, T?>) -> [T] {
        return compactMap {
            $0[keyPath: keyPath]
        }
    }
}

extension URL {
    static func signIn(deviceToken: String) -> URL? {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return nil
        }
        let payload = SignIn(deviceToken: deviceToken, apnsTopic: bundleId, production: isProductionAPSEnvironment)
        guard let data = try? JSONEncoder().encode(payload) else {
            return nil
        }
        guard let state = String(data: data, encoding: .utf8) else {
            return nil
        }

        var cc = URLComponents()
        cc.scheme = "https"
        cc.host = "github.com"
        cc.path = "/login/oauth/authorize"
        cc.queryItems = [
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "scope": "admin:repo_hook admin:org_hook repo",
            "state": state,
            "allow_signup": "false"  //avoid potential confusion
        ].map(URLQueryItem.init)
        return cc.url
    }
}

func updateTokens(oauth: String, device: String) -> Promise<Void> {
    do {
        let bid = Bundle.main.bundleIdentifier!
        let up = TokenUpdate(
            oauthToken: oauth,
            deviceToken: device,
            apnsTopic: bid,
            production: isProductionAPSEnvironment
        )
        var rq = URLRequest(url: URL(string: "\(serverBaseUri)/token")!)
        rq.httpMethod = "POST"
        rq.httpBody = try JSONEncoder().encode(up)
        rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return URLSession.shared.dataTask(.promise, with: rq).asVoid()
    } catch {
        return Promise(error: error)
    }
}

private var isProductionAPSEnvironment: Bool {
#if os(iOS)
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
        return true
    }
#else
    let url = Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")
#endif
    guard let data = try? Data(contentsOf: url), let string = String(data: data, encoding: .ascii) else {
        return true
    }
#if os(iOS)
    return !string.contains("""
        <key>aps-environment</key>
        \t\t<string>development</string>
        """)
#else
    return !string.contains("""
        <key>com.apple.developer.aps-environment</key>
        \t\t<string>development</string>
        """)
#endif
}
