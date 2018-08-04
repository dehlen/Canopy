import PerfectHTTP
import Foundation
import PromiseKit
import Roots

func createHookHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    guard let token = rq.header(.authorization) else {
        return response.completed(status: .forbidden)
    }
    guard let node = try? rq.decode(Node.self) else {
        return response.completed(status: .badRequest)
    }
    let api = GitHubAPI(oauthToken: token)
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
        let secret = UUID().ascii85
        let json: [String: Any] = [
            "name": "web",
            "events": ["*"],
            "config": [
                "url": hookUri,
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
    nodeId().then{ nodeId in
        try create().done {
            try DB().record(hook: $0.0, secret: $0.1, node: (node, nodeId))
        }
    }.done {
        response.completed()
    }.catch { error in
        response.appendBody(string: error.legibleDescription)
        response.completed(status: .badGateway)
    }
}

private struct Response: Decodable {
    let id: Int
}

private extension UUID {
    var ascii85: String {
        func convert(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> [UInt8] {
            if a == 0, b == 0, c == 0, d == 0 {
                return [122] // "z"
            }

            let x = UInt(a) * 52200625 + UInt(b) * 614125 + UInt(c) * 7225 + UInt(d)

            let c0 = UInt8((x / 52200625) % 85) + 33
            let c1 = UInt8((x / 614125) % 85) + 33
            let c2 = UInt8((x / 7225) % 85) + 33
            let c3 = UInt8((x / 85) % 85) + 33
            let c4 = UInt8(x % 85) + 33

            return [c0,c1,c2,c3,c4]
        }

        var aa = convert(uuid.0, uuid.1, uuid.2, uuid.3)
        aa += convert(uuid.4, uuid.5, uuid.6, uuid.7)
        aa += convert(uuid.8, uuid.9, uuid.10, uuid.11)
        aa += convert(uuid.12, uuid.13, uuid.14, uuid.15)
        return String(cString: aa)
    }
}

extension Node {
    var apiPath: String {
        switch self {
        case .organization:
            return "/\(ref)"
        case .repository(let owner, let name):
            return "/repos/\(owner)/\(name)"
        }
    }
}
