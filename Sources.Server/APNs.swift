import class PerfectHTTPServer.HTTP2Client
import PerfectCrypto
import Foundation
import PromiseKit
import CCurl

//TODO apns-collapse-id

private enum E: Error {
    case badToken
    case other(Int, String?)
    case fundamental
}

private var curlHandle: UnsafeMutableRawPointer = {
    let curlHandle = curl_easy_init()
    //curlHelperSetOptBool(curlHandle, CURLOPT_VERBOSE, CURL_TRUE)
    curlHelperSetOptInt(curlHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2_0)
    return curlHandle!
}()

let qq = DispatchQueue(label: "cURL HTTP2 serial-Q")

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

func send(to confs: [APNSConfiguration: [String]], note: APNsNotification) throws {
    //TODO parallel
    let json = try JSONSerialization.data(withJSONObject: note.payload)
    for (conf, tokens) in confs where conf.isProduction {
        for token in tokens {
            send(to: token, topic: conf.topic, json: json)
        }
    }
}

func send(to token: String, topic: String, _ note: APNsNotification) throws {
    let json = try JSONSerialization.data(withJSONObject: note.payload)
    try qq.sync { try _send(to: token, topic: topic, json: json) }
}

private func send(to token: String, topic: String, json: Data) {
    qq.async {
        do {
            print("Sending to:", token)
            try _send(to: token, topic: topic, json: json)
            print("OK")
        } catch E.badToken {
            print("Deleting bad token:", token)
            _ = try? DB().delete(apnsDeviceToken: token)
        } catch {
            print(error)
        }
    }
}

private func _send(to token: String, topic: String, json: Data) throws {
#if os(Linux)
    dispatchPrecondition(condition: .onQueue(qq))
#endif

    // Set URL
    var url = "https://api.push.apple.com/3/device/\(token)"
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
        print(String(data: writeStorage.data, encoding: .utf8) ?? "OK")
    case 400:
        guard let str = String(data: writeStorage.data, encoding: .utf8) else {
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
            throw E.other(400, String(data: writeStorage.data, encoding: .utf8))
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
            let pem = try! PEMKey(pemPath: "AuthKey_5354D789X6.p8")
            lastJwt = try! jwt.sign(alg: JWT.Alg.es256, key: pem, headers: ["kid": "5354D789X6"])
            sigtime = now
            return lastJwt
        }
    } else {
        return q.sync{ lastJwt }
    }
}

func alert(message: String, function: StaticString = #function) {
    print(function, message)

    guard let confs = try? DB().mxcl() else {
        return
    }
    let apns = APNsNotification.alert(body: message, title: nil, category: nil, threadId: nil, extra: nil)
    for foo in confs where foo.key.isProduction {
        _ = try? send(to: confs, note: apns)
    }
}


//
//  CurlVersionHelper.swift
//  VaporAPNS
//
//  Created by Matthijs Logemann on 01/01/2017.
//
//

class CurlVersionHelper {
    public enum Result {
        case ok
        case old(got: String, wanted: String)
        case noHTTP2
        case unknown
    }

    public func checkVersion() {
        switch checkVersionNum() {
        case .old(let got, let wanted):
            print("Your current version of curl (\(got)) is out of date!")
            print("APNS needs at least \(wanted).")
        case .noHTTP2:
            print("Your current version of curl lacks HTTP2!")
            print("APNS will not work with this version of curl.")
        default:
            break
        }
    }

    private func checkVersionNum() -> Result {
        let version = curl_version_info(CURLVERSION_FOURTH)
        let verBytes = version?.pointee.version
        let versionString = String.init(cString: verBytes!)
        //        return .old

        guard checkVersionNumber(versionString, "7.51.0") >= 0 else {
            return .old(got: versionString, wanted: "7.51.0")
        }

        let features = version?.pointee.features

        if ((features! & CURL_VERSION_HTTP2) == CURL_VERSION_HTTP2) {
            return .ok
        }else {
            return .noHTTP2
        }
    }

    private func checkVersionNumber(_ strVersionA: String, _ strVersionB: String) -> Int{
        var arrVersionA = strVersionA.split(separator: ".").map({ Int($0) })
        guard arrVersionA.count == 3 else {
            fatalError("Wrong curl version scheme! \(strVersionA)")
        }

        var arrVersionB = strVersionB.split(separator: ".").map({ Int($0) })
        guard arrVersionB.count == 3 else {
            fatalError("Wrong curl version scheme! \(strVersionB)")
        }

        let intVersionA = (100000000 * arrVersionA[0]!) + (1000000 * arrVersionA[1]!) + (10000 * arrVersionA[2]!)
        let intVersionB = (100000000 * arrVersionB[0]!) + (1000000 * arrVersionB[1]!) + (10000 * arrVersionB[2]!)

        if intVersionA > intVersionB {
            return 1
        } else if intVersionA < intVersionB {
            return -1
        } else {
            return 0
        }
    }
}
