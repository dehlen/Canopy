import PerfectNotifications
import PerfectHTTP
import Foundation
import PromiseKit

func oauthCallback(request rq: HTTPRequest, response: HTTPResponse) {
    print()
    print("/oauth")

    do {
        let qq = Dictionary(uniqueKeysWithValues: rq.queryParams)
        guard let state = qq["state"], let code = qq["code"] else {
            throw HTTPResponseError(status: .badRequest, description: "Invalid JSON")
        }
        try finish(code: code, state: state)
        response.appendBody(string: "<p>Authenticating, please stand-by...</p>")
        response.completed()
    } catch {
        response.completed(status: .expectationFailed)
        response.appendBody(string: error.legibleDescription)
    }
}

private func finish(code: String, state: String) throws {
    let url = URL(string: "https://github.com/login/oauth/access_token")!
    guard let data = state.data(using: .utf8) else {
        throw HTTPResponseError(status: .badRequest, description: "Bad state string")
    }
    let signInParameters = try JSONDecoder().decode(SignIn.self, from: data)
    let json = [
        "client_id": clientId,
        "client_secret": "2397959358b460caf90f943c9a0f548cb084d5f2",
        "code": code,
        "redirect_uri": redirectUri,
        "state": state
    ]
    var rq = URLRequest(url: url)
    rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
    rq.setValue("application/json", forHTTPHeaderField: "Accept")
    rq.httpMethod = "POST"
    rq.httpBody = try JSONSerialization.data(withJSONObject: json)

    struct Response: Decodable {
        let access_token: String
        let scope: String?  // docs aren't clear if this is always present
    }

    func send(key: String, value: String) {
        let confName = signInParameters.production
            ? NotificationPusher.productionConfigurationName
            : NotificationPusher.sandboxConfigurationName

        NotificationPusher(apnsTopic: signInParameters.apnsTopic).pushAPNS(configurationName: confName, deviceTokens: [signInParameters.deviceToken], notificationItems: [
            .customPayload(key, value)
        ], callback: { responses in
            print("APNs says:", responses)
        })
    }

    firstly {
        URLSession.shared.dataTask(.promise, with: rq)
    }.map { data, _ in
        try JSONDecoder().decode(Response.self, from: data).access_token
    }.then { oauthToken in
        updateTokens(with: signInParameters.upgrade(with: oauthToken)).map{ oauthToken }
    }.done { oauthToken in
        send(key: "oauthToken", value: oauthToken) //TODO APPLE SAYS TO ENCRYPT
    }.catch { error in
        print(#function, error)
        send(key: "oauthTokenError", value: error.legibleDescription)
    }
}

private extension SignIn {
    func upgrade(with oauthToken: String) -> TokenUpdate {
        return TokenUpdate(oauthToken: oauthToken, deviceToken: deviceToken, apnsTopic: apnsTopic, production: production)
    }
}
