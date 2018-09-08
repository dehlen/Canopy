import class PerfectHTTPServer.HTTP2Client
import PerfectCrypto
import Foundation
import PromiseKit
import CCurl

private enum E: Error {
    case badToken
    case other(Int, String?)
    case fundamental
}

private let qq = DispatchQueue(label: "cURL HTTP2 serial-Q")

private class APNs {
    let curlHandle: UnsafeMutableRawPointer
    let url: String

    init(production: Bool) {
        if production {
            url = "https://api.push.apple.com/3/device/"
        } else {
            url = "https://api.sandbox.push.apple.com/3/device/"
        }
        curlHandle = curl_easy_init()
        //curlHelperSetOptBool(curlHandle, CURLOPT_VERBOSE, CURL_TRUE)
        curlHelperSetOptInt(curlHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2_0)
    }

    func send(to token: String, topic: String, json: Data, id: String?, collapseId: String?) {
        qq.async {
            do {
                try _send(topic: topic, json: json, id: id, collapseId: collapseId, curlHandle: self.curlHandle, url: self.url + token)
            } catch E.badToken {
                do {
                    print("APNs: deleting bad-token:", token)
                    try DB().delete(apnsDeviceToken: token)
                } catch {
                    print("DB: error:", error)
                }
            } catch {
                print("APNs: error:", error)
            }
        }
    }
}

private let release = APNs(production: true)
private let debug = APNs(production: false)

extension APNsNotification {
    func send(to: [APNSConfiguration: [String]]) throws {
        let json = try JSONSerialization.data(withJSONObject: payload)
        for (conf, tokens) in to {
            let apns = conf.isProduction ? release : debug
            for token in tokens {
                apns.send(to: token, topic: conf.topic, json: json, id: id, collapseId: collapseId)
            }
        }
    }
}

enum APNsNotification {
    case silent([String: Any])
    case alert(body: String, title: String?, subtitle: String?, category: String?, threadId: String?, extra: [String: Any]?, id: String?, collapseId: String?)

    init(body: String, title: String? = nil, subtitle: String? = nil, category: String? = nil, threadId: String? = nil, extra: [String: Any]? = nil, id: String? = nil, collapseId: String? = nil) {
        self = .alert(body: body, title: title, subtitle: subtitle, category: category, threadId: threadId, extra: extra, id: id, collapseId: collapseId)
    }

    fileprivate var payload: [String: Any] {
        switch self {
        case .silent(let extra):
            var payload = extra
            payload["aps"] = ["content-available": 1]
            return payload
        case .alert(let body, let title, let subtitle, let category, let threadId, let extra, _, _):
            var alert = ["body": body]
            alert["title"] = title
            alert["subtitle"] = subtitle

            var aps: [String: Any] = ["alert": alert]
            aps["thread-id"] = threadId
            aps["category"] = category

            var payload: [String: Any] = extra ?? [:]
            payload["aps"] = aps

            return payload
        }
    }

    var id: String? {
        switch self {
        case .alert(_, _, _, _, _, _, let id, _):
            return id
        case .silent:
            return nil
        }
    }

    var collapseId: String? {
        switch self {
        case .alert(_, _, _, _, _, _, _, let id):
            return id
        case .silent:
            return nil
        }
    }
}

