import class PerfectHTTPServer.HTTP2Client
import PerfectCrypto
import Foundation
import PromiseKit

//TODO apns-collapse-id

//NOTE this is a bad implementation, we can only send one notification at a time
// while we should be able to open multiple streams (docs say only after one successful
// push though) as a result the speed is bad.

private enum E: Error {
    case noConnect
}

private var lastPing = Date(timeIntervalSince1970: 0)
private var queue = Guarantee()
private var _http: Guarantee<HTTP2Client>?
let qq = DispatchQueue(label: "HTTP2Client")
private var http: Guarantee<HTTP2Client> {
    func _reconnect() -> Guarantee<HTTP2Client> {
        print("RECONNECTING")
        return Guarantee { seal in
            let http = HTTP2Client()
            http.connect(host: "api.push.apple.com", port: 443, ssl: true, timeoutSeconds: 5) {
                if $0 {
                    seal(http)
                } else {
                    qq.async {
                        // can't reject or we'll never try to reconnect!
                        _http = nil
                    }
                }
            }
        }
    }
    func reconnect() -> Guarantee<HTTP2Client> {
        return qq.sync {
            _http = _reconnect()
            lastPing = Date()
            return _http!
        }
    }
    func ping(with http: HTTP2Client) -> Guarantee<HTTP2Client> {
        print("ping")
        return qq.sync {
            _http = Guarantee { seal in
                http.sendPing {
                    print("ping result", $0)
                    if $0 {
                        seal(http)
                    } else {
                        _reconnect().done(seal)
                    }
                }
            }
            lastPing = Date()
            return _http!
        }
    }
    if let http = qq.sync(execute: { _http }) {
        if let http = http.value, http.isConnected, lastPing.timeIntervalSinceNow < -60 {
            return ping(with: http)
        } else {
            return http
        }
    } else {
        return reconnect()
    }
}

enum APNsNotification {
    case silent([String: Any])
    case alert(body: String, title: String?, category: String?, threadId: String?, extra: [String: Any]?)

    fileprivate var payload: [String: Any] {
        switch self {
        case .silent(let extra):
            var payload = extra
            payload["aps"] = ["content-available": 1]
            return payload
        case .alert(let body, let title, let category, let threadId, let extra):
            var alert = ["body": body]
            alert["title"] = title

            var aps: [String: Any] = ["alert": alert]
            aps["thread-id"] = threadId
            aps["category"] = category

            var payload: [String: Any] = extra ?? [:]
            payload["aps"] = aps

            return payload
        }
    }
}

//TODO re-encoding json again and again is not so efficient
func send(to tokens: [String], topic: String, _ note: APNsNotification) throws {
    // probably parallel this
    let json = try JSONSerialization.data(withJSONObject: note.payload)

    func send(to token: String, http: HTTP2Client) -> Guarantee<Void> {
        print("Sending \(token) (\(topic))")

        let rq = http.createRequest()
        rq.method = .post
        rq.postBodyBytes = [UInt8](json)
        rq.setHeader(.contentType, value: "application/json; charset=utf-8")
        rq.setHeader(.custom(name: "apns-topic"), value: topic)
        rq.setHeader(.authorization, value: "bearer \(jwt)")
        rq.path = "/3/device/\(token)"
        return Guarantee { seal in
            http.sendRequest(rq) {
                switch $0?.status {
                case .badRequest?:
                    print($0!.status)
                    struct Response: Decodable {
                        let reason: String
                    }
                    //Perfect sucks, why is this a string ffs?
                    if let data = $1?.data(using: .utf8), (try? JSONDecoder().decode(Response.self, from: data))?.reason == "BadDeviceToken" {
                        fallthrough
                    }
                case .gone?:
                    print($0!.status)
                    try! DB().delete(apnsDeviceToken: token)
                case nil:
                    print("NO RESPONSE PROVIDED", $1 ?? "Perfect sucks")
                default:
                    print($0!.status)
                }

                seal(())
            }
        }
    }

    qq.sync {
        for token in tokens {
            queue = queue.then {
                http
            }.then { http in
                send(to: token, http: http)
            }
        }
    }
}

private let q = DispatchQueue(label: #file, attributes: .concurrent)

private var sigtime = Date(timeIntervalSince1970: 0)
private var lastJwt: String!
private var jwt: String {
    //TODO thread-safety
    let now = Date()
    let t = q.sync{ sigtime }
    if t.timeIntervalSince(now) < -3590 {
        return q.sync(flags: .barrier) {
            sigtime = now
            lastJwt = _jwt(now: now)
            return lastJwt
        }
    } else {
        return q.sync{ lastJwt }
    }
}
private func _jwt(now: Date) -> String {
    let payload: [String: Any] = ["iss": teamId, "iat": Int(now.timeIntervalSince1970)]
    let jwt = JWTCreator(payload: payload)!
    let pem = try! PEMKey(pemPath: "AuthKey_5354D789X6.p8")
    let sig = try! jwt.sign(alg: JWT.Alg.es256, key: pem, headers: ["kid": "5354D789X6"])
    return sig
}

func alert(message: String, function: StaticString = #function) {
    print(function, message)

    guard let confs = try? DB().mxcl() else {
        return
    }
    let apns = APNsNotification.alert(body: message, title: nil, category: nil, threadId: nil, extra: nil)
    for (conf, tokens) in confs where conf.isProduction {
        _ = try? send(to: tokens, topic: conf.topic, apns)
    }
}
