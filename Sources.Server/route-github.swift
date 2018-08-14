import PerfectNotifications
import PerfectHTTP
import Foundation
import PromiseKit
import Roots

private enum E: Error {
    case noEventType
    case unimplemented(String)
    case ignoring
}

func githubHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    print()
    print("/github")

    do {
        let (eventType, notificatable) = try rq.decodeNotificatable()

        print(type(of: notificatable))

        guard !notificatable.shouldIgnore else {
            throw E.ignoring
        }

        var notificationItems: [APNSNotificationItem] = [
            .alertBody(notificatable.body),
            .threadId(notificatable.threadingId),
            .category(eventType)
        ]
        if let title = notificatable.title {
            notificationItems.append(.alertTitle(title))
        }
        if let url = notificatable.url {
            notificationItems.append(.customPayload("url", url.absoluteString))
        }

        func send(to confs: [APNSConfiguration: [String]]) {
            print("sending:", notificatable.body)
            for (apnsConfiguration, tokens) in confs {
                apnsConfiguration.send(notificationItems, to: tokens)
            }
        }

        switch SendType(notificatable) {
        case .broadcast:
            send(to: try DB().allAPNsTokens())
        case .private(let repo):
            // maybe this looks less efficient, but actually apns only
            // accepts one device-token at a time anyway
            // However, it would be nice if we could avoid these checks
            // in theory we could just use webhooks to know when to remove
            // user-access to repos

            let db = try DB()

            print("checking clearances & receipts for private repo:", repo.full_name)
            let tokens = try db.tokens(forRepoId: repo.id)
            print("got:", tokens.count, "tokens")

            for (oauthToken, foo) in tokens {
                DispatchQueue.global().async(.promise) {
                    guard try db.isReceiptValid(forUserId: foo.userId) else { throw PMKError.cancelled }
                }.then {
                    GitHubAPI(oauthToken: oauthToken).hasClearance(for: repo.id)
                }.done { cleared in
                    if cleared {
                        send(to: foo.confs)
                    } else {
                        print("No clearance!")
                        try db.delete(subscription: repo.id, userId: foo.userId)
                    }
                }.catch {
                    alert(message: $0.legibleDescription)
                }
            }
        case .public(let repo):
            send(to: try DB().apnsTokens(for: repo.id))
        case .organization:
        #if swift(>=4.1.5)
            #warning("FIXME BEFORE PRODUCTION!")
        #endif
            send(to: try DB().mxcl())
        }

        //github say we should do this sooner
        response.completed()

    } catch E.unimplemented(let eventType) {
        alert(message: "Unknown/unimplemented event type: \(eventType)")
        response.completed(status: .internalServerError)
    } catch E.noEventType {
        alert(message: "No event type provided by GitHub!")
        response.completed(status: .expectationFailed)
    } catch E.ignoring {
        print("Ignoring status event")
        response.completed()
    } catch {
        alert(message: error.legibleDescription)
        response.appendBody(string: error.legibleDescription)
        response.completed(status: .expectationFailed)
    }
}

private extension HTTPRequest {
    func decodeNotificatable() throws -> (eventType: String, Notificatable) {
        guard let eventType = header(.custom(name: "X-GitHub-Event")) else {
            throw E.noEventType
        }
        return (eventType, try _decode(eventType: eventType))
    }

    private func _decode(eventType: String) throws -> Notificatable {
        let rq = self
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
            return try rq.decode(PullRequestReviewEvent.self)
        case "watch":
            return try rq.decode(WatchEvent.self)
        case "release":
            return try rq.decode(ReleaseEvent.self)
        case "status":
            // HEAVY TRAFFIC DUDE! Probably send as a silent notification
            // happens for eg. EVERY SINGLE travis build job
            throw E.ignoring
        case "pull_request_review_comment":
            return try rq.decode(PullRequestReviewCommentEvent.self)
        case "marketplace_purchase", "repository", "repository_vulnerability_alert", "team", "team_add", _:
            throw E.unimplemented(eventType)
        }
    }
}

/// checks if user has access to information about this private repository
/// if so, send APNs, if not, delete the subscription
private extension GitHubAPI {
    func hasClearance(for repoId: Int) -> Promise<Bool> {
        var rq = request(path: "/repositories/\(repoId)")
        rq.httpMethod = "HEAD"
        return firstly {
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.map(on: nil) { _ in
            true
        }.recover { error -> Promise<Bool> in
            print(error)
            if case PMKHTTPError.badStatusCode(404, _, _) = error {
                return .value(false)
            } else {
                throw error
            }
        }
    }
}

private enum SendType {
    case `public`(Repository)
    case `private`(Repository)
    case organization(User)
    case broadcast

    init(_ notificatable: Notificatable) {
        if notificatable is PublicEvent {
            // TELL EVERYBODY!
            self = .broadcast
        } else {
            switch notificatable.context {
            case .repository(let repo) where repo.private:
                self = .private(repo)
            case .repository(let repo):
                self = .public(repo)
            case .organization(let org):
                self = .organization(org)
            }
        }
    }
}
