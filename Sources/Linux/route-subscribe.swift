import PerfectHTTP
import Foundation
import PromiseKit
import Roots

func subscriptionsHandler(request rq: HTTPRequest) throws -> Promise<Routes.Response<[Int]>> {
    guard let token = rq.header(.custom(name: "Authorization")) else {
        throw HTTPResponseError(status: .badRequest, description: "")
    }
    return firstly {
        GitHubAPI(oauthToken: token).me()
    }.map { user -> Routes.Response<[Int]> in
        let db = try DB()
        let enrollments = try db.subscriptions(forUserId: user.id)
        let hasReceipt = try db.isReceiptValid(forUserId: user.id)
        return .init(codable: enrollments, headers: [
            .upgrade: hasReceipt ? "true" : "false"
        ])
    }
}


//NOTE the following pair of routes are unused (in app) since 1.0.1

func subscribeHandler(request rq: HTTPRequest, _ response: HTTPResponse) {

    //NOTE we don't check if user has receipt, they can sub to
    // stuff without one, we just won't deliver their notifications.
    // we allow sub’ing so they can state what they want, though they
    // cannot yet get.

    guard let token = rq.header(.authorization) else {
        return response.completed(status: .badRequest)
    }
    do {
        let subs = try rq.decode([Int].self)
        let api = GitHubAPI(oauthToken: token)
        let rqs = subs.map { id -> URLRequest in
            var rq = api.request(path: "/repositories/\(id)")
            rq.httpMethod = "HEAD"  // less data thanks
            return rq
        }
        when(fulfilled: rqs.map { rq in
            URLSession.shared.dataTask(.promise, with: rq).validate()
            // ^^ first verify user *really* has permission to “read” this repo
        }).then { _ in
            api.me()
        }.done { me in
            try DB().add(subscriptions: subs, userId: me.id)
            response.completed()
        }.catch { error in
            response.appendBody(string: "\(error)")
            response.completed(status: .expectationFailed)
        }
    } catch {
        response.appendBody(string: "\(error)")
        response.completed(status: .badRequest)
    }
}

func unsubscribeHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    guard let token = rq.header(.authorization) else {
        return response.completed(status: .badRequest)
    }
    do {
        let subs = try rq.decode([Int].self)
        firstly {
            GitHubAPI(oauthToken: token).me()
        }.done {
            try DB().delete(subscriptions: subs, userId: $0.id)
            response.completed()
        }.catch { error in
            response.appendBody(string: error.legibleDescription)
            response.completed(status: .badRequest)
        }
    } catch {
        response.appendBody(string: error.legibleDescription)
        response.completed(status: .badRequest)
    }
}
