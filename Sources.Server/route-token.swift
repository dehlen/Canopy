import enum PerfectSQLite.SQLiteError
import PerfectHTTP
import Foundation
import PromiseKit

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
        try DB().add(token: body.deviceToken, topic: body.apnsTopic, userId: me.id, production: body.production)
    }.recover { error in
        // code 19 means UNIQUE violation, so we already have this, which is fine
        guard case PerfectSQLite.SQLiteError.Error(let code, _) = error, code == 19 else {
            throw error
        }
    }
}
