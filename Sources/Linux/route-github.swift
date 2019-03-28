import PMKFoundation
import PerfectHTTP
import Foundation
import PromiseKit
import Roots
import APNs

func githubHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    guard let eventType = rq.header(.custom(name: "X-GitHub-Event")), let payload = rq.postBodyBytes.map(Data.init(_:)) else {
        response.completed(status: .expectationFailed)
        return
    }

    print()
    print("/github:", eventType, terminator: " ")

    func save(prefix: String) {
        Debris.save(json: payload, eventName: "\(prefix)-\(eventType)")
    }

    do {
        guard let event = Event(rawValue: eventType) else {
            throw Event.E.unimplemented(eventType)
        }
        let notificatable = try event.decode(from: payload)

        print(notificatable.title ?? "untitled")

        if let prefix = notificatable.saveNamePrefix {
            save(prefix: prefix)
        }

        guard !notificatable.shouldIgnore else {
            throw Event.E.ignoring
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

            try note.send(to: confs) { error in
                switch error {
                case .badToken(let token):
                    print("error: APNs: deleting bad-token:", token)
                    do {
                        try DB().delete(apnsDeviceToken: token)
                    } catch {
                        print("error:", error.legibleDescription)
                    }
                case .reason(let msg), .fundamental(let msg):
                    print("error: \(msg)")
                }
            }
        }

        func send(to: [APNSConfiguration: [String]]) throws {
            try send(notificatable: notificatable, to: to)
        }

        switch SendType(notificatable) {
        case .public(let repo):
            try send(to: db.apnsTokens(for: (repoId: repo.id, ignoreUserId: notificatable.senderUid, event: event)))
        case .private(let repo):

            let tokens = try db.tokens(for: (repoId: repo.id, ignoreUserId: notificatable.senderUid, event: event))

            for (oauthToken, foo) in tokens {
                DispatchQueue.global().async(.promise) {
                    switch foo.userId {
                    case 58962, 7132384, 24509830, 33223853, 33409294, 21280410, 9217605, 15271677:
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

      //// mxcl is interested
        if notificatable is PublicEvent {
            try send(to: db.mxcl())
        }

      //// if we’re a new branch prompt the user to create a pr
        if let note = notificatable as? CreateEvent, note.ref_type == .branch, let branch = note.ref, branch != "gh-pages" {

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

        if let ping = notificatable as? PingEvent {
            let node: Node, id: Int
            switch ping.context {
            case .organization(let org, _):
                node = .organization(org.login)
                id = org.id
            case .repository(let repo):
                id = repo.id
                node = .repository(repo.owner.login, repo.name)
            }

            try db.recordIfUnknown(hook: ping.hook.id, node: (node, id: id))
        }

        response.completed()

    } catch Event.E.unimplemented(let eventType) {
        print("unknown event")
        alert(message: "Unknown/unimplemented event type: \(eventType)")
        response.completed(status: .internalServerError)
        save(prefix: "unimplemented")
    } catch Event.E.ignoring {
        print("ignoring event")
        response.completed()
    } catch DB.E.oauthTokenNotFound {
        print("oauth-token not found but was required to do this particular operation")
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

    init(_ notificatable: Notificatable) {
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

func save(json: Data, eventName: String) {
    DispatchQueue.global(qos: .utility).async {
        do {
            let obj = try JSONSerialization.jsonObject(with: json)
            let data = try JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted)
            let dst = URL(fileURLWithPath: "../payloads/\(eventName).json")
            try data.write(to: dst, options: .atomic)
        } catch {
            print("save-payloads:", error)
        }
    }
}
