import PerfectNotifications
import PerfectHTTP
import Foundation
import PromiseKit
import Roots

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
    guard let parametersData = Data(base64Encoded: state)?.xor else {
        throw HTTPResponseError(status: .badRequest, description: "Bad state string")
    }
    let signInParameters = try JSONDecoder().decode(SignIn.self, from: parametersData)
    let json = [
        "client_id": clientId,
        "client_secret": "2397959358b460caf90f943c9a0f548cb084d5f2",
        "code": code,
        "redirect_uri": URL(.redirect).absoluteString,
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

    struct ErrorResponse: Decodable, XPError {
        let error: String
        let error_description: String
        let error_uri: URL

        var serverError: ServerError {
            return .authentication
        }

        var errorDescription: String? {
            return error_description
        }
    }

    func decode(_ data: Data) throws -> Response {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            if let error = try? decoder.decode(ErrorResponse.self, from: data) {
                throw error
            } else {
                throw error
            }
        }
    }

    func send(items: [APNSNotificationItem]) {
        let confName = signInParameters.production
            ? NotificationPusher.productionConfigurationName
            : NotificationPusher.sandboxConfigurationName
        print("sending:", items)
        NotificationPusher(apnsTopic: signInParameters.apnsTopic).pushAPNS(configurationName: confName, deviceTokens: [signInParameters.deviceToken], notificationItems: items, callback: { responses in
            print("APNs says:", responses[0])
        })
    }

    func success(login: String, token: String) {
        var items: [APNSNotificationItem] = [
            .customPayload("token", token), //TODO APPLE SAYS TO ENCRYPT
            .customPayload("login", login)
        ]
        if !signInParameters.apnsTopic.isMac {
            items.append(.contentAvailable)
        }
        send(items: items)
    }

    func failure(error rawError: Error) {
        guard let error = rawError as? XPError else {
            return alert(message: rawError.legibleDescription)
        }

        var items = [APNSNotificationItem.customPayload("error-code", error.serverError.rawValue)]
        if signInParameters.apnsTopic.isMac {
            items.append(.customPayload("error", error.legibleDescription))
        } else {
            items.append(.alertTitle("Sign‑in Error"))
            items.append(.alertBody(error.legibleDescription))
        }
        send(items: items)
    }

    firstly {
        URLSession.shared.dataTask(.promise, with: rq)
    }.map { data, _ in
        try decode(data).access_token
    }.then { oauthToken in
        updateTokens(with: signInParameters.upgrade(with: oauthToken)).map{ ($0, oauthToken) }
    }.done(success).catch { error in
        failure(error: error)
    }
}

private extension SignIn {
    func upgrade(with oauthToken: String) -> TokenUpdate {
        return TokenUpdate(oauthToken: oauthToken, deviceToken: deviceToken, apnsTopic: apnsTopic, production: production)
    }
}

private extension String {
    var isMac: Bool {
        return self == "com.codebasesaga.GitBell" || self == "com.codebasesaga.macOS.Canopy"
    }
}
