import PerfectHTTP
import Foundation
import PromiseKit
import Roots

private enum E: Error {
    case unimplemented(String)
    case ignoring
}

func githubHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    guard let eventType = rq.header(.custom(name: "X-GitHub-Event")) else {
        alert(message: "No event type provided by GitHub!")
        response.completed(status: .expectationFailed)
        return
    }

    print()
    print("/github:", eventType, terminator: " ")

    func save(prefix: String) {
        guard let bytes = rq.postBodyBytes else { return }
        Debris.save(json: Data(bytes), eventName: "\(prefix)-\(eventType)")
    }

    do {
        let notificatable = try rq.decodeNotificatable(eventType: eventType)

        print(notificatable.title ?? "untitled")

        if let prefix = notificatable.saveNamePrefix {
            save(prefix: prefix)
        }

        guard !notificatable.shouldIgnore else {
            throw E.ignoring
        }

        let db = try DB()

        let id = rq.header(.custom(name: "X-GitHub-Delivery"))

        func send(notificatable: Notificatable, to confs: [APNSConfiguration: [String]]) throws {
            let note = APNsNotification.alert(
                body: notificatable.body,
                title: notificatable.title,
                subtitle: notificatable.subtitle,
                category: eventType,
                threadId: notificatable.threadingId,
                extra: notificatable.url.map{ ["url": $0.absoluteString] },
                id: id,
                collapseId: notificatable.collapseId)
            try note.send(to: confs)
        }

        func send(to: [APNSConfiguration: [String]]) throws {
            try send(notificatable: notificatable, to: to)
        }

        switch SendType(notificatable) {
        case .broadcast(let repo):
            try send(to: db.mxcl())
            fallthrough
        case .public(let repo):
            try send(to: db.apnsTokens(for: (repoId: repo.id, ignoreUserId: notificatable.senderUid)))
        case .private(let repo):

            let tokens = try db.tokens(for: (repoId: repo.id, ignoreUserId: notificatable.senderUid))

            for (oauthToken, foo) in tokens {
                DispatchQueue.global().async(.promise) {
                    switch foo.userId {
                    case 58962, 7132384, 24509830, 33223853, 33409294:
                        //mxcl, aleshia, laurie,   akash,    ernesto
                        return
                    default:
                        guard try db.isReceiptValid(forUserId: foo.userId) else {
                            throw PMKError.cancelled
                        }
                    }
                }.then {
                    GitHubAPI(oauthToken: oauthToken).hasClearance(for: repo)
                }.done { cleared in
                    if cleared {
                        try send(to: foo.confs)
                    } else {
                        print("No clearance! Deleting token for:", foo.userId)
                        try db.delete(subscription: repo.id, userId: foo.userId)
                    }
                }.catch {
                    alert(message: $0.legibleDescription)
                }
            }
        case .organization(let org, let admin):
            let oauthToken = try db.oauthToken(forUser: admin.id)
            firstly {
                GitHubAPI(oauthToken: oauthToken).members(for: org)
            }.map {
                try db.apnsTokens(forUserIds: $0 - [notificatable.senderUid])
            }.done {
                try send(to: $0)
            }.catch {
                alert(message: $0.legibleDescription)
            }
        }

      //// if we’re a new branch prompt the user to create a pr
        if let note = notificatable as? CreateEvent, note.ref_type == .branch, let branch = note.ref {

            struct CreatePR: Notificatable {
                let branch: String
                let repo: Repository
                var context: Context { return .repository(repo) }
                let senderUid = 0 //unused here
                var subtitle: String? { return "You pushed “\(branch)”" }
                let body = "Tap to create pull request"
                var url: URL? { return URL(string: "https://github.com/\(repo.full_name)/pull/new/\(branch)") }
                var collapseId: String? { return repo.full_name + "/create-pr" }
            }

            let pr = CreatePR(branch: branch, repo: note.repository)
            let confs = try db.apnsTokens(forUserIds: [note.senderUid])
            try send(notificatable: pr, to: confs)
        }

        response.completed()

    } catch E.unimplemented(let eventType) {
        print("unknown event")
        alert(message: "Unknown/unimplemented event type: \(eventType)")
        response.completed(status: .internalServerError)
        save(prefix: "unimplemented")
    } catch E.ignoring {
        print("ignoring event")
        response.completed()
    } catch DB.E.oauthTokenNotFound {
        print("no oauth-token not found which was required to do this particular operation")
        // user signed out presumably
        response.completed(status: .unauthorized)
    } catch {
        print(error.legibleDescription)
        alert(message: error.legibleDescription)
        response.appendBody(string: error.legibleDescription)
        response.completed(status: .expectationFailed)
        save(prefix: "error")
    }
}

private extension HTTPRequest {
    func decodeNotificatable(eventType: String) throws -> Notificatable {
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
        case "release":
            return try rq.decode(ReleaseEvent.self)
        case "repository":
            return try rq.decode(RepositoryEvent.self)
        case "status":
            // HEAVY TRAFFIC DUDE! Probably send as a silent notification
            // happens for eg. EVERY SINGLE travis build job
            throw E.ignoring
        case "watch":
            return try rq.decode(WatchEvent.self)
        case "pull_request_review_comment":
            return try rq.decode(PullRequestReviewCommentEvent.self)
        case "team":
            return try rq.decode(TeamEvent.self)
        case "team_add":
            return try rq.decode(TeamAddEvent.self)
        case "repository_vulnerability_alert":
            return try rq.decode(RepositoryVulnerabilityEvent.self)
        case "marketplace_purchase", _:
            throw E.unimplemented(eventType)
        }
    }
}

/// checks if user has access to information about this private repository
/// if so, send APNs, if not, delete the subscription
private extension GitHubAPI {

    private func _wrap(type: String, id: Int) -> Promise<Bool> {
        var rq = request(path: "/\(type)/\(id)")
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

    func hasClearance(for repo: Repository) -> Promise<Bool> {
        return _wrap(type: "repositories", id: repo.id)
    }

    func hasClearance(for org: Organization) -> Promise<Bool> {
        return _wrap(type: "organizations", id: org.id)
    }

    func members(for org: Organization) -> Promise<[Int]> {
        let q = DispatchQueue(label: #file + #function)
        struct Response: Decodable {
            let id: Int
        }
        var ids: [Int] = []
        return task(path: "/orgs/\(org.login)/members") { data in
            DispatchQueue.global().async(.promise) {
                try JSONDecoder().decode([Response].self, from: data)
            }.done(on: q) {
                ids.append(contentsOf: $0.map(\.id))
            }
        }.map {
            ids
        }
    }
}

private enum SendType {
    case `public`(Repository)
    case `private`(Repository)
    case organization(Organization, admin: User)
    case broadcast(Repository)

    init(_ notificatable: Notificatable) {
        if let publicEvent = notificatable as? PublicEvent {
            self = .broadcast(publicEvent.repository)
        } else {
            switch notificatable.context {
            case .repository(let repo) where repo.private:
                self = .private(repo)
            case .repository(let repo):
                self = .public(repo)
            case .organization(let org, let admin):
                self = .organization(org, admin: admin)
            }
        }
    }
}


func save(json: Data, eventName: String) {

    func go() {
        do {
            let obj = try JSONSerialization.jsonObject(with: json)
            let data = try JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted)
            let dst = URL(fileURLWithPath: "../payloads/\(eventName).json")
            try data.write(to: dst, options: .atomic)
        } catch {
            print("save-payloads:", error)
        }
    }

    DispatchQueue.global(qos: .utility).async(execute: go)
}
