import protocol xp.TitledError
import struct xp.TokenUpdate
import struct xp.Enrollment
import struct xp.SignIn
import enum PMKFoundation.PMKHTTPError
import enum xp.Node
import enum xp.API
import var xp.clientId
import KeychainAccess
import LegibleError
import Foundation
import PromiseKit

public extension String {
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
                return (legibleLocalizedDescription, defaultTitle)
            }
            let more = response.errors.compactMap(\.message)
            if !more.isEmpty {
                return (more.joined(separator: ". ") + ".", response.message)
            } else {
                return (legibleLocalizedDescription, response.message)
            }
        }
    }
}

////// auth
public extension Notification.Name {
    static var credsUpdated: Notification.Name { return Notification.Name("com.codebasesaga.credsUpdated") }
}

private let keychain = Keychain(service: "com.codebasesaga.Canopy.GitHub", accessGroup: "TEQMQBRC7B.com.codebasesaga.Canopy")
    .accessibility(.afterFirstUnlock)
    .synchronizable(true)
    .label("Canopy")
    .comment("OAuth Token")

public var creds: (username: String, token: String)? {
    get {
    #if targetEnvironment(simulator)
        return ("codebasesaga-tester", "66c58c7a33e7afcb4abbb2891089f9a8f33b2b1c")
    #else
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
    #endif
    }
    set {
        let oldValue = creds
        if oldValue == nil, newValue == nil { return }  // prevents triggers when we don't want them

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
public struct Repo: Decodable {
    public let id: Int
    public let full_name: String
    public let owner: Owner
    public let `private`: Bool
    public let permissions: Permissions
    public let name: String

    public struct Permissions: Decodable {
        public let admin: Bool
    }

    public struct Owner: Decodable, Hashable {
        public let id: Int
        public let login: String
        public let type: Kind

        public enum Kind: String, Codable {
            case organization = "Organization"
            case user = "User"
        }
    }

    public var isPartOfOrganization: Bool {
        return owner.type == .organization
    }
}

extension Repo: Hashable, Equatable, Comparable {
    public static func == (lhs: Repo, rhs: Repo) -> Bool {
        return lhs.id == rhs.id
    }

#if swift(>=4.2)
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
#else
    public var hashValue: Int {
        return id
    }
#endif

    public static func < (lhs: Repo, rhs: Repo) -> Bool {
        return lhs.full_name.localizedLowercase < rhs.full_name.localizedLowercase
    }
}

public extension Node {
    init(_ repo: Repo) {
        self = .repository(repo.owner.login, repo.name)
    }
}

public extension URL {
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

    static var termsOfUse: URL {
        return URL(string: "https://mxcl.github.io/canopy/#terms-of-use")!
    }
    static var privacyPolicy: URL {
        return URL(string: "https://mxcl.github.io/canopy/#privacy-policy")!
    }
    static var faq: URL {
        return URL(string: "https://mxcl.github.io/canopy/#faq")!
    }
    static var manageSubscription: URL {
        return URL(string: "itmss://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/manageSubscriptions")!
    }
    static var home: URL {
        return URL(string: "https://mxcl.github.io/canopy/")!
    }
}

public extension URLRequest {
    init(_ canopy: URL.Canopy) {
        self.init(url: URL(canopy))
    }
}

public func updateTokens(oauth: String, device: String) -> Promise<Void> {
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

public var isProductionAPNsEnvironment: Bool {
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
    public var title: String {
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

public extension Promise where T == (data: Data, response: URLResponse) {
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

private extension Array where Element == String {
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

private func _alert(error: Error, title: String?, file: StaticString, line: UInt) -> (String, String) {
    print("\(file):\(line)", error.legibleDescription, error)

    var computeTitle: String {
        switch (error as NSError).domain {
        case "SKErrorDomain":
            return "App Store Error"
        case "kCLErrorDomain":
            return "Core Location Error"
        case NSCocoaErrorDomain:
            return "Error"
        default:
            return "Unexpected Error"
        }
    }

    let title = title ?? (error as? TitledError)?.title ?? computeTitle

    if let error = error as? PMKHTTPError {
        return error.gitHubDescription(defaultTitle: title)
    } else {
        return (error.legibleLocalizedDescription, title)
    }
}

#if os(macOS)
import AppKit

public func alert(error: Error, title: String? = nil, file: StaticString = #file, line: UInt = #line) {
    let (msg, title) = _alert(error: error, title: title, file: file, line: line)

    // we cannot make SKError CancellableError sadly (still)
    let pair: (String, Int) = { ($0.domain, $0.code) }(error as NSError)
    guard ("SKErrorDomain", 2) != pair else { return } // user-cancelled

    alert(message: msg, title: title)
}

public func alert(message: String, title: String) {
    func go() {
      #if os(macOS)
        let alert = NSAlert()
        alert.informativeText = message
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.runModal()
      #else

      #endif
    }
    if Thread.isMainThread {
        go()
    } else {
        DispatchQueue.main.async(execute: go)
    }
}
#else
import UIKit

@discardableResult
public func alert(error: Error, title: String? = nil, file: StaticString = #file, line: UInt = #line) -> Guarantee<Void> {

    // we cannot make SKError CancellableError sadly (still)
    let pair: (String, Int) = { ($0.domain, $0.code) }(error as NSError)
    guard ("SKErrorDomain", 2) != pair else { return Guarantee() }

    let (msg, title) = _alert(error: error, title: title, file: file, line: line)
    return alert(message: msg, title: title)
}

@discardableResult
public func alert(message: String, title: String? = nil) -> Guarantee<Void> {
    let (promise, seal) = Guarantee<UIAlertAction>.pending()

    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(.init(title: "OK", style: .default, handler: seal))

    guard let vc = UIApplication.shared.visibleViewController else {
        print("error: Could not present UIAlertViewController")
        return Guarantee()
    }

    if let transitionCoordinator = vc.transitionCoordinator {
        transitionCoordinator.animate(alongsideTransition: nil, completion: { _ in
            vc.present(alert, animated: true)
        })
    } else {
        vc.present(alert, animated: true)
    }

    return promise.asVoid()
}

private extension UIApplication {
    var visibleViewController: UIViewController? {
        var vc = UIApplication.shared.keyWindow?.rootViewController
        while let presentedVc = vc?.presentedViewController {
            if let navVc = (presentedVc as? UINavigationController)?.viewControllers.last {
                vc = navVc
            } else if let tabVc = (presentedVc as? UITabBarController)?.selectedViewController {
                vc = tabVc
            } else {
                vc = presentedVc
            }
        }
        return vc
    }
}
#endif

public extension Set where Element == Enrollment {
    @inline(__always)
    func contains(_ repo: Repo) -> Bool {
        return contains(Enrollment(repoId: repo.id, eventMask: 0))
    }
}

public extension Set where Element == Node {
    @inline(__always)
    func contains(_ repo: Repo) -> Bool {
        return contains(.init(repo))
    }
}
