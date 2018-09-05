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
        var rejects: [Node] = []
        for (result, node) in zip(results, rq.nodes) {
            switch result {
            case .fulfilled(let repoId):
                fulfills.append(repoId)
            case .rejected:
                rejects.append(node)
            }
        }
        try DB().add(subscriptions: fulfills, userId: userId)
        guard rejects.isEmpty else {
            throw API.Enroll.Error.noClearance(rejects)
        }
    }

    return firstly {
        api.me()
    }.then { me in
        when(resolved: try rq.repos.map(verify)).done {
            try saveEnrollments($0, userId: me.id)
        }
    }.then {
        api.createHooks(for: rq.nodes)  //NOTE also saves to db!
    }.done { results in
        var rejects: [Node] = []
        for (result, node) in zip(results, rq.nodes) {
            if case .rejected = result {
                rejects.append(node)
            }
        }
        guard rejects.isEmpty else {
            throw API.Enroll.Error.hookCreationFailed(rejects)
        }
    }
}

private extension GitHubAPI {
    func createHooks(for nodes: [Node]) -> Guarantee<[Result<Node>]> {
        let promises = nodes.map{ node in createHook(for: node).map{ node } }
        return when(resolved: promises)
    }
}
