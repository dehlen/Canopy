import PerfectHTTP
import Foundation
import PromiseKit
import Roots

private enum E: Error {
    case failedToCreateSecret
}

private let salt = "yhjChvi>Bh9#3D3TJ4pZ9sgA[e9fp#BAEffjFvDww6BVLqsoun?cUz4L]sN{gyZG"

func createHookHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    guard let token = rq.header(.authorization) else {
        return response.completed(status: .forbidden)
    }
    guard let node = try? rq.decode(Node.self) else {
        return response.completed(status: .badRequest)
    }
    let api = GitHubAPI(oauthToken: token)

    print("Creating hook:", node.apiPath)

    firstly {
        api.createHook(for: node)
    }.done {
        response.completed()
    }.catch { error in
        if case PMKHTTPError.badStatusCode(422, _, _) = error {
            print(#function, "Hook already installed!")
            response.completed() // hook already installed!
        } else {
            response.appendBody(string: error.legibleDescription)
            response.completed(status: .badGateway)
        }
    }
}

//FIXME has side-effects for DB so should *not* be an extension
extension GitHubAPI {
    func createHook(for node: Node) -> Promise<Void> {
        let api = self
        let decoder = JSONDecoder()

        func nodeId() -> Promise<Int> {
            return firstly {
                URLSession.shared.dataTask(.promise, with: api.request(path: node.apiPath)).validate()
            }.map {
                try decoder.decode(Response.self, from: $0.data).id
            }
        }

        //TODO need to store repo/org nature, also we probably need to record this
        // for general subscriptions. So give it all some thought.

        func create() throws -> Promise<(Int, String)> {
            guard let secret = "\(salt)•\(node.ref)".md5 else {
                throw E.failedToCreateSecret
            }
            // ^^ we digest the secret so it is always the same for the same repository/org
            // this way GitHub overwrites subsequent attempts to create the webhooks, leaving
            // a single hook in such an eventuality
            let json: [String: Any] = [
                "name": "web",
                "events": ["*"],
                "config": [
                    "url": URL(.grapnel).absoluteString,
                    "content_type": "json",
                    "insecure_ssl": "0",
                    "secret": secret
                ]
            ]
            var rq = api.request(path: "\(node.apiPath)/hooks")
            rq.httpMethod = "POST"
            rq.httpBody = try JSONSerialization.data(withJSONObject: json)
            return firstly {
                URLSession.shared.dataTask(.promise, with: rq).validate()
            }.map {
                (try decoder.decode(Response.self, from: $0.data).id, secret)
            }
        }

        // sequentially since it is possible that a user *may* rename
        // the repo before we can create the hook, so since we cannot
        // create hooks by ID, get the ID first, then if hook creation
        // fails we haven't saved any bad data to our database yet.
        return nodeId().then{ nodeId in
            try create().done {
                try DB().record(hook: $0.0, secret: $0.1, node: (node, nodeId))
                alert(message: "Hook created for \(node.apiPath)")
            }
        }
    }
}

public func hookQueryHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    do {
        var ids = rq.queryParams.compactMap{ Int($1) }
        ids = try DB().whichAreHooked(ids: ids)
        try response.setBody(json: ids)
        response.completed()
    } catch {
        response.appendBody(string: error.legibleDescription)
        response.completed(status: .internalServerError)
    }
}

private struct Response: Decodable {
    let id: Int
}

import PerfectCrypto

private extension String {
    var md5: String? {
        guard let digest = digest(.md5) else { return nil }
        return Data(bytes: digest).base64EncodedString()
    }
}
