import enum PerfectSQLite.SQLiteError
import PerfectHTTP
import Foundation
import PromiseKit

func updateTokensHandler(request: HTTPRequest, response: HTTPResponse) {
    DispatchQueue.global().async(.promise) {
        try request.decode(UpdateTokens.self)
    }.then { token in
        updateTokens(oauth: token.oauth, device: token.device, apnsTopicId: token.apnsTopic)
    }.done {
        response.completed()
    }.catch {
        response.appendBody(string: $0.legibleDescription)
        response.completed(status: .badGateway)
    }
}

func updateTokens(oauth: String, device: String, apnsTopicId: String) -> Promise<Void> {
    return firstly {
        GitHubAPI(oauthToken: oauth).me()
    }.done { me in
        try DB().add(token: device, topic: apnsTopicId, userId: me.id)
    }.recover { error in
        // code 19 means UNIQUE violation, so we already have this, which is fine
        guard case PerfectSQLite.SQLiteError.Error(let code, _) = error, code == 19 else {
            throw error
        }
    }
}
