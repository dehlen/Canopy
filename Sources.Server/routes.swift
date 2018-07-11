import PerfectNotifications
import PerfectHTTP
import Foundation

var routes: Routes {
    var routes = Routes()
    routes.add(method: .post, uri: "/token", handler: tokenHandler)
    routes.add(method: .post, uri: "/github", handler: githubHandler)
    return routes
}

var token: String? {
    set {
        UserDefaults.standard.set(newValue, forKey: "token")
    }
    get {
        return UserDefaults.standard.string(forKey: "token")
    }
}

private func tokenHandler(request rq: HTTPRequest, _ response: HTTPResponse) {

    print("Receiving token")

    enum E: Error {
        case noBody
    }

    struct Response: Decodable {
        let token: String
    }

    do {
        guard let bytes = rq.postBodyBytes else {
            throw E.noBody
        }
        let data = Data(bytes: bytes)
        token = try JSONDecoder().decode(Response.self, from: data).token
        response.appendBody(string: "got: \(String(describing: token))")
        response.completed()
    } catch {
        response.appendBody(string: "error: \(error)")
        response.completed(status: .badRequest)
    }
}

private func githubHandler(request: HTTPRequest, _ response: HTTPResponse) {
    print("Receiving Webhook payload")

    guard let token = token else {
        response.appendBody(string: "No token registered")
        return response.completed(status: .expectationFailed)
    }

    guard let eventType = request.header(.custom(name: "X-GitHub-Event")) else {
        response.appendBody(string: "No event type header")
        return response.completed(status: .expectationFailed)
    }

    do {
        enum E: Error {
            case noPostBody
        }
        guard let bytes = request.postBodyBytes else {
            throw E.noPostBody
        }

        let data = Data(bytes: bytes)
        String(data: data, encoding: .utf8).map{ print($0) }

        let notificatable: Notificatable
        switch eventType {
        case "ping":
            notificatable = try JSONDecoder().decode(PingEvent.self, from: data)
        default:
            struct Oh: Notificatable {
                let title: String?
                let body = "Unknown event type"
            }
            notificatable = Oh(title: eventType)
        }

        let notificationItems: [APNSNotificationItem] = [
            .alertTitle(notificatable.title ?? "Error"),
            .alertBody(notificatable.body ?? "Error"),
        ]

        NotificationPusher(apnsTopic: apnsTopicId).pushAPNS(configurationName: apnsTopicId, deviceTokens: [token], notificationItems: notificationItems) { responses in
            print("APNs said:", responses)
        }
        print("Sent:", notificationItems)

        response.completed()

    } catch {
        response.appendBody(string: "\(error)")
        return response.completed(status: .expectationFailed)
    }
}
