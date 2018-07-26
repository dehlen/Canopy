import PerfectNotifications
import PerfectHTTP
import Foundation

func githubHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    print()
    print("/github")

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
            // HEAVY TRAFFIC DUDE! Probably send as a silent notification
            //let status = try rq.decode(StatusEvent.self)
            if let body = rq.postBodyString {
                print(body)
            }
            return
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

        let tokens: [APNSConfiguration: [String]]
        switch notificatable.context {
        case .repository(id: let id):
            tokens = try DB().tokens(for: id)
        default:
        #if swift(>=4.1.5)
            #warning("FIXME BEFORE PRODUCTION!")
        #endif
            tokens = try DB().mxcl().mapValues{ [$0] }
        }

        var notificationItems: [APNSNotificationItem] = [
            .alertBody(notificatable.body)
        ]
        if let title = notificatable.title {
            notificationItems.append(.alertTitle(title))
        }
        if let url = notificatable.url {
            notificationItems.append(.customPayload("url", url.absoluteString))
        }
        if let threadingId = notificatable.threadingId {
            notificationItems.append(.threadId(threadingId))
        }

        print("sending:", notificatable.body)

        for (apnsConfiguration, tokens) in tokens {
            let pusher = NotificationPusher(apnsTopic: apnsConfiguration.topic)
            pusher.expiration = .relative(30)
            let confname = apnsConfiguration.isProduction
                ? NotificationPusher.productionConfigurationName
                : NotificationPusher.sandboxConfigurationName

            print("sent to:", tokens.count, "tokens to production:", apnsConfiguration.isProduction, "(\(apnsConfiguration.topic))")

            pusher.pushAPNS(configurationName: confname, deviceTokens: tokens, notificationItems: notificationItems) { responses in
                for (index, response) in responses.enumerated() {
                    do {
                        let token = tokens[index]
                        switch response.status {
                        case .ok:    //200
                            continue
                        case .badRequest:  //400
                            if response.jsonObjectBody["reason"] as? String == "BadDeviceToken" {
                                fallthrough
                            }
                        case .gone:        //410
                            print("Deleting token due to \(response.status)")
                            try DB().delete(token: tokens[index])
                        default:
                            print("APNs:", response, token)
                        }
                    } catch {
                        print(#function, error)
                    }
                }
            }
        }

        response.completed()

    } catch {
        response.appendBody(string: "\(error)")
        return response.completed(status: .expectationFailed)
    }
}
