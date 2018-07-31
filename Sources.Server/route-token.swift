import enum PerfectSQLite.SQLiteError
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
    }.done {
        response.completed()
    }.catch {
        response.appendBody(string: $0.legibleDescription)
        response.completed(status: .badGateway)
    }
}

func updateTokens(with body: TokenUpdate) -> Promise<Void> {
    return firstly {
        GitHubAPI(oauthToken: body.oauthToken).me()
    }.done { me in
        let db = try DB()
        try db.add(apnsToken: body.deviceToken, topic: body.apnsTopic, userId: me.id, production: body.production)
        try db.add(oauthToken: body.oauthToken, userId: me.id)
    }.recover { error in
        // code 19 means UNIQUE violation, so we already have this, which is fine
        guard case PerfectSQLite.SQLiteError.Error(let code, _) = error, code == 19 else {
            throw error
        }
    }
}
