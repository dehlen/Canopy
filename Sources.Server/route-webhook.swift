import PerfectNotifications
import PerfectHTTP
import Foundation
import PromiseKit
import Roots

private enum E: Error {
    case noEventType
    case unimplemented(String)
    case ignoring(String?)
}

func githubHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    print()
    print("/github")

    do {
        let notificatable = try rq.decodeNotificatable()

        var notificationItems: [APNSNotificationItem] = [
            .alertBody(notificatable.body),
            .threadId(notificatable.threadingId)
        ]
        if let title = notificatable.title {
            notificationItems.append(.alertTitle(title))
        }
        if let url = notificatable.url {
            notificationItems.append(.customPayload("url", url.absoluteString))
        }

        let confs: [APNSConfiguration: [String]]

        if notificatable is PublicEvent {
            // TELL EVERYBODY!
            confs = try DB().allAPNsTokens()
        } else {
            switch notificatable.context {
            case .repository(let repo):
                confs = try DB().apnsTokens(for: repo.id)
            case .organization:
            #if swift(>=4.1.5)
                #warning("FIXME BEFORE PRODUCTION!")
            #endif
                confs = try DB().mxcl()
            }
        }

        print("sending:", notificatable.body)
        for (apnsConfiguration, tokens) in confs {
            apnsConfiguration.send(notificationItems, to: tokens)
        }

        response.completed()

    } catch E.unimplemented(let eventType) {
        alert(message: "Unknown/unimplemented event type: \(eventType)")
        response.completed(status: .internalServerError)
    } catch E.noEventType {
        alert(message: "No event type provided by GitHub!")
        response.completed(status: .expectationFailed)
    } catch E.ignoring(let body) {
        if let body = body {
            print(body)
        }
        response.completed()
    } catch {
        alert(message: error.legibleDescription)
        response.appendBody(string: error.legibleDescription)
        response.completed(status: .expectationFailed)
    }
}

private extension HTTPRequest {
    func decodeNotificatable() throws -> Notificatable {
        let rq = self

        guard let eventType = rq.header(.custom(name: "X-GitHub-Event")) else {
            throw E.noEventType
        }

        switch eventType {
        case "ping":
            return try rq.decode(PingEvent.self)
        case "push":
            return try rq.decode(PushEvent.self)
        case "check_run":
            return try rq.decode(CheckRunEvent.self)
        case "check_suite":
            return try rq.decode(CheckSuiteEvent.self)
        case "commit_comment":
            return try rq.decode(CommitComment.self)
        case "create":
            return try rq.decode(CreateEvent.self)
        case "delete":
            return try rq.decode(DeleteEvent.self)
        case "deployment":
            return try rq.decode(DeploymentEvent.self)
        case "deployment_status":
            return try rq.decode(DeploymentStatusEvent.self)
        case "fork":
            return try rq.decode(ForkEvent.self)
        case "gollum":
            return try rq.decode(GollumEvent.self)
        case "issue_comment":
            return try rq.decode(IssueCommentEvent.self)
        case "issues":
            return try rq.decode(IssuesEvent.self)
        case "label":
            return try rq.decode(LabelEvent.self)
        case "member":
            return try rq.decode(MemberEvent.self)
        case "membership":
            return try rq.decode(MembershipEvent.self)
        case "milestone":
            return try rq.decode(MilestoneEvent.self)
        case "organization":
            return try rq.decode(OrganizationEvent.self)
        case "org_block":
            return try rq.decode(OrgBlockEvent.self)
        case "page_build":
            return try rq.decode(PageBuildEvent.self)
        case "project_card":
            return try rq.decode(ProjectCardEvent.self)
        case "project_column":
            return try rq.decode(ProjectColumnEvent.self)
        case "project":
            return try rq.decode(ProjectEvent.self)
        case "public":
            return try rq.decode(PublicEvent.self)
        case "pull_request":
            return try rq.decode(PullRequestEvent.self)
        case "pull_request_review":
            return try rq.decode(PullRequestEvent.self)
        case "watch":
            return try rq.decode(WatchEvent.self)
        case "release":
            return try rq.decode(ReleaseEvent.self)
        case "status":
            // HEAVY TRAFFIC DUDE! Probably send as a silent notification
            // happens for eg. EVERY SINGLE travis build job
            throw E.ignoring(rq.postBodyString)
        case "pull_request_review_comment":
            return try rq.decode(PullRequestReviewCommentEvent.self)
        case "marketplace_purchase", "repository", "repository_vulnerability_alert", "team", "team_add", _:
            throw E.unimplemented(eventType)
        }
    }
}

/// checks if user has access to information about this private repository
/// if so, send APNs, if not, delete the subscription
func security(repo repoId: Int, user userId: Int) -> Promise<Bool> {

    func check(with token: String) -> Promise<Bool> {
        var rq = GitHubAPI(oauthToken: token).request(path: "/repos/\(repoId)")
        rq.httpMethod = "HEAD"
        return firstly {
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.map(on: nil) { _ in
            true
        }.recover { error -> Promise<Bool> in
            if case PMKHTTPError.badStatusCode(404, _, _) = error {
                return .value(false)
            } else {
                throw error
            }
        }
    }

    return DispatchQueue.global().async(.promise) {
        try DB().oauthToken(user: userId)
    }.then {
        check(with: $0)
    }
}
