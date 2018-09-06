import Foundation
import PromiseKit

extension String {
    init(deviceToken: Data) {
        self.init(deviceToken.map{ String(format: "%02.2hhx", $0) }.joined())
    }
}

enum CanopyError: Error {
    case badURL
    case notHTTPResponse
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
    static var credsUpdated: Notification.Name { return Notification.Name("com.codebasesaga.credsUpdated") }
}

private let keychain = Keychain(service: "com.codebasesaga.Canopy.GitHub", accessGroup: "TEQMQBRC7B.com.codebasesaga.Canopy")
    .accessibility(.afterFirstUnlock)
    .synchronizable(true)
    .label("Canopy")
    .comment("OAuth Token")

var creds: (username: String, token: String)? {
    get {
        guard let username = keychain.allItems().first?["key"] as? String else {
            return nil
        }
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
        do {
            guard let (login, token) = newValue else {
                throw CocoaError.error(.coderInvalidValue)
            }
            try keychain.set(token, key: login)

            NotificationCenter.default.post(name: .credsUpdated, object: nil, userInfo: [
                "token": token,
                "login": login
            ])
        } catch {
            try! keychain.removeAll()
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
    let name: String

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

extension Repo: Hashable, Equatable, Comparable {
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

    static func < (lhs: Repo, rhs: Repo) -> Bool {
        return lhs.full_name < rhs.full_name
    }
}

extension Node {
    init(_ repo: Repo) {
        self = .repository(repo.owner.login, repo.name)
    }
}

extension URL {
    static func signIn(deviceToken: String) -> URL? {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return nil
        }
        let payload = SignIn(deviceToken: deviceToken, apnsTopic: bundleId, production: isProductionAPNsEnvironment)
        guard let data = try? JSONEncoder().encode(payload) else {
            return nil
        }
        let state = data.xor.base64EncodedString()

        var cc = URLComponents()
        cc.scheme = "https"
        cc.host = "github.com"
        cc.path = "/login/oauth/authorize"
        cc.queryItems = [
            "client_id": clientId,
            "scope": "admin:repo_hook admin:org_hook repo",
            "state": state,
            "allow_signup": "false"  //avoid potential confusion
        ].map(URLQueryItem.init)
        return cc.url
    }
}

extension URLRequest {
    init(_ canopy: URL.Canopy) {
        self.init(url: URL(canopy))
    }
}

func updateTokens(oauth: String, device: String) -> Promise<Void> {
    do {
        let bid = Bundle.main.bundleIdentifier!
        let up = TokenUpdate(
            oauthToken: oauth,
            deviceToken: device,
            apnsTopic: bid,
            production: isProductionAPNsEnvironment
        )
        var rq = URLRequest(.token)
        rq.httpMethod = "POST"
        rq.httpBody = try JSONEncoder().encode(up)
        rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return URLSession.shared.dataTask(.promise, with: rq).validate().asVoid()
    } catch {
        return Promise(error: error)
    }
}

var isProductionAPNsEnvironment: Bool {
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

extension API.Enroll.Error: TitledError {
    var title: String {
        return "Enrollment Error"
    }

    public var errorDescription: String? {
        switch self {
        case API.Enroll.Error.noClearance:
            return "You do not have clearance to all the requested repositories"
        case API.Enroll.Error.hookCreationFailed(let nodes):
            return """
            Hook creation failed for \(nodes.map(\.ref).english); probably you don’t have clearance to create webhooks, contact the admin.
            """
        }
    }
}

extension Promise where T == (data: Data, response: URLResponse) {
    func httpValidate() -> Promise {
        return validate().recover { error -> Promise in
            guard case PMKHTTPError.badStatusCode(_, let data, _) = error else {
                throw error
            }
            if let error = try? JSONDecoder().decode(API.Enroll.Error.self, from: data) {
                throw error
            } else {
                throw error
            }
        }
    }
}

extension Array where Element == String {
    var english: String {
        switch count {
        case ...0:
            return ""
        case 1:
            return first!
        default:
            var me = self
            let last = me.popLast()!
            return me.joined(separator: ", ") + " and " + last
        }
    }
}
