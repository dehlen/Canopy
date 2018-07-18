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
    var gitHubOAuthToken: String? {
        get {
            return string(forKey: #function)
        }
        set {
            set(newValue, forKey: #function)
        }
    }
}

struct Repo: Decodable {
    let id: Int
    let full_name: String
    let owner: Owner

    struct Owner: Decodable, Hashable {
        let id: Int
        let login: String
        let type: String
    }

    var isOrganization: Bool {
        return owner.type.lowercased() == "organization"
    }
}

extension Repo: Hashable, Equatable {
    static func == (lhs: Repo, rhs: Repo) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Sequence {
    @inlinable
    func map<T>(_ keyPath: KeyPath<Element, T>) -> [T] {
        return map {
            $0[keyPath: keyPath]
        }
    }

    @inlinable
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
        let payload = SignIn(deviceToken: deviceToken, apnsTopic: bundleId)
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
            "scope": "admin:repo_hook admin:org_hook repo:read",
            "state": state,
            "allow_signup": "false"  //avoid potential confusion
        ].map(URLQueryItem.init)
        return cc.url
    }
}

func updateTokens(oauth: String, device: String) -> Promise<Void> {
    do {
        let bid = Bundle.main.bundleIdentifier!
        let up = UpdateTokens(oauth: oauth, device: device, apnsTopic: bid)
        var rq = URLRequest(url: URL(string: "http://ci.codebasesaga.com:1889/token")!)
        rq.httpMethod = "POST"
        rq.httpBody = try JSONEncoder().encode(up)
        rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return URLSession.shared.dataTask(.promise, with: rq).asVoid()
    } catch {
        return Promise(error: error)
    }
}
