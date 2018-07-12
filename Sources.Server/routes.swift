import PerfectNotifications
import PerfectHTTP
import Foundation

var routes: Routes {
    var routes = Routes()
    routes.add(method: .post, uri: "/token", handler: tokenHandler)
    routes.add(method: .post, uri: "/github", handler: githubHandler)
    return routes
}

private var tokens: Set<String> {
    set {
        UserDefaults.standard.set(Array(newValue), forKey: "tokens")
    }
    get {
        return Set(UserDefaults.standard.stringArray(forKey: "tokens") ?? [])
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
        let token = try JSONDecoder().decode(Response.self, from: data).token
        if tokens.insert(token).inserted {
            response.appendBody(string: "new token added: \(String(describing: token))")
        } else {
            response.appendBody(string: "already knew this token, kthxbai")
        }
        response.completed()
    } catch {
        response.appendBody(string: "error: \(error)")
        response.completed(status: .badRequest)
    }
}

private func githubHandler(request: HTTPRequest, _ response: HTTPResponse) {
    print("Receiving Webhook payload")

    let tokens = gitbell.tokens

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

        func decode<T>(_ t: T.Type) throws -> T where T: Decodable {
            return try JSONDecoder().decode(T.self, from: data)
        }

        let notificatable: Notificatable
        switch eventType {
        case "ping":
            notificatable = try decode(PingEvent.self)
        case "push":
            notificatable = try decode(PushEvent.self)
        case "check_run":
            notificatable = try decode(CheckRunEvent.self)
        case "check_suite":
            notificatable = try decode(CheckSuiteEvent.self)
        case "commit_comment":
            notificatable = try decode(CommitComment.self)
        case "create":
            notificatable = try decode(CreateEvent.self)
        case "delete":
            notificatable = try decode(DeleteEvent.self)
        case "deployment":
            notificatable = try decode(DeploymentEvent.self)
        case "deployment_status":
            notificatable = try decode(DeploymentStatusEvent.self)
        case "fork":
            notificatable = try decode(ForkEvent.self)
        case "gollum":
            notificatable = try decode(GollumEvent.self)
        case "installation":
            notificatable = try decode(InstallationEvent.self)
        case "installation_repositories":
            notificatable = try decode(InstallationRepositoriesEvent.self)
        case "issue_comment":
            notificatable = try decode(IssueCommentEvent.self)
        case "issues":
            notificatable = try decode(IssuesEvent.self)
        case "label":
            notificatable = try decode(LabelEvent.self)
        case "member":
            notificatable = try decode(MemberEvent.self)
        case "membership":
            notificatable = try decode(MembershipEvent.self)
        case "milestone":
            notificatable = try decode(MilestoneEvent.self)
        case "organization":
            notificatable = try decode(OrganizationEvent.self)
        case "org_block":
            notificatable = try decode(OrgBlockEvent.self)
        case "page_build":
            notificatable = try decode(PageBuildEvent.self)
        case "watch":
            notificatable = try decode(WatchEvent.self)
        case "marketplace_purchase", "project_card", "project_column", "project", "public", "pull_request", "pull_request_review", "pull_request_review_comment", "release", "repository", "repository_vulnerability_alert", "status", "team", "team_add":
            print("Unimplemented event:", eventType)
            fallthrough
        default:
            struct Oh: Notificatable {
                let title: String?
                let body = "Unknown event type"
            }
            notificatable = Oh(title: eventType)
        }

        var notificationItems: [APNSNotificationItem] = [
            .alertTitle(notificatable.title ?? "Error"),
            .alertBody(notificatable.body ?? "Error"),
        ]

        if let url = notificatable.url {
            notificationItems.append(.customPayload("url", url.absoluteString))
        }

        NotificationPusher(apnsTopic: apnsTopicId).pushAPNS(configurationName: apnsTopicId, deviceTokens: Array(tokens), notificationItems: notificationItems) { responses in
            print("APNs said:", responses)
        }
        print("Sent:", notificationItems)

        response.completed()

    } catch {
        response.appendBody(string: "\(error)")
        return response.completed(status: .expectationFailed)
    }
}
