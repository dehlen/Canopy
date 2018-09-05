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

    /// first verify user *really* has permission to “read” this repo
    func verify(repoId: Int) throws -> Promise<Int> {
        var rq = api.request(path: "/repositories/\(repoId)")
        rq.httpMethod = "HEAD"  // less data thanks
        return firstly {
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.map { _ in
            repoId
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
        api.createHooks(for: rq.createHooks)  //NOTE also saves to db!
    }.done { results in
        var rejects: [Node] = []
        for (result, node) in zip(results, rq.createHooks) {
            if case .rejected = result {
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
                    // ^^ hook already exists
                    throw error
                }
            }.map { _ in
                node
            }
        }
        return when(resolved: nodes.map(mapper))
    }
}
