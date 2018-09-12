import PerfectHTTP
import Foundation
import PromiseKit
import Roots

func enrollHandler(request rq: HTTPRequest) throws -> Promise<Void> {
    guard let token = rq.header(.authorization) else {
        throw HTTPResponseError(status: .unauthorized, description: "")
    }
    let rq = try rq.decode(API.Enroll.self)
    let api = GitHubAPI(oauthToken: token)

    var lookup = [Int: Node]()

    /// first verify user *really* has permission to “read” this repo
    func verify(repoId: Int) throws -> Promise<Int> {

        struct Repo: Decodable {
            let id: Int
            let name: String
            let owner: Owner
            struct Owner: Decodable {
                let id: Int
                let login: String
                let type: Type_
                enum Type_: String, Decodable {
                    case organization = "Organization"
                    case user = "User"
                }
            }
        }

        //TODO Node or the API should take hook-ids too since
        // this is just stupid. Then we could just HEAD request
        // again.

        let rq = api.request(path: "/repositories/\(repoId)")
        return firstly {
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.map {
            try JSONDecoder().decode(Repo.self, from: $0.data)
        }.get { repo in
            precondition(repo.id == repoId)

            switch repo.owner.type {
            case .organization:
                lookup[repo.owner.id] = .organization(repo.owner.login)
            case .user:
                lookup[repo.id] = .repository(repo.owner.login, repo.name)
            }
        }.map {
            $0.id
        }
    }

    func saveEnrollments(_ results: [Result<Int>], userId: Int) throws {
        var fulfills: [Int] = []
        var rejects: [Int] = []
        for (result, repoId) in zip(results, rq.enrollRepoIds) {
            switch result {
            case .fulfilled(let repoId):
                fulfills.append(repoId)
            case .rejected:
                rejects.append(repoId)
            }
        }
        try DB().add(subscriptions: fulfills, userId: userId)
        guard rejects.isEmpty else {
            throw API.Enroll.Error.noClearance(repoIds: rejects)
        }
    }

    return firstly {
        api.me()
    }.then { me in
        when(resolved: try rq.enrollRepoIds.map(verify)).done {
            try saveEnrollments($0, userId: me.id)
        }
    }.then {
        api.createHooks(for: rq.createHooks)
    }.done { results in

        //TODO if we knew if the user was admin we could only attempt to hook
        // those, if already hooked that is; the reason we are going to reattempt
        // hooks we know exist is in-case the hook was deleted and we didn't know
        // about it, thus the support story is: opt-out then back in to enrollment
        // which is easy and something the user may well attempt anyway
        let previouslyHooked = Set(try DB().whichAreHooked(ids: lookup.keys).map{ lookup[$0]! })

        var rejects: [Node] = []
        for (result, node) in zip(results, rq.createHooks) {
            if case .rejected = result, !previouslyHooked.contains(node) {
                rejects.append(node)
            }
        }
        guard rejects.isEmpty else {
            throw API.Enroll.Error.hookCreationFailed(rejects)
        }
    }
}

func unenrollHandler(request rq: HTTPRequest) throws -> Promise<Void> {

    guard let token = rq.header(.authorization) else {
        throw HTTPResponseError(status: .unauthorized, description: "")
    }

    // we don’t remove the webhooks
    // NOTE we should probably tell the user that? Or offer the chance to do that too.

    return firstly {
        GitHubAPI(oauthToken: token).me()
    }.done {
        let repos = try rq.decode(API.Unenroll.self).repoIds
        try DB().delete(subscriptions: repos, userId: $0.id)
    }
}

private extension GitHubAPI {
    func createHooks(for nodes: [Node]) -> Guarantee<[Result<Node>]> {
        func mapper(node: Node) -> Promise<Node> {
            return createHook(for: node).recover { error in
                guard case PMKHTTPError.badStatusCode(422, _, _) = error else {
                    // ^^ hook already exists ∴ ignore error
                    throw error
                }
            }.map { _ in
                node
            }
        }
        return when(resolved: nodes.map(mapper))
    }
}
