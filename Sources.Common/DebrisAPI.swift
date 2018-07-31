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
