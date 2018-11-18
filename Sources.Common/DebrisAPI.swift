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

public enum ServerError: Int {
    case authentication
}

public protocol XPError: LocalizedError, HTTPStatusCodable {
    var serverError: ServerError { get }
}

public protocol HTTPStatusCodable {
    var httpStatusCode: Int { get }
}

extension PMKHTTPError: HTTPStatusCodable {
    public var httpStatusCode: Int {
        switch self {
        case .badStatusCode(let code, _, _):
            return code
        }
    }
}

public struct Enrollment {
    public let repoId: Int
    public let events: Set<Event>

    enum CodingKeys: String, CodingKey {
        case repoId, events
    }

    public init(repoId: Int, eventMask: Int) {
        self.repoId = repoId
        self.events = Set(mask: eventMask)
    }

    public init(repoId: Int, events: Set<Event>) {
        self.repoId = repoId
        self.events = events
    }
}

extension Enrollment: Hashable, Equatable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(repoId)
    }
    public static func == (lhs: Enrollment, rhs: Enrollment) -> Bool {
        return lhs.repoId == rhs.repoId
    }
}

extension Enrollment: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(repoId, forKey: .repoId)
        try container.encode(events.maskValue, forKey: .events)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repoId = try container.decode(Int.self, forKey: .repoId)
        let eventMask = try container.decode(Int.self, forKey: .events)
        events = .init(mask: eventMask)
    }
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

    public var apiPath: String {
        switch self {
        case .organization:
            return "/\(ref)"
        case .repository(let owner, let name):
            return "/repos/\(owner)/\(name)"
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

extension Node: Equatable, Hashable
{}

enum RemoteNotificationUserInfo {
    case creds(login: String, token: String)
    case error(message: String, ServerError?)
    case unknown

    init(userInfo: [AnyHashable: Any]) {
        if let token = userInfo["token"] as? String, let login = userInfo["login"] as? String {
            self = .creds(login: login, token: token)
        } else if let message = userInfo["error"] {
            let code = userInfo["error-code"] as? Int
            self = .error(message: "\(message)", code.flatMap(ServerError.init))
        } else {
            self = .unknown
        }
    }
}

public enum API {
    public struct Enroll: Codable {
        public let createHooks: [Node]
        public let enrollRepoIds: [Int]    // because we sub to an org’s children, but create the hook on the org itself
    }
    public struct Unenroll: Codable {
        public let repoIds: [Int]
    }
}

public extension API.Enroll {
    enum Error: Swift.Error, Codable, HTTPStatusCodable {
        case noClearance(repoIds: [Int])
        case hookCreationFailed([Node])

        enum CodingKeys: String, CodingKey {
            case kind
            case ids
            case nodes
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Int.self, forKey: .kind)
            switch kind {
            case 0:
                let ids = try container.decode([Int].self, forKey: .ids)
                self = .noClearance(repoIds: ids)
            case 1:
                let nodes = try container.decode([Node].self, forKey: .nodes)
                self = .hookCreationFailed(nodes)
            default:
                throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Invalid kind value")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .noClearance(let ids):
                try container.encode(ids, forKey: .ids)
                try container.encode(0, forKey: .kind)
            case .hookCreationFailed(let nodes):
                try container.encode(nodes, forKey: .nodes)
                try container.encode(1, forKey: .kind)
            }
        }

        public var httpStatusCode: Int {
            return 502
        }
    }
}
