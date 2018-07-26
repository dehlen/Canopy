import PerfectHTTP
import Foundation
import PromiseKit

func subscriptionsHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    print()
    print("/subscribe")
    
    guard let token = rq.header(.custom(name: "Authorization")) else {
        return response.completed(status: .badRequest)
    }
    firstly {
        GitHubAPI(oauthToken: token).me()
    }.done {
        let foo = try DB().subscriptions(forUserId: $0.id)
        let data = try JSONEncoder().encode(foo)
        response.appendBody(bytes: [UInt8](data))
        response.completed()
    }.catch { error in
        response.appendBody(string: "\(error)")
        response.completed(status: .internalServerError)
    }
}

func subscribeHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
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
    fatalError()
}