private func _send(topic: String, json: Data, id: String?, collapseId: String?, curlHandle: UnsafeMutableRawPointer, url: String) throws {
#if os(Linux)
    dispatchPrecondition(condition: .onQueue(qq))
#endif

    // Set URL
    var url = url
    url.withCString {
        var str = UnsafeMutablePointer(mutating: $0)
        curlHelperSetOptString(curlHandle, CURLOPT_URL, str)
    }

    curlHelperSetOptInt(curlHandle, CURLOPT_PORT, 443)
    curlHelperSetOptBool(curlHandle, CURLOPT_FOLLOWLOCATION, CURL_TRUE)
    curlHelperSetOptBool(curlHandle, CURLOPT_POST, CURL_TRUE)
    curlHelperSetOptBool(curlHandle, CURLOPT_HEADER, CURL_TRUE) // Tell CURL to add headers

    // setup payload
    var json = json
    json.append(0)
    json.withUnsafeMutableBytes {
        _ = curlHelperSetOptString(curlHandle, CURLOPT_POSTFIELDS, $0)
    }
    curlHelperSetOptInt(curlHandle, CURLOPT_POSTFIELDSIZE, json.count - 1)

    //Headers
    var curlHeaders: UnsafeMutablePointer<curl_slist>?
    curlHeaders = curl_slist_append(curlHeaders, "Authorization: bearer \(jwt)")
    curlHeaders = curl_slist_append(curlHeaders, "User-Agent: Canopy, Codebase LLC")
    curlHeaders = curl_slist_append(curlHeaders, "apns-topic: \(topic)")
    if let id = id {
        curlHeaders = curl_slist_append(curlHeaders, "apns-id: \(id)")
    }
    if let collapseId = collapseId {
        curlHeaders = curl_slist_append(curlHeaders, "apns-collapse-id: \(collapseId)")
    }
    curlHeaders = curl_slist_append(curlHeaders, "Accept: application/json")
    curlHeaders = curl_slist_append(curlHeaders, "Content-Type: application/json; charset=utf-8")
    curlHelperSetOptHeaders(curlHandle, curlHeaders)
    defer {
        if let curlHeaders = curlHeaders {
            curl_slist_free_all(curlHeaders)
        }
    }

    class WriteStorage {
        var data = Data()
        var string: String? {
            return String(data: data.dropLast(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // Get response
    var writeStorage = WriteStorage()
    curlHelperSetOptWriteFunc(curlHandle, &writeStorage) { (ptr, size, nMemb, privateData) -> Int in
        let storage = privateData?.assumingMemoryBound(to: WriteStorage.self)
        let realsize = size * nMemb

        var bytes = [UInt8](repeating: 0, count: realsize)
        memcpy(&bytes, ptr!, realsize)

        for byte in bytes {
            storage?.pointee.data.append(byte)
        }
        return realsize
    }

    let ret = curl_easy_perform(curlHandle)

    if ret != CURLE_OK {
        throw E.fundamental
    }
    var code = 500
    curlHelperGetInfoLong(curlHandle, CURLINFO_RESPONSE_CODE, &code)

    switch code {
    case 200..<300:
        print(writeStorage.string ?? "NORSP \(writeStorage.data.count)")
    case 400:
        guard let str = writeStorage.string else {
            throw E.other(400, nil)
        }
        let parts = str.components(separatedBy: "\r\n\r\n")
        guard parts.count == 2, let data = parts[1].data(using: .utf8) else {
            throw E.other(400, str)
        }
        struct Response: Decodable {
            let reason: String
        }
        if (try? JSONDecoder().decode(Response.self, from: data))?.reason == "BadDeviceToken" {
            throw E.badToken
        } else {
            throw E.other(400, writeStorage.string)
        }
    case 410:
        throw E.badToken
    default:
        throw E.other(code, String(data: writeStorage.data, encoding: .utf8))
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
            let payload: [String: Any] = ["iss": teamId, "iat": Int(now.timeIntervalSince1970)]
            let jwt = JWTCreator(payload: payload)!
            let pem = try! PEMKey(pemPath: "../AuthKey_5354D789X6.p8")
            lastJwt = try! jwt.sign(alg: JWT.Alg.es256, key: pem, headers: ["kid": "5354D789X6"])
            sigtime = now
            return lastJwt
        }
    } else {
        return q.sync{ lastJwt }
    }
}

func alert(message: String, function: StaticString = #function) {
    do {
        print(function, message)
        try APNsNotification(body: message).send(to: DB().mxcl())
    } catch {
        print("alert: error:", error)
    }
}
