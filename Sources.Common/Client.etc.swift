import Foundation
import PromiseKit

extension String {
    init(deviceToken: Data) {
        self.init(deviceToken.map{ String(format: "%02.2hhx", $0) }.joined())
    }
}

enum CanopyError: Error {
    case badURL
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

////// auth
extension Notification.Name {
    static var credsUpdated: Notification.Name { return Notification.Name("CredsUpdatedNotification") }
}

private let keychain = Keychain(server: "https://github.com", protocolType: .https)
    .accessibility(.whenUnlocked)
    .synchronizable(true)

extension UserDefaults {
    var username: String? {
        get {
            return string(forKey: #function)
        }
        set {
            set(newValue, forKey: #function)
        }
    }
}

var creds: (username: String, token: String)? {
    get {
        guard let username = UserDefaults.standard.username else { return nil }
        do {
            guard let token = try keychain.get(username) else {
                print(#function, "Unexpected nil for token from keychain")
                return nil
            }
            return (username, token)
        } catch {
            print(#function, error)
            return nil
        }
    }
    set {
        if let (login, token) = newValue {
            do {
                try keychain.set(token, key: login)
                UserDefaults.standard.username = login

                NotificationCenter.default.post(name: .credsUpdated, object: nil, userInfo: [
                    "token": token,
                    "login": login
                ])
            } catch {
                if let user = UserDefaults.standard.username {
                    keychain[user] = nil
                }
                UserDefaults.standard.username = nil
                NotificationCenter.default.post(name: .credsUpdated, object: nil)
            }
        } else if let user = UserDefaults.standard.username {
            keychain[user] = nil
            NotificationCenter.default.post(name: .credsUpdated, object: nil)
        }
    }
}

////// repo
struct Repo: Decodable {
    let id: Int
    let full_name: String
    let owner: Owner
    let `private`: Bool
    let permissions: Permissions

    struct Permissions: Decodable {
        let admin: Bool
    }

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
        return URLSession.shared.dataTask(.promise, with: rq).validate().asVoid()
    } catch {
        return Promise(error: error)
    }
}

var isProductionAPSEnvironment: Bool {
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
