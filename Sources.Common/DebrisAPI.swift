import protocol Foundation.LocalizedError

public struct TokenUpdate: Codable {
    public let oauthToken: String
    public let deviceToken: String
    public let apnsTopic: String
    public let production: Bool

    public init(oauthToken: String, deviceToken: String, apnsTopic: String, production: Bool) {
        self.oauthToken = oauthToken
        self.deviceToken = deviceToken
        self.apnsTopic = apnsTopic
        self.production = production
    }
}

public struct SignIn: Codable {
    public let deviceToken: String
    public let apnsTopic: String
    public let production: Bool
}

public struct Receipt: Codable {
    public let isProduction: Bool
    public let base64: String
}

public enum ServerError: Int {
    case authentication
}

public protocol XPError: LocalizedError {
    var serverError: ServerError { get }
}

public enum Node: Codable {
    case organization(String)
    case repository(String, String)

    public var ref: String {
        switch self {
        case .organization(let login):
            return "orgs/\(login)"
        case .repository(let owner, let name):
            return "\(owner)/\(name)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case node
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let parts = try container.decode(String.self, forKey: .node).split(separator: "/")
        guard parts.count == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .node, in: container, debugDescription: "Incorrect path component count")
        }
        if parts[0] == "orgs" {
            self = .organization(String(parts[1]))
        } else {
            self = .repository(String(parts[0]), String(parts[1]))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .organization(let name):
            try container.encode("orgs/\(name)", forKey: .node)
        case .repository(let user, let name):
            try container.encode("\(user)/\(name)", forKey: .node)
        }
    }
}

#if os(macOS)
extension Node: Equatable, Hashable
{}
#endif
