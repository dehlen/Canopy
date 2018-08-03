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
