import enum PerfectSQLite.SQLiteError
import LegibleError
import PerfectHTTP
import Foundation
import PromiseKit
import Roots

func updateTokensHandler(request: HTTPRequest, response: HTTPResponse) {
    print()
    print("/token")

    DispatchQueue.global().async(.promise) {
        try request.decode(TokenUpdate.self)
    }.then {
        updateTokens(with: $0)
    }.done { _ in
        response.completed()
    }.catch {
        response.appendBody(string: $0.legibleDescription)
        if $0 is SQLiteError {
            response.completed(status: .internalServerError)
        } else {
            response.completed(status: .badRequest)
        }
    }
}

func deleteTokenHandler(request: HTTPRequest, response: HTTPResponse) {
    do {
        // we don't require auth, since that makes the state machine more error-prone
        // and if you know the token, then well, good for you
        if let token = request.postBodyString {
            try DB().delete(apnsDeviceToken: token)
            response.completed()
        } else {
            response.completed(status: .badRequest)
        }
    } catch {
        response.completed(status: .badRequest)
    }
}

func updateTokens(with body: TokenUpdate) -> Promise<String> {
    return firstly {
        GitHubAPI(oauthToken: body.oauthToken).me()
    }.map { me -> String in
        let db = try DB()
        try db.add(apnsToken: body.deviceToken, topic: body.apnsTopic, userId: me.id, production: body.production)
        try db.add(oauthToken: body.oauthToken, userId: me.id)
        return me.login
    }
}
