import PerfectNotifications
import PerfectHTTP
import Foundation

func githubHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    print("Receiving Webhook payload")

    guard let eventType = rq.header(.custom(name: "X-GitHub-Event")) else {
        response.appendBody(string: "No event type header")
        return response.completed(status: .expectationFailed)
    }

    do {
        let notificatable: Notificatable

        switch eventType {
        case "ping":
            notificatable = try rq.decode(PingEvent.self)
        case "push":
            notificatable = try rq.decode(PushEvent.self)
        case "check_run":
            notificatable = try rq.decode(CheckRunEvent.self)
        case "check_suite":
            notificatable = try rq.decode(CheckSuiteEvent.self)
        case "commit_comment":
            notificatable = try rq.decode(CommitComment.self)
        case "create":
            notificatable = try rq.decode(CreateEvent.self)
        case "delete":
            notificatable = try rq.decode(DeleteEvent.self)
        case "deployment":
            notificatable = try rq.decode(DeploymentEvent.self)
        case "deployment_status":
            notificatable = try rq.decode(DeploymentStatusEvent.self)
        case "fork":
            notificatable = try rq.decode(ForkEvent.self)
        case "gollum":
            notificatable = try rq.decode(GollumEvent.self)
        case "issue_comment":
            notificatable = try rq.decode(IssueCommentEvent.self)
        case "issues":
            notificatable = try rq.decode(IssuesEvent.self)
        case "label":
            notificatable = try rq.decode(LabelEvent.self)
        case "member":
            notificatable = try rq.decode(MemberEvent.self)
        case "membership":
            notificatable = try rq.decode(MembershipEvent.self)
        case "milestone":
            notificatable = try rq.decode(MilestoneEvent.self)
        case "organization":
            notificatable = try rq.decode(OrganizationEvent.self)
        case "org_block":
            notificatable = try rq.decode(OrgBlockEvent.self)
        case "page_build":
            notificatable = try rq.decode(PageBuildEvent.self)
        case "pull_request":
            notificatable = try rq.decode(PullRequestEvent.self)
        case "pull_request_review":
            notificatable = try rq.decode(PullRequestEvent.self)
        case "watch":
            notificatable = try rq.decode(WatchEvent.self)
        case "status":
            notificatable = try rq.decode(StatusEvent.self)
        case "marketplace_purchase", "project_card", "project_column", "project", "public", "pull_request_review_comment", "release", "repository", "repository_vulnerability_alert", "team", "team_add":
            print("Unimplemented event:", eventType)
            fallthrough
        default:
            struct Oh: Notificatable {
                let title: String?
                let body = "Unknown event type"
                let context = Context.alert
            }
            notificatable = Oh(title: eventType)
        }

        let tokens = UserDefaults.standard.tokens(for: notificatable.context)

        var notificationItems: [APNSNotificationItem] = [
            .alertBody(notificatable.body)
        ]
        if let title = notificatable.title {
            notificationItems.append(.alertTitle(title))
        }
        if let url = notificatable.url {
            notificationItems.append(.customPayload("url", url.absoluteString))
        }

        for (topic, tokens) in tokens {
            let pusher = NotificationPusher(apnsTopic: topic)
            pusher.pushAPNS(configurationName: NotificationPusher.confName, deviceTokens: tokens, notificationItems: notificationItems) { responses in
                print("APNs said:", responses)
            }
        }
        print("Sent to \(tokens.flatMap{ $0.1 }.count) tokens:", notificationItems)

        response.completed()

    } catch {
        response.appendBody(string: "\(error)")
        return response.completed(status: .expectationFailed)
    }
}
